import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/floating_chat/view_models/listen_once_viewmodel.dart';

import '../../../helpers/duplex_voice_fakes.dart';

void main() {
  late FakeAudioDevice device;
  late List<String> delivered;

  setUp(() {
    device = FakeAudioDevice();
    delivered = [];
  });

  ListenOnceViewModel build({
    Future<String?> Function(Float32List samples)? transcribe,
    bool speechModelMissing = false,
  }) {
    final vm = ListenOnceViewModel(
      service: device.service,
      transcribe: transcribe ?? (_) async => 'comprar leite',
      speechModelMissing: () async => speechModelMissing,
      onText: delivered.add,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  test('one utterance closes the mic, is transcribed and delivered', () async {
    Float32List? transcribed;
    final vm = build(transcribe: (samples) async {
      transcribed = samples;
      return 'comprar leite';
    });

    await vm.start();
    expect(vm.state, ListenOnceState.listening);
    expect(device.permissionRequests, 1);
    expect(device.micHeld, isTrue);

    await device.say();

    expect(transcribed, isNotNull);
    expect(delivered, ['comprar leite']);
    expect(vm.state, ListenOnceState.idle);
    expect(vm.nothingHeard, isFalse);
    expect(device.micHeld, isFalse, reason: 'closed at the end of speech');
  });

  test('denied permission stops before the microphone opens', () async {
    device.permission = false;
    final vm = build();

    await vm.start();

    expect(vm.state, ListenOnceState.permissionDenied);
    expect(device.micStarts, 0);
    expect(delivered, isEmpty);
  });

  test('missing speech model stops before asking for the microphone', () async {
    final vm = build(speechModelMissing: true);

    await vm.start();

    expect(vm.state, ListenOnceState.modelMissing);
    expect(device.permissionRequests, 0);
    expect(device.micStarts, 0);
  });

  test('an utterance that transcribes to nothing is not sent', () async {
    final vm = build(transcribe: (_) async => '   ');

    await vm.start();
    await device.say();

    expect(delivered, isEmpty);
    expect(vm.state, ListenOnceState.idle);
    expect(vm.nothingHeard, isTrue);
    expect(device.micHeld, isFalse);
  });

  test('a microphone that fails to open ends in error with no mic held',
      () async {
    device.startError = StateError('mic busy');
    final vm = build();

    await vm.start();

    expect(vm.state, ListenOnceState.error);
    expect(device.micHeld, isFalse);
    expect(delivered, isEmpty);
  });

  test('a failed transcription ends in error and keeps the mic closed',
      () async {
    final vm = build(transcribe: (_) async => throw StateError('model'));

    await vm.start();
    await device.say();

    expect(vm.state, ListenOnceState.error);
    expect(device.micHeld, isFalse);
    expect(delivered, isEmpty);
  });

  test('cancel closes the microphone and later audio delivers nothing',
      () async {
    final vm = build();

    await vm.start();
    expect(device.micHeld, isTrue);

    await vm.cancel();
    expect(device.micHeld, isFalse, reason: 'closed when the user types');
    expect(vm.state, ListenOnceState.idle);

    await device.say();
    expect(delivered, isEmpty);
    expect(device.micStarts, 1);
  });

  test('dispose closes the microphone and releases it', () async {
    final vm = ListenOnceViewModel(
      service: device.service,
      transcribe: (_) async => 'x',
      speechModelMissing: () async => false,
      onText: delivered.add,
    );
    await vm.start();
    expect(device.micHeld, isTrue);

    vm.dispose();
    await pumpEventQueue();

    expect(device.micHeld, isFalse);
    expect(device.micStops, 1);
    expect(device.speechShutdowns, 1);
    expect(delivered, isEmpty);
  });
}
