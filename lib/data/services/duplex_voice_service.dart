import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:memex/data/services/whisper_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/wakelock_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Finds where speech starts and ends in 16 kHz mono audio.
abstract class SpeechDetector {
  /// Samples per [accept] call.
  static const int windowSize = 512;

  void accept(Float32List window);

  /// True while speech is being heard.
  bool get isSpeech;

  /// The next finished utterance, or null when there is none.
  Float32List? takeSegment();

  /// Forgets audio heard so far.
  void reset();

  void free();
}

/// Audio side of the duplex voice conversation (F7-03): the microphone stream
/// cut into utterances by voice detection, and the system speech engine.
///
/// Audio lives only in memory. Nothing here writes it to disk.
class DuplexVoiceService {
  DuplexVoiceService({
    Future<bool> Function()? requestPermission,
    Future<Stream<Uint8List>> Function()? startStream,
    Future<void> Function()? stopStream,
    Future<SpeechDetector> Function()? createDetector,
    Future<bool> Function(String text, String locale)? speak,
    Future<void> Function()? stopSpeaking,
    Future<void> Function()? shutdownSpeech,
    Future<void> Function(bool on)? keepAwake,
  })  : _requestPermission = requestPermission ?? _defaultPermission,
        _createDetector = createDetector ?? _SileroDetector.create,
        _speak = speak ?? _platformSpeak,
        _stopSpeaking = stopSpeaking ?? (() => _tts.invokeMethod('stop')),
        _shutdownSpeech =
            shutdownSpeech ?? (() => _tts.invokeMethod('shutdown')),
        _keepAwake = keepAwake ?? _defaultKeepAwake {
    if (startStream != null && stopStream != null) {
      _startStream = startStream;
      _stopStream = stopStream;
    } else {
      // Created on first use: the plugin is not available in widget tests.
      AudioRecorder? recorder;
      _startStream = () {
        recorder = AudioRecorder();
        return recorder!.startStream(micConfig);
      };
      _stopStream = () async {
        final active = recorder;
        recorder = null;
        await active?.stop();
        await active?.dispose();
      };
    }
  }

