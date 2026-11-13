import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_config.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/view_models/duplex_voice_viewmodel.dart';
import 'package:memex/ui/chat/widgets/duplex_voice_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/duplex_voice_fakes.dart';

void main() {
  late FakeAudioDevice device;
  late FakeChatRouter router;

  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  setUp(() {
    device = FakeAudioDevice();
    router = FakeChatRouter();
  });

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  /// The screen owns the ViewModel and disposes it when it leaves the tree.
  Future<DuplexVoiceViewModel> pumpScreen(
    WidgetTester tester, {
    bool noConfig = false,
    bool localSpeech = false,
    bool speechModelMissing = false,
  }) async {
    final vm = buildDuplexViewModel(
      device: device,
      router: router,
      noConfig: noConfig,
      localSpeech: localSpeech,
      speechModelMissing: speechModelMissing,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DuplexVoiceScreen(viewModel: vm),
      ),
    );
    await settle(tester);
    return vm;
  }

  Future<void> tap(WidgetTester tester, String name) async {
    await tester.tap(key(name));
    await settle(tester);
  }

  testWidgets('abre com o microfone desligado e mostra para onde os dados vão',
      (tester) async {
    final l10n = UserStorage.l10n;
    await pumpScreen(tester);

    expect(find.text(l10n.duplexStateIdle), findsOneWidget);
    expect(key('duplex-mic-off'), findsOneWidget);
    expect(key('duplex-mic-on'), findsNothing);
    // Opening the screen is not consent: nothing was asked or opened.
    expect(device.permissionRequests, 0);
    expect(device.micStarts, 0);

    expect(key('duplex-data-route'), findsOneWidget);
    expect(
      find.text(l10n.dataRouteAudioSentTo('llm.example.test')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dataRouteTextSentTo('llm.example.test')),
      findsOneWidget,
    );
    expect(find.textContaining('modelo-de-teste'), findsNWidgets(2));
    expect(find.text(l10n.duplexRouteSpeechValue), findsOneWidget);
    expect(key('duplex-pause'), findsNothing);
  });

  testWidgets('transcrição local é mostrada como "no aparelho"',
      (tester) async {
    final l10n = UserStorage.l10n;
    await pumpScreen(tester, localSpeech: true);

    expect(find.text(l10n.duplexRouteTranscriptionLocal), findsOneWidget);
    expect(
      find.text(l10n.dataRouteAudioSentTo('llm.example.test')),
      findsNothing,
    );
  });

  testWidgets('sem modelo configurado o botão de iniciar fica desativado',
      (tester) async {
    await pumpScreen(tester, noConfig: true);

    expect(find.text(UserStorage.l10n.dataRouteNone), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(key('duplex-start')).onPressed,
      isNull,
    );
  });

  testWidgets('iniciar, pausar, retomar e encerrar com um toque cada',
      (tester) async {
    final l10n = UserStorage.l10n;
    final handle = tester.ensureSemantics();
    await pumpScreen(tester);

    await tap(tester, 'duplex-start');
    expect(find.text(l10n.duplexStateListening), findsOneWidget);
    expect(key('duplex-mic-on'), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.duplexStateListening), findsOneWidget);
    expect(device.micHeld, isTrue);
    expect(key('duplex-pause'), findsOneWidget);
    expect(key('duplex-cancel'), findsOneWidget);

    await tap(tester, 'duplex-pause');
    expect(find.text(l10n.duplexStatePaused), findsOneWidget);
    expect(key('duplex-mic-off'), findsOneWidget);
    expect(device.micHeld, isFalse);

    await tap(tester, 'duplex-resume');
    expect(find.text(l10n.duplexStateListening), findsOneWidget);
    expect(device.micHeld, isTrue);

    await tap(tester, 'duplex-cancel');
    expect(find.text(l10n.duplexStateIdle), findsOneWidget);
    expect(key('duplex-mic-off'), findsOneWidget);
    expect(device.micHeld, isFalse);
    expect(key('duplex-start'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('permissão negada mostra o aviso e o microfone desligado',
      (tester) async {
    device.permission = false;
    await pumpScreen(tester);

    await tap(tester, 'duplex-start');

    expect(find.text(UserStorage.l10n.voiceMicDenied), findsOneWidget);
    expect(key('duplex-mic-off'), findsOneWidget);
    expect(device.micStarts, 0);
  });

  testWidgets('modelo de fala local ausente mostra como resolver',
      (tester) async {
    await pumpScreen(tester, localSpeech: true, speechModelMissing: true);

    await tap(tester, 'duplex-start');

    expect(find.text(UserStorage.l10n.speechModelMissingHint), findsOneWidget);
    expect(device.permissionRequests, 0);
  });

  testWidgets('erro mostra a mensagem e deixa o microfone desligado',
      (tester) async {
    device.startError = StateError('microfone ocupado');
    await pumpScreen(tester);

    await tap(tester, 'duplex-start');

    expect(find.text(UserStorage.l10n.duplexErrorFailed), findsOneWidget);
    expect(key('duplex-mic-off'), findsOneWidget);
    expect(key('duplex-start'), findsOneWidget);
  });

  testWidgets('app em segundo plano encerra a conversa e libera o microfone',
      (tester) async {
    await pumpScreen(tester);
    await tap(tester, 'duplex-start');
    expect(device.micHeld, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);

    expect(device.micHeld, isFalse);
    expect(device.speechShutdowns, 1);

    // Frames are not drawn while paused; back in the app it shows as ended
    // and does not reopen the microphone by itself.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.text(UserStorage.l10n.duplexStateIdle), findsOneWidget);
    expect(device.micStarts, 1);
  });

  testWidgets('o diálogo de permissão (inactive) não encerra a conversa',
      (tester) async {
    await pumpScreen(tester);
    await tap(tester, 'duplex-start');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);

    expect(device.micHeld, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('fechar a tela libera o microfone e a voz', (tester) async {
    await pumpScreen(tester);
    await tap(tester, 'duplex-start');
    expect(device.micHeld, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);

    expect(device.micHeld, isFalse);
    expect(device.speechShutdowns, 1);
    expect(device.awake, isFalse);
  });

  // Was off until the S25 measurement; on since the owner chose tap-to-interrupt (D-049).
  test('a entrada no chat está ligada', () {
    expect(AppConfig.enableDuplexVoice, isTrue);
  });
}
