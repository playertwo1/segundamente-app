import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/duplex_voice_fakes.dart';

void main() {
  late FakeAudioDevice device;
  late int starts;
  late List<int> utterances;
  late List<Object> errors;

  Future<void> open() => device.service.openMic(
        onSpeechStart: () => starts++,
        onUtterance: (samples) => utterances.add(samples.length),
        onError: errors.add,
      );

  setUp(() {
    device = FakeAudioDevice();
    starts = 0;
    utterances = [];
    errors = [];
  });

  test('o microfone só abre quando pedido e corta a fala em falas', () async {
    expect(device.service.micOpen, isFalse);
    expect(device.micStarts, 0);

    await open();
    expect(device.service.micOpen, isTrue);
    expect(device.awake, isTrue);

    await device.say();
    expect(starts, 1);
    expect(utterances, [4 * 512]);

    await device.say();
    expect(starts, 2);
    expect(utterances, hasLength(2));
  });

  test('pedaços de áudio fora do tamanho da janela são reagrupados', () async {
    await open();
    final speech = pcm(4, loud: true);
    device.mic
      ..add(Uint8List.sublistView(speech, 0, 700))
      ..add(Uint8List.sublistView(speech, 700))
      ..add(pcm(2, loud: false));
    await pumpEventQueue();

    expect(utterances, [4 * 512]);
  });

  test('com discardInput o áudio é jogado fora sem passar pelo detector',
      () async {
    await open();
    device.mic.add(pcm(2, loud: true));
    await pumpEventQueue();
    expect(starts, 1);

    device.service.discardInput = true;
    await device.say();
    expect(utterances, isEmpty);

    device.service.discardInput = false;
    await device.say();
    // Only the utterance heard after the gate reopened, without the first half.
    expect(utterances, [4 * 512]);
  });

  test('closeMic para a captura, libera o wakelock e ignora áudio tardio',
      () async {
    await open();
    final mic = device.mic;
    await device.service.closeMic();

    expect(device.service.micOpen, isFalse);
    expect(device.micHeld, isFalse);
    expect(device.awake, isFalse);

    mic.add(pcm(4, loud: true));
    await pumpEventQueue();
    expect(starts, 0);
    expect(errors, isEmpty);

    await device.service.closeMic();
    expect(device.micStops, 1);
  });

  test('fim inesperado do fluxo do microfone vira erro', () async {
    await open();
    await device.mic.close();
    await pumpEventQueue();

    expect(errors.single, isA<StateError>());
  });

  test('release fecha tudo mesmo quando um passo falha', () async {
    await open();
    device.stopSpeakingError = StateError('motor de voz');

    await expectLater(device.service.release(), throwsStateError);

    expect(device.micHeld, isFalse);
    expect(device.speechShutdowns, 1);
    expect(device.detector.freed, isTrue);
    expect(device.awake, isFalse);
  });
}
