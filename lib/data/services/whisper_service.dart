import 'dart:io' show File, Directory;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/audio_converter.dart';
import 'package:memex/data/services/transcription_isolate.dart';
import 'package:archive/archive_io.dart';

/// Service for on-device speech-to-text using sherpa-onnx + NVIDIA Parakeet
/// TDT 0.6B v3 (25 European languages, Portuguese included; F2-11). The
/// class keeps its old name so callers stay unchanged.
///
/// Handles model download, caching, and transcription.
class WhisperService {
  static final WhisperService _instance = WhisperService._();
  static WhisperService get instance => _instance;
  WhisperService._();

  final Logger _logger = getLogger('WhisperService');

  static const _modelDirName = 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8';
  static const _encoderFileName = 'encoder.int8.onnx';
  static const _decoderFileName = 'decoder.int8.onnx';
  static const _joinerFileName = 'joiner.int8.onnx';
  static const _tokensFileName = 'tokens.txt';
  static const _modelFileNames = {
    _encoderFileName,
    _decoderFileName,
    _joinerFileName,
    _tokensFileName,
  };

  /// Earlier local models (SenseVoice without Portuguese, then Whisper
  /// turbo); their files are removed when Parakeet is downloaded.
  static const _legacyModelDirNames = [
    'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17',
    'sherpa-onnx-whisper-turbo',
  ];

  /// Download URL
  static const _downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$_modelDirName.tar.bz2';

  TranscriptionIsolate? _bgIsolate;

