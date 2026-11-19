import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/main.dart' show MemexApp;
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/chat/widgets/agent_chat_dialog.dart';
import 'package:memex/ui/floating_chat/widgets/floating_chat_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F15-02 chain: the real router and app shell over a fake native channel.
/// The native side is the only fake; the sheet, the dialog and the routes are
/// the production ones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.memexlab.memex/floating_chat');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  late List<String> nativeCalls;
  String? pendingMode;

  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  setUp(() {
    nativeCalls = [];
    pendingMode = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return call.method == 'takePendingMode' ? pendingMode : null;
    });
    FloatingChatService.instance.initialize();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMessageHandler(channel.name, null);
  });

  Future<void> pumpApp(WidgetTester tester, GoRouter router) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MemexApp(router: router));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  GoRouter appRouter({
    String initialLocation = AppRoutes.home,
    String? savedSessionId,
  }) {
    return createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(body: Text('home-screen')),
      initialLocation: initialLocation,
      floatingSessionLoaderForTesting: () async => savedSessionId,
    );
  }

  testWidgets('returning to the launcher from the bubble restores the app',
      (tester) async {
    final router = appRouter(
      initialLocation: AppRoutes.floatingChatFor(FloatingChatMode.bubble),
    );
    await pumpApp(tester, router);
    expect(find.byType(FloatingChatScreen), findsOneWidget);

    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('mainOpened')),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.text('home-screen'), findsOneWidget);
    expect(find.byType(FloatingChatScreen), findsNothing);
  });

  testWidgets('a warm shortcut resumes the session before returning home',
      (tester) async {
    final router = appRouter(savedSessionId: 'previous-conversation');
    await pumpApp(tester, router);
    pendingMode = 'type';
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('open')),
      (_) {},
    );
    await tester.pumpAndSettle();
    final dialog = tester.widget<AgentChatDialog>(find.byType(AgentChatDialog));
    expect(dialog.initialSessionId, 'previous-conversation');

    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('mainOpened')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('home-screen'), findsOneWidget);
    expect(find.byType(FloatingChatScreen), findsNothing);
  });

  testWidgets('a cold start on the sheet shows it first, then Close goes home',
      (tester) async {
    final router = appRouter(
      initialLocation: AppRoutes.floatingChatFor(FloatingChatMode.type),
    );
    await pumpApp(tester, router);

    expect(find.byType(FloatingChatScreen), findsOneWidget);
    expect(find.byType(AgentChatDialog), findsOneWidget);
    expect(find.text('home-screen'), findsNothing);

    await tester.tap(find.text(UserStorage.l10n.close));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(nativeCalls, ['close']);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    expect(find.byType(FloatingChatScreen), findsNothing);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('an open signal with a pending mode pushes the sheet over home',
      (tester) async {
    final router = appRouter();
    await pumpApp(tester, router);
    expect(find.text('home-screen'), findsOneWidget);
    expect(find.byType(FloatingChatScreen), findsNothing);

    pendingMode = 'type';
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('open')),
      (_) {},
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(nativeCalls, contains('takePendingMode'));
    expect(find.byType(FloatingChatScreen), findsOneWidget);
    expect(
      tester.widget<FloatingChatScreen>(find.byType(FloatingChatScreen)).mode,
      FloatingChatMode.type,
    );
  });

  testWidgets('Close on a pushed sheet pops back to home, not a new home',
      (tester) async {
    final router = appRouter();
    await pumpApp(tester, router);

    pendingMode = 'type';
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('open')),
      (_) {},
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FloatingChatScreen), findsOneWidget);

    await tester.tap(find.text(UserStorage.l10n.close));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(nativeCalls.last, 'close');
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    expect(find.byType(FloatingChatScreen), findsNothing);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('Open in app without a conversation just leaves the sheet',
      (tester) async {
    final router = appRouter(
      initialLocation: AppRoutes.floatingChatFor(FloatingChatMode.type),
    );
    await pumpApp(tester, router);

    await tester.tap(find.text(UserStorage.l10n.floatingOpenInApp));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(nativeCalls, ['openInApp']);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    expect(find.text('home-screen'), findsOneWidget);
  });
}
