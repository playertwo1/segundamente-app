import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/duplex_voice_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/duplex_voice_fakes.dart';

/// F7-03 full chain: screen → ViewModel → DuplexVoiceService → chat router,
/// fed with synthetic PCM. Only the device edges are fakes (microphone stream,
/// voice detector model, speech engine, transcriber, model reply).
void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  testWidgets('conversa por voz de ponta a ponta com interrupção por toque',
      (tester) async {
    final l10n = UserStorage.l10n;
    final device = FakeAudioDevice();
    final router = FakeChatRouter();
    var utterance = 0;
    final vm = buildDuplexViewModel(
      device: device,
      router: router,
      transcribe: (samples) async {
        expect(samples.length, 4 * 512);
        return ['que horas são', 'espera, e amanhã?'][utterance++];
      },
    );
    Finder key(String name) => find.byKey(ValueKey(name));
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    Future<void> answer(String text) async {
      router.reply!
        ..add(ChatSessionCreatedEvent('voz-1'))
        ..add(ChatResponseChunkEvent('t', text, isDone: true));
      await router.reply!.close();
      await settle();
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DuplexVoiceScreen(viewModel: vm),
      ),
    );
    await settle();
    expect(device.micStarts, 0);

    // Explicit start: the indicator turns on with the microphone.
    await tester.tap(key('duplex-start'));
    await settle();
    expect(key('duplex-mic-on'), findsOneWidget);

    // First utterance → transcript on screen → sent read-only to the chat.
    device.mic
      ..add(pcm(4, loud: true))
      ..add(pcm(2, loud: false));
    await settle();
    expect(find.text(l10n.duplexStateThinking), findsOneWidget);
    expect(find.text('que horas são'), findsOneWidget);
    expect(router.readOnly, [true]);

    // Reply is spoken with the microphone visibly off.
    await answer('São dez horas.');
    expect(find.text(l10n.duplexStateSpeaking), findsOneWidget);
    expect(find.text('São dez horas.'), findsOneWidget);
    expect(device.spoken, ['São dez horas.']);
    expect(key('duplex-mic-off'), findsOneWidget);
    expect(device.micHeld, isFalse);

    // One tap silences it and the microphone comes back on.
    await tester.tap(key('duplex-interrupt'));
    await settle();
    expect(device.isSpeaking, isFalse);
    expect(find.text(l10n.duplexStateListening), findsOneWidget);
    expect(key('duplex-mic-on'), findsOneWidget);
    expect(key('duplex-interrupt'), findsNothing);

    device.mic
      ..add(pcm(4, loud: true))
      ..add(pcm(2, loud: false));
    await settle();
    expect(find.text('espera, e amanhã?'), findsOneWidget);
    expect(router.sent, ['que horas são', 'espera, e amanhã?']);
    expect(router.sessionIds, [null, 'voz-1']);

    // Leaving the screen mid-turn releases everything.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    expect(device.micHeld, isFalse);
    expect(device.speechShutdowns, 1);
    expect(device.awake, isFalse);
  });
}