  /// Model directory path.
  Future<String> _modelDir() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_modelDirName';
  }

  /// Whether the model files exist locally.
  Future<bool> isModelDownloaded() async {
    final dir = await _modelDir();
    return _modelFileNames.every((name) => File('$dir/$name').existsSync());
  }

  /// Delete any downloaded or partially downloaded local model files.
  Future<bool> deleteDownloadedModel() async {
    dispose();

    final dirPath = await _modelDir();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return false;

    await dir.delete(recursive: true);
    _logger.info('Deleted speech model directory: $dirPath');
    return true;
  }

  /// Download model files with progress callback.
  /// [onProgress] receives values from 0.0 to 1.0.
  Future<void> downloadModel({
    required ValueChanged<double> onProgress,
  }) async {
    final dir = await _modelDir();
    await Directory(dir).create(recursive: true);

    // Download tar.bz2 archive from GitHub
    _logger.info('Downloading Parakeet model from $_downloadUrl');
    final tmpFile = File('$dir/model.tar.bz2');
    await _downloadFile(
      _downloadUrl,
      tmpFile.path,
      onProgress: (p) => onProgress(p * 0.9),
    );

    // Extract on disk in a background isolate: the archive is ~470 MB, too
    // big to decompress in memory on the UI isolate.
    _logger.info('Extracting model archive...');
    onProgress(0.9);
    final archivePath = tmpFile.path;
    await Isolate.run(
      () => extractModelFiles(archivePath, dir, _modelFileNames),
    );
    if (tmpFile.existsSync()) await tmpFile.delete();

    final support = (await getApplicationSupportDirectory()).path;
    for (final name in _legacyModelDirNames) {
      final legacy = Directory('$support/$name');
      if (legacy.existsSync()) await legacy.delete(recursive: true);
    }
    onProgress(1.0);

    _logger.info('Parakeet model downloaded to $dir');
  }

  /// Extracts the files named in [names] from the `.tar.bz2` at [archivePath]
  /// into [outDir], streaming through a temporary `.tar` on disk. Each file is
  /// written as `.part` and renamed, so an interrupted extraction never
  /// leaves a truncated model that [isModelDownloaded] would accept.
  @visibleForTesting
  static void extractModelFiles(
    String archivePath,
    String outDir,
    Set<String> names,
  ) {
    final tarPath = '$archivePath.tar';
    final compressed = InputFileStream(archivePath);
    final tarOut = OutputFileStream(tarPath);
    try {
      BZip2Decoder().decodeStream(compressed, tarOut);
    } finally {
      compressed.closeSync();
      tarOut.closeSync();
    }
    final tarIn = InputFileStream(tarPath);
    try {
      for (final file in TarDecoder().decodeStream(tarIn)) {
        final name = file.name.split('/').last;
        if (!file.isFile || !names.contains(name)) continue;
        final part = OutputFileStream('$outDir/$name.part');
        try {
          file.writeContent(part);
        } finally {
          part.closeSync();
        }
        File('$outDir/$name.part').renameSync('$outDir/$name');
      }
    } finally {
      tarIn.closeSync();
      File(tarPath).deleteSync();
    }
  }

  Future<void> _downloadFile(
    String url,
    String savePath, {
    required ValueChanged<double> onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    final totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;
    final sink = File(savePath).openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress(receivedBytes / totalBytes);
      }
    }
    await sink.close();
  }

  /// Max audio duration in seconds for transcription.
  /// Longer audio will be truncated to avoid OOM.
  static const int _maxAudioSeconds = 60;

  /// Transcribe an audio file to text.
  /// Supports WAV directly; other formats (m4a, mp3, etc.) are auto-converted.
  /// Audio longer than 60 seconds is truncated unless [skipLengthCheck] is true.
  Future<String?> transcribe(String audioPath,
      {bool skipLengthCheck = false}) async {
    try {
      if (!await isModelDownloaded()) {
        _logger.warning('Speech model not downloaded yet');
        return null;
      }

      ensureInitialized();

      // Convert to WAV 16kHz mono if needed
      final wavPath = await AudioConverter.toWav16kMono(audioPath);
      if (wavPath == null) {
        _logger.severe('Audio conversion failed for: $audioPath');
        return null;
      }

      // Check file size — reject very large files to avoid OOM
      // 16kHz × 2 bytes × 60s = ~1.92MB + 44 bytes header
      final wavFile = File(wavPath);
      final fileSize = await wavFile.length();
      if (!skipLengthCheck) {
        const maxSize = 16000 * 2 * _maxAudioSeconds + 44;
        if (fileSize > maxSize * 2) {
          _logger.warning(
              'Audio too long (${fileSize ~/ 1024}KB), max ~${_maxAudioSeconds}s. Skipping.');
          if (wavPath != audioPath) {
            try {
              wavFile.deleteSync();
            } catch (_) {}
          }
          return null;
        }
      }

      _logger.info('Transcribing audio: $wavPath (${fileSize ~/ 1024}KB)');

      final waveData = sherpa.readWave(wavPath);

      // Truncate samples to max duration to prevent OOM
      const maxSamples = 16000 * _maxAudioSeconds;
      final samples = (!skipLengthCheck && waveData.samples.length > maxSamples)
          ? Float32List.fromList(waveData.samples.sublist(0, maxSamples))
          : waveData.samples;

      final text = await transcribeSamples(samples);
      // Clean up converted temp file
      if (wavPath != audioPath) {
        try {
          File(wavPath).deleteSync();
        } catch (_) {}
      }
      _logger.info(
          'Transcription complete: ${text?.substring(0, text.length.clamp(0, 100))}');
      return text;
    } catch (e) {
      _logger.severe('Transcription failed: $e');
      return null;
    }
  }

  /// Dispose the background isolate.
  void dispose() {
    _bgIsolate?.dispose();
    _bgIsolate = null;
  }

  /// Parakeet has no 30 s limit, but on the owner's notes 30 s pieces
  /// transcribed better than the whole 5 min at once (31% vs 38% distance to
  /// Whisper large-v3, F2-11 section 7) and keep memory flat on long audio.
  static const int _chunkSamples = 16000 * 30;

  /// Pieces shorter than 0.1 s hold no word, and a few samples crashed the
  /// native Whisper decoder (sherpa-onnx 1.13.2); kept as a cheap guard.
  static const int _minChunkSamples = 1600;

  /// Each cut is searched in the last 10 s before the 30 s mark.
  static const int _searchSamples = 16000 * 10;

  /// Splits [samples] into consecutive pieces of at most 30 s, cutting at the
  /// quietest 0.1 s near each 30 s mark so a pause, not a word, is split.
  /// A piece under 0.1 s is dropped.
  /// shortcut: "quietest" is plain energy, so steady loud noise with no pause
  /// still gets cut mid-word; upgrade to the Silero VAD if that shows up.
  @visibleForTesting
  static List<Float32List> splitAtPauses(Float32List samples) {
    const frame = _minChunkSamples;
    final pieces = <Float32List>[];
    var start = 0;
    while (samples.length - start > _chunkSamples) {
      final from = start + _chunkSamples - _searchSamples;
      final to = start + _chunkSamples;
      // Prefix sums of squared samples give each frame's energy in O(1).
      final energy = Float64List(to - from + 1);
      for (var i = from; i < to; i++) {
        energy[i - from + 1] = energy[i - from] + samples[i] * samples[i];
      }
      var best = to - frame;
      var bestEnergy = double.infinity;
      for (var f = from; f + frame <= to; f += frame ~/ 10) {
        final e = energy[f + frame - from] - energy[f - from];
        // `<=` keeps the latest of equally quiet frames: fewer, longer pieces.
        if (e <= bestEnergy) {
          bestEnergy = e;
          best = f;
        }
      }
      final cut = best + frame ~/ 2;
      pieces.add(samples.sublist(start, cut));
      start = cut;
    }
    if (samples.length - start >= _minChunkSamples) {
      pieces.add(samples.sublist(start));
    }
    return pieces;
  }

  /// Transcribe speech (Float32List samples at 16kHz) of any length.
  /// Runs in a background Isolate so the UI thread is not blocked.
  Future<String?> transcribeSamples(Float32List samples) async {
    try {
      if (!await isModelDownloaded()) return null;
      await _ensureBgIsolate();
      final parts = <String>[];
      for (final chunk in splitAtPauses(samples)) {
        final text = await _bgIsolate!.transcribe(chunk);
        if (text != null && text.isNotEmpty) parts.add(text);
      }
      final text = parts.join(' ').trim();
      if (text.isEmpty) return null;
      _logger.info(
          'Transcribed (bg, ${parts.length} parts): ${text.substring(0, text.length.clamp(0, 80))}');
      return text;
    } catch (e) {
      _logger.severe('Transcription failed: $e');
      return null;
    }
  }

  /// Ensure the background isolate is running.
  Future<void> _ensureBgIsolate() async {
    if (_bgIsolate != null && _bgIsolate!.isReady) return;
    _bgIsolate = TranscriptionIsolate();
    final dir = await _modelDir();
    await _bgIsolate!.start(
      encoderPath: '$dir/$_encoderFileName',
      decoderPath: '$dir/$_decoderFileName',
      joinerPath: '$dir/$_joinerFileName',
      tokensPath: '$dir/$_tokensFileName',
    );
  }

  /// Ensure sherpa-onnx bindings are initialized.
  void ensureInitialized() {
    sherpa.initBindings();
  }

  /// Model download size in MB (the release archive).
  static const double modelSizeMB = 470;
}
