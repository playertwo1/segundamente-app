import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/transcription_isolate.dart';
import 'package:memex/data/services/whisper_service.dart';

void main() {
  test('local model is Parakeet as a NeMo transducer on CPU', () {
    final config = TranscriptionIsolate.parakeetConfig(
      encoderPath: 'e.onnx',
      decoderPath: 'd.onnx',
      joinerPath: 'j.onnx',
      tokensPath: 't.txt',
    );
    expect(config.model.transducer.encoder, 'e.onnx');
    expect(config.model.transducer.decoder, 'd.onnx');
    expect(config.model.transducer.joiner, 'j.onnx');
    expect(config.model.modelType, 'nemo_transducer');
    expect(config.model.whisper.encoder, isEmpty);
    expect(config.model.tokens, 't.txt');
    expect(config.model.provider, 'cpu');
    expect(config.model.senseVoice.model, isEmpty);
  });

  /// Loud "speech" everywhere except silent gaps at the given seconds.
  Float32List speechWithPauses(int seconds, List<double> pauses) {
    final s = Float32List(16000 * seconds);
    for (var i = 0; i < s.length; i++) {
      s[i] = i.isEven ? 0.5 : -0.5;
    }
    for (final p in pauses) {
      final at = (p * 16000).round();
      s.fillRange(at, at + 4000, 0); // 0.25 s pause
    }
    return s;
  }

  test('long audio is cut inside pauses, in pieces of at most 30 s', () {
    final audio = speechWithPauses(65, [24, 50]);
    final parts = WhisperService.splitAtPauses(audio);

    expect(parts.length, 3);
    expect(parts.every((p) => p.length <= 16000 * 30), isTrue);
    // Nothing lost or duplicated: the pieces add back to the whole audio.
    expect(parts.fold<int>(0, (n, p) => n + p.length), audio.length);
    // Each cut sits in a pause: the samples around it are silent.
    final cuts = [parts[0].length, parts[0].length + parts[1].length];
    for (final cut in cuts) {
      expect(audio[cut - 1], 0);
      expect(audio[cut], 0);
    }
    expect(cuts.map((c) => c / 16000),
        [closeTo(24.1, 0.2), closeTo(50.1, 0.2)]);
  });

  test('speech without pauses still yields pieces of at most 30 s', () {
    final parts = WhisperService.splitAtPauses(speechWithPauses(95, []));
    expect(parts.every((p) => p.length <= 16000 * 30), isTrue);
    expect(parts.fold<int>(0, (n, p) => n + p.length), 16000 * 95);
  });

  test('short audio stays whole and slivers are dropped', () {
    expect(WhisperService.splitAtPauses(Float32List(16000 * 3)).single.length,
        16000 * 3);
    expect(WhisperService.splitAtPauses(Float32List(0)), isEmpty);
    // A few samples crashed the native Whisper decoder; never send them.
    expect(WhisperService.splitAtPauses(Float32List(1000)), isEmpty);
    expect(
        WhisperService.splitAtPauses(Float32List(16000 * 30 + 75))
            .every((p) => p.length >= 1600),
        isTrue);
  });

  test('extractModelFiles keeps only the named files and cleans up', () {
    final dir = Directory.systemTemp.createTempSync('whisper_extract');
    addTearDown(() => dir.deleteSync(recursive: true));
    ArchiveFile entry(String name, String text) {
      final bytes = Uint8List.fromList(text.codeUnits);
      return ArchiveFile('sherpa-onnx-whisper-turbo/$name', bytes.length, bytes);
    }

    final tar = TarEncoder().encodeBytes(Archive()
      ..addFile(entry('turbo-encoder.int8.onnx', 'enc'))
      ..addFile(entry('turbo-encoder.onnx', 'fp32'))
      ..addFile(entry('turbo-tokens.txt', 'tok')));
    final archivePath = '${dir.path}/model.tar.bz2';
    File(archivePath).writeAsBytesSync(BZip2Encoder().encodeBytes(tar));

    WhisperService.extractModelFiles(
      archivePath,
      dir.path,
      {'turbo-encoder.int8.onnx', 'turbo-tokens.txt'},
    );

    expect(File('${dir.path}/turbo-encoder.int8.onnx').readAsStringSync(), 'enc');
    expect(File('${dir.path}/turbo-tokens.txt').readAsStringSync(), 'tok');
    expect(File('${dir.path}/turbo-encoder.onnx').existsSync(), isFalse);
    expect(File('$archivePath.tar').existsSync(), isFalse);
    expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });
}