  /// The platform echo canceller is what keeps the app from hearing its own
  /// voice. Values NOT measured on the S25 yet (docs/fases/F7-03-voz-duplex.md);
  /// tools/f703_probe compares the alternatives.
  static const micConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    echoCancel: true,
    noiseSuppress: true,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
    ),
  );

  static const _tts = MethodChannel('com.memexlab.memex/tts');
  static const _wakeReason = 'duplex_voice';
  static final _logger = getLogger('DuplexVoiceService');

  static Future<bool> _defaultPermission() async =>
      (await Permission.microphone.request()).isGranted;

  static Future<bool> _platformSpeak(String text, String locale) async =>
      await _tts.invokeMethod<bool>('speak', {
        'text': text,
        'locale': locale,
      }) ??
      false;

  static Future<void> _defaultKeepAwake(bool on) => on
      ? WakelockManager.acquire(_wakeReason)
      : WakelockManager.release(_wakeReason);

  final Future<bool> Function() _requestPermission;
  final Future<SpeechDetector> Function() _createDetector;
  final Future<bool> Function(String text, String locale) _speak;
  final Future<void> Function() _stopSpeaking;
  final Future<void> Function() _shutdownSpeech;
  final Future<void> Function(bool on) _keepAwake;
  late final Future<Stream<Uint8List>> Function() _startStream;
  late final Future<void> Function() _stopStream;

  StreamSubscription<Uint8List>? _sub;
  SpeechDetector? _detector;
  final List<double> _samples = [];
  bool _wasSpeech = false;
  bool _discardInput = false;

  /// True while the microphone stream is open.
  bool get micOpen => _sub != null;

  /// While true, microphone audio is dropped unheard (the app is busy with the
  /// previous utterance).
  bool get discardInput => _discardInput;
  set discardInput(bool value) {
    _discardInput = value;
    if (value) _forgetAudio();
  }

  Future<bool> requestPermission() => _requestPermission();

  /// Opens the microphone. [onSpeechStart] fires when someone starts talking,
  /// [onUtterance] with the samples once they stop, and [onError] when the
  /// stream fails or ends by itself (e.g. permission revoked); the caller must
  /// then [release].
  Future<void> openMic({
    required void Function() onSpeechStart,
    required void Function(Float32List samples) onUtterance,
    required void Function(Object error) onError,
  }) async {
    if (micOpen) return;
    _detector ??= await _createDetector();
    _forgetAudio();
    final stream = await _startStream();
    _sub = stream.listen(
      (chunk) {
        try {
          _feed(chunk, onSpeechStart, onUtterance);
        } catch (e, stack) {
          _logger.severe('Voice detection failed', e, stack);
          onError(e);
        }
      },
      onError: (Object e) => onError(e),
      onDone: () => onError(StateError('microphone stream ended')),
    );
    await _keepAwake(true);
  }

  void _feed(
    Uint8List chunk,
    void Function() onSpeechStart,
    void Function(Float32List samples) onUtterance,
  ) {
    final detector = _detector;
    if (detector == null || _discardInput) return;
    // Copied so the 16-bit view is aligned whatever the plugin hands over.
    final pcm = Uint8List.fromList(chunk).buffer.asInt16List(
          0,
          chunk.length ~/ 2,
        );
    for (final sample in pcm) {
      _samples.add(sample / 32768.0);
    }
    while (_samples.length >= SpeechDetector.windowSize) {
      detector.accept(
        Float32List.fromList(_samples.sublist(0, SpeechDetector.windowSize)),
      );
      _samples.removeRange(0, SpeechDetector.windowSize);
      final speech = detector.isSpeech;
      if (speech && !_wasSpeech) onSpeechStart();
      _wasSpeech = speech;
      // A callback may have closed the microphone or asked to drop input.
      if (_detector == null || _discardInput) return;
    }
    for (var segment = detector.takeSegment();
        segment != null;
        segment = _detector?.takeSegment()) {
      onUtterance(segment);
      if (_discardInput) return;
    }
  }

  void _forgetAudio() {
    _samples.clear();
    _wasSpeech = false;
    _detector?.reset();
  }

  /// Stops and releases the microphone. Safe to call when already closed.
  Future<void> closeMic() async {
    final sub = _sub;
    _sub = null;
    _forgetAudio();
    // Not awaited: cancel() on a plain controller can stay pending, and the
    // stop below ends the recording anyway.
    unawaited(sub?.cancel() ?? Future<void>.value());
    try {
      if (sub != null) await _stopStream();
    } finally {
      await _keepAwake(false);
    }
  }

  /// Speaks [text]; true when it ended by itself, false when stopped.
  Future<bool> speak(String text, String locale) => _speak(text, locale);

  Future<void> stopSpeaking() => _stopSpeaking();

  /// Closes the microphone and the speech engine. Every step runs even when
  /// an earlier one fails, so no audio resource is left open.
  Future<void> release() async {
    Object? firstError;
    for (final step in [closeMic, _stopSpeaking, _shutdownSpeech]) {
      try {
        await step();
      } catch (e, stack) {
        _logger.warning('Could not release an audio resource', e, stack);
        firstError ??= e;
      }
    }
    _detector?.free();
    _detector = null;
    _discardInput = false;
    if (firstError != null) throw firstError;
  }
}

/// Silero VAD from sherpa-onnx, the same model the live transcript uses.
class _SileroDetector implements SpeechDetector {
  _SileroDetector(this._vad);

  static Future<SpeechDetector> create() async {
    WhisperService.instance.ensureInitialized();
    final dir = await getApplicationSupportDirectory();
    final model = File('${dir.path}/silero_vad.onnx');
    if (!model.existsSync()) {
      final data = await rootBundle.load('assets/silero_vad.onnx');
      await model.writeAsBytes(data.buffer.asUint8List());
    }
    return _SileroDetector(
      sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: model.path,
            // NOT measured on the S25 yet. 0.7 s of silence ends the turn;
            // 0.25 s of speech is needed before it counts, which also keeps a
            // click or an echo burst from interrupting the reply.
            threshold: 0.5,
            minSilenceDuration: 0.7,
            minSpeechDuration: 0.25,
            windowSize: SpeechDetector.windowSize,
            // shortcut: a turn longer than 30 s is cut in two; join the pieces
            // if long dictation by voice becomes a use.
            maxSpeechDuration: 30,
          ),
          sampleRate: 16000,
          numThreads: 1,
          debug: false,
        ),
        bufferSizeInSeconds: 60,
      ),
    );
  }

  final sherpa.VoiceActivityDetector _vad;

  @override
  void accept(Float32List window) => _vad.acceptWaveform(window);

  @override
  bool get isSpeech => _vad.isDetected();

  @override
  Float32List? takeSegment() {
    if (_vad.isEmpty()) return null;
    final samples = _vad.front().samples;
    _vad.pop();
    return samples;
  }

  @override
  void reset() => _vad.reset();

  @override
  void free() => _vad.free();
}
