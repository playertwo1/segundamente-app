import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/ui/chat/view_models/duplex_voice_viewmodel.dart';

import '../../../helpers/duplex_voice_fakes.dart';

void main() {
  late FakeAudioDevice device;
  late FakeChatRouter router;

  setUp(() {
    device = FakeAudioDevice();
    router = FakeChatRouter();
  });

  Future<DuplexVoiceViewModel> started({
    Future<String?> Function(Float32List samples)? transcribe,
  }) async {
    final vm = buildDuplexViewModel(
      device: device,
      router: router,
      transcribe: transcribe,
    );
    addTearDown(vm.dispose);
    await vm.loadRoutes();
    await vm.start();
    return vm;
  }

  /// Takes the conversation up to the reply being read aloud.
  Future<DuplexVoiceViewModel> speaking() async {
    final vm = await started();
    await device.say();
    await router.answer('são **dez** horas');
    expect(vm.state, DuplexVoiceState.speaking);
    return vm;
  }

  test('nada de microfone nem de permissão antes de start', () async {
    final vm = buildDuplexViewModel(device: device, router: router);
    addTearDown(vm.dispose);

    expect(vm.canStart, isFalse);
    await vm.loadRoutes();

    expect(vm.canStart, isTrue);
    expect(vm.state, DuplexVoiceState.idle);
    expect(vm.micActive, isFalse);
    expect(device.permissionRequests, 0);
    expect(device.micStarts, 0);
    expect(vm.routes!.chat.host, 'llm.example.test');
  });

  test('sem modelo válido não dá para iniciar', () async {
    final vm =
        buildDuplexViewModel(device: device, router: router, noConfig: true);
    addTearDown(vm.dispose);
    await vm.loadRoutes();

    await vm.start();

    expect(vm.canStart, isFalse);
    expect(device.permissionRequests, 0);
  });

  test('start pede a permissão e abre o microfone', () async {
    final vm = await started();

    expect(device.permissionRequests, 1);
    expect(vm.state, DuplexVoiceState.listening);
    expect(vm.micActive, isTrue);
    expect(device.micHeld, isTrue);
  });

  test('permissão negada não abre o microfone', () async {
    device.permission = false;
    final vm = await started();

    expect(vm.state, DuplexVoiceState.idle);
    expect(vm.problem, DuplexVoiceProblem.permissionDenied);
    expect(device.micStarts, 0);
    expect(vm.micActive, isFalse);
  });

  test('modelo de fala local ausente avisa antes de pedir a permissão',
      () async {
    final vm = buildDuplexViewModel(
      device: device,
      router: router,
      localSpeech: true,
      speechModelMissing: true,
    );
    addTearDown(vm.dispose);
    await vm.loadRoutes();
    await vm.start();

    expect(vm.problem, DuplexVoiceProblem.speechModelMissing);
    expect(device.permissionRequests, 0);
    expect(device.micStarts, 0);
  });

  test('um turno: ouvir, transcrever, perguntar só leitura, falar, ouvir',
      () async {
    final vm = await started();

    await device.say();
    expect(vm.state, DuplexVoiceState.thinking);
    expect(vm.heard, 'que horas são');
    expect(router.sent, ['que horas são']);
    expect(router.readOnly, [true]);

    await router.answer('são **dez** horas');
    expect(vm.state, DuplexVoiceState.speaking);
    expect(vm.reply, 'são **dez** horas');
    expect(device.spoken, ['são dez horas']); // sem marcas de Markdown
    expect(device.locales, ['pt-BR']);
    // Microphone closed while the app talks (D-049): it cannot hear itself.
    expect(vm.micActive, isFalse);
    expect(device.micHeld, isFalse);

    device.finishSpeaking();
    await pumpEventQueue();
    expect(vm.state, DuplexVoiceState.listening);
    expect(device.micHeld, isTrue);

    // The next turn stays in the same chat session.
    await device.say();
    expect(router.sessionIds, [null, 'voz-1']);
  });

  // Talking over the reply was replaced by a tap after the S25 measurement
  // (D-049): the loudspeaker echo triggered the detector.
  test('interromper cala a síntese, reabre o microfone e ouve o próximo turno',
      () async {
    final vm = await speaking();

    await vm.interrupt();
    await pumpEventQueue();

    expect(device.speechStops, 1);
    expect(device.isSpeaking, isFalse);
    expect(vm.state, DuplexVoiceState.listening);
    expect(device.micHeld, isTrue);

    await device.say();

    expect(vm.state, DuplexVoiceState.thinking);
    expect(router.sent, hasLength(2));
  });

  test('som enquanto o app fala não interrompe nem vira turno', () async {
    final vm = await speaking();
    final closedMic = device.mic;

    closedMic.add(pcm(4, loud: true));
    closedMic.add(pcm(2, loud: false));
    await pumpEventQueue();

    expect(vm.state, DuplexVoiceState.speaking);
    expect(device.isSpeaking, isTrue);
    expect(device.speechStops, 0);
    expect(router.sent, hasLength(1));
  });

  test('interromper fora da fala não faz nada', () async {
    final vm = await started();

    await vm.interrupt();

    expect(vm.state, DuplexVoiceState.listening);
    expect(device.speechStops, 0);
  });

  test('áudio que chega enquanto pensa é descartado', () async {
    var calls = 0;
    final vm = await started(transcribe: (_) async {
      calls++;
      return 'oi';
    });

    await device.say();
    expect(vm.state, DuplexVoiceState.thinking);
    await device.say();

    expect(calls, 1);
    expect(router.sent, hasLength(1));
  });

  test('fala sem texto reconhecido volta a ouvir sem perguntar ao modelo',
      () async {
    final vm = await started(transcribe: (_) async => '  ');

    await device.say();

    expect(vm.state, DuplexVoiceState.listening);
    expect(router.sent, isEmpty);
  });

  test('pausar fecha o microfone e cala a resposta; retomar reabre', () async {
    final vm = await speaking();

    await vm.pause();

    expect(vm.state, DuplexVoiceState.paused);
    expect(vm.micActive, isFalse);
    expect(device.micHeld, isFalse);
    expect(device.isSpeaking, isFalse);
    expect(device.speechShutdowns, 0);

    await vm.resume();

    expect(vm.state, DuplexVoiceState.listening);
    expect(device.micStarts, 2);
    expect(device.micHeld, isTrue);
  });

  test('pausar enquanto pensa descarta a resposta que chegar depois', () async {
    final vm = await started();
    await device.say();
    final pending = router.reply!;

    await vm.pause();
    pending.add(ChatResponseChunkEvent('t', 'tarde demais', isDone: true));
    unawaited(pending.close());
    await pumpEventQueue();

    expect(vm.state, DuplexVoiceState.paused);
    expect(device.spoken, isEmpty);
  });

  test('cancelar libera microfone e voz e ignora o que estava em curso',
      () async {
    final transcript = Completer<String?>();
    final vm = await started(transcribe: (_) => transcript.future);
    await device.say();

    await vm.cancel();

    expect(vm.state, DuplexVoiceState.idle);
    expect(vm.problem, isNull);
    expect(vm.micActive, isFalse);
    expect(device.micHeld, isFalse);
    expect(device.speechShutdowns, 1);
    expect(device.detector.freed, isTrue);

    transcript.complete('chegou depois do cancelamento');
    await pumpEventQueue();

    expect(router.sent, isEmpty);
    expect(vm.state, DuplexVoiceState.idle);
  });

  test('cancelar enquanto fala para a síntese', () async {
    final vm = await speaking();

    await vm.cancel();

    expect(device.isSpeaking, isFalse);
    expect(device.micHeld, isFalse);
    expect(vm.state, DuplexVoiceState.idle);
  });

  test('erro na transcrição deixa tudo desligado e registra o erro', () async {
    final vm = await started(transcribe: (_) async => throw StateError('rede'));

    await device.say();

    expect(vm.state, DuplexVoiceState.idle);
    expect(vm.problem, DuplexVoiceProblem.failed);
    expect(vm.error, isA<StateError>());
    expect(device.micHeld, isFalse);
    expect(device.speechShutdowns, 1);
  });

  test('erro do modelo deixa tudo desligado', () async {
    final vm = await started();
    await device.say();

    router.reply!.add(ChatErrorEvent('t', 'sem conexão'));
    await pumpEventQueue();

    expect(vm.problem, DuplexVoiceProblem.failed);
    expect(device.micHeld, isFalse);
    expect(device.spoken, isEmpty);
  });

  test('falha ao abrir o microfone não deixa nada aberto', () async {
    device.startError = StateError('microfone ocupado');
    final vm = await started();

    expect(vm.state, DuplexVoiceState.idle);
    expect(vm.problem, DuplexVoiceProblem.failed);
    expect(vm.micActive, isFalse);
    expect(device.speechShutdowns, 1);
  });

  test('perder o microfone no meio (permissão revogada) encerra com erro',
      () async {
    final vm = await started();

    await device.mic.close();
    await pumpEventQueue();

    expect(vm.state, DuplexVoiceState.idle);
    expect(vm.problem, DuplexVoiceProblem.failed);
    expect(device.micHeld, isFalse);
    expect(device.speechShutdowns, 1);
  });

  test('dispose libera os recursos de áudio', () async {
    final vm = buildDuplexViewModel(device: device, router: router);
    await vm.loadRoutes();
    await vm.start();
    await device.say();
    await router.answer('resposta');

    vm.dispose();
    await pumpEventQueue();

    expect(device.micHeld, isFalse);
    expect(device.isSpeaking, isFalse);
    expect(device.speechShutdowns, 1);
    expect(device.awake, isFalse);
  });
}
