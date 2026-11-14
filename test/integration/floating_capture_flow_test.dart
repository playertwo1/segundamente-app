import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/main.dart' show MemexApp;
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/floating_chat/widgets/floating_capture_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/floating_capture_fakes.dart';

/// F15-04 chain: the real router and app shell, with the native channels and
/// the super agent faked. The capture sheet, its view model and the routes are
/// the production ones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.memexlab.memex/floating_chat');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  late List<String> nativeCalls;
  late FakeCaptureRouter router;
  String? pendingMode;
  String? clipboard;

  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  setUp(() {
    nativeCalls = [];
    router = FakeCaptureRouter();
    pendingMode = null;
    clipboard = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return call.method == 'takePendingMode' ? pendingMode : null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return clipboard == null ? null : <String, dynamic>{'text': clipboard};
      }
      return null;
    });
    FloatingChatService.instance.initialize();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMessageHandler(channel.name, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpApp(WidgetTester tester, GoRouter appRouter) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Provider<MemexRouter>.value(
        value: router,
        child: MemexApp(router: appRouter),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  GoRouter appRouter({String initialLocation = AppRoutes.home}) {
    return createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(body: Text('home-screen')),
      initialLocation: initialLocation,
    );
  }

  Future<void> openSheetFromNative(WidgetTester tester, String mode) async {
    pendingMode = mode;
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('open')),
      (_) {},
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a cold Anotar launch saves only on Guardar, then goes home',
      (tester) async {
    final goRouter = appRouter(
      initialLocation: AppRoutes.floatingLocationFor(FloatingChatMode.note),
    );
    await pumpApp(tester, goRouter);

    expect(find.byType(FloatingCaptureScreen), findsOneWidget);
    expect(find.text('home-screen'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ideia do ônibus');
    await tester.pump();
    expect(router.sent, isEmpty);

    await tester.tap(find.text(UserStorage.l10n.floatingCaptureSave));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(router.sent.map((c) => c.text), ['ideia do ônibus']);
    expect(nativeCalls, ['close']);
    expect(
        goRouter.routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('Colar over home reads the clipboard and Fechar saves nothing',
      (tester) async {
    final goRouter = appRouter();
    await pumpApp(tester, goRouter);
    expect(find.text('home-screen'), findsOneWidget);

    clipboard = 'trecho copiado';
    await openSheetFromNative(tester, 'paste');

    expect(find.byType(FloatingCaptureScreen), findsOneWidget);
    expect(find.text('trecho copiado'), findsOneWidget);

    await tester.tap(find.text(UserStorage.l10n.close));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(router.sent, isEmpty);
    expect(nativeCalls.last, 'close');
    expect(
        goRouter.routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    expect(find.text('home-screen'), findsOneWidget);
  });
}
