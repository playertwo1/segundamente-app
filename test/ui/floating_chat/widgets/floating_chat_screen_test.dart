import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/agent_chat_dialog.dart';
import 'package:memex/ui/floating_chat/view_models/listen_once_viewmodel.dart';
import 'package:memex/ui/floating_chat/widgets/floating_chat_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/duplex_voice_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/floating_chat_screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> nativeCalls;
  late FloatingChatService service;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await initializeDateFormatting('en');
    await UserStorage.initL10n();
  });

  setUp(() {
    nativeCalls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
    service = FloatingChatService.forTesting(channel: channel);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Home at '/', the sheet at '/floating-chat' as the app mounts it.
  Future<GoRouter> pumpSheet(
    WidgetTester tester,
    FloatingChatMode mode, {
    ListenOnceViewModel? listenOnce,
    Future<String?> Function()? loadSessionId,
    Size size = const Size(390, 800),
    double textScale = 1,
  }) async {
    final router = GoRouter(
      initialLocation: '/floating-chat',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home-screen')),
        ),
        GoRoute(
          path: '/floating-chat',
          builder: (_, __) => FloatingChatScreen(
            mode: mode,
            service: service,
            listenOnceForTesting: listenOnce,
            loadSessionId: loadSessionId ?? () async => null,
          ),
        ),
      ],
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp.router(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return router;
  }

  testWidgets('type mode opens the dialog with the keyboard and no listening',
      (tester) async {
    await pumpSheet(tester, FloatingChatMode.type);

    final dialog = tester.widget<AgentChatDialog>(find.byType(AgentChatDialog));
    expect(dialog.autofocusInput, isTrue);
    expect(dialog.listenOnStart, isFalse);
    expect(dialog.initialSessionId, isNull);
    expect(dialog.floatingHost, isNotNull);
  });

  testWidgets('talk mode opens the dialog already listening', (tester) async {
    final listenOnce = ListenOnceViewModel(
      service: FakeAudioDevice().service,
      speechModelMissing: () async => true,
    );
    addTearDown(listenOnce.dispose);
    await pumpSheet(tester, FloatingChatMode.talk, listenOnce: listenOnce);

    final dialog = tester.widget<AgentChatDialog>(find.byType(AgentChatDialog));
    expect(dialog.listenOnStart, isTrue);
    expect(dialog.autofocusInput, isFalse);
    expect(dialog.listenOnceForTesting, same(listenOnce));
    expect(listenOnce.state, ListenOnceState.modelMissing);
  });

  for (final mode in [FloatingChatMode.type, FloatingChatMode.bubble]) {
    testWidgets('${mode.name} waits for and opens the saved conversation',
        (tester) async {
      final existingSession = Completer<String?>();
      await pumpSheet(tester, mode,
          loadSessionId: () => existingSession.future);
      expect(find.byType(AgentChatDialog), findsNothing);

      existingSession.complete('saved-conversation');
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<AgentChatDialog>(find.byType(AgentChatDialog))
            .initialSessionId,
        'saved-conversation',
      );
    });
  }

  testWidgets('bubble mode fills its window without opening the keyboard',
      (tester) async {
    await pumpSheet(tester, FloatingChatMode.bubble);

    final dialog = tester.widget<AgentChatDialog>(find.byType(AgentChatDialog));
    expect(dialog.autofocusInput, isFalse);
    expect(dialog.listenOnStart, isFalse);
    expect(
      tester.getSize(find.byKey(const ValueKey('agent_chat_dialog_container'))),
      const Size(390, 800),
    );
  });

  testWidgets('remove animations gives the chat a stationary entrance',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpSheet(tester, FloatingChatMode.type);

    final panel = find.byKey(const ValueKey('agent_chat_dialog_container'));
    final slide = tester.widget<SlideTransition>(
      find.ancestor(of: panel, matching: find.byType(SlideTransition)).first,
    );
    final keyboardPadding = tester.widget<AnimatedPadding>(
      find.ancestor(of: panel, matching: find.byType(AnimatedPadding)).first,
    );
    expect(slide.position.value, Offset.zero);
    expect(keyboardPadding.duration, Duration.zero);
  });

  testWidgets('the bubble keeps the header actions at twice the text size',
      (tester) async {
    await pumpSheet(
      tester,
      FloatingChatMode.bubble,
      size: const Size(320, 650),
      textScale: 2,
    );

    expect(find.byTooltip(UserStorage.l10n.floatingOpenInApp), findsOneWidget);
    expect(find.byTooltip(UserStorage.l10n.close), findsOneWidget);
  });

  testWidgets('Close closes the native sheet and returns home', (tester) async {
    final router = await pumpSheet(tester, FloatingChatMode.type);

    await tester.tap(find.text(UserStorage.l10n.close));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(nativeCalls, ['close']);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('Close pops back to the screen the sheet was pushed over',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/origin',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home-screen')),
        ),
        GoRoute(
          path: '/origin',
          builder: (_, __) => const Scaffold(body: Text('origin-screen')),
        ),
        GoRoute(
          path: '/floating-chat',
          builder: (_, __) => FloatingChatScreen(
            mode: FloatingChatMode.type,
            service: service,
            loadSessionId: () async => null,
          ),
        ),
      ],
    );
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    unawaited(router.push('/floating-chat'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FloatingChatScreen), findsOneWidget);

    await tester.tap(find.text(UserStorage.l10n.close));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(nativeCalls, ['close']);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/origin');
    expect(find.text('origin-screen'), findsOneWidget);
    expect(find.text('home-screen'), findsNothing);
  });

  testWidgets('back gesture closes the sheet the same way', (tester) async {
    final router = await pumpSheet(tester, FloatingChatMode.type);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    expect(nativeCalls, ['close']);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });
}
