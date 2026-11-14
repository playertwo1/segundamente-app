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
import 'package:memex/ui/floating_chat/widgets/floating_todo_add_screen.dart';
import 'package:memex/ui/floating_chat/widgets/floating_todo_complete_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/floating_todo_fakes.dart';

/// F15-05 chain: the real router and app shell, with the native channels faked
/// and the router a fake. The Todo sheets and their routes are the production ones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.memexlab.memex/floating_chat');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  late List<String> nativeCalls;
  late FakeTodoRouter router;
  String? pendingMode;

  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  setUp(() {
    nativeCalls = [];
    router = FakeTodoRouter([
      todoTask('task-1', 'Enviar proposta', date: '2026-11-14', time: '15:00'),
    ]);
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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
    await settle(tester);
  }

  GoRouter appRouter({String initialLocation = AppRoutes.home}) {
    return createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(body: Text('home-screen')),
      initialLocation: initialLocation,
    );
  }

  Future<void> openFromNative(WidgetTester tester, String mode) async {
    pendingMode = mode;
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('open')),
      (_) {},
    );
    await settle(tester);
  }

  testWidgets('a cold circle tap completes the task once and goes home',
      (tester) async {
    final goRouter = appRouter(
      initialLocation: AppRoutes.floatingLocationForLaunch(
        const FloatingLaunch(FloatingChatMode.todoComplete, todoId: 'task-1'),
      ),
    );
    await pumpApp(tester, goRouter);

    expect(router.completedIds, ['task-1']);
    expect(router.items.single.done, isTrue);
    expect(nativeCalls, contains('close'));
    expect(find.text('home-screen'), findsOneWidget);
    expect(find.byType(FloatingTodoCompleteScreen), findsNothing);
  });

  testWidgets('a circle tap on a task that is gone closes without crashing',
      (tester) async {
    final goRouter = appRouter(
      initialLocation: AppRoutes.floatingTodoCompleteFor('nao-existe'),
    );
    await pumpApp(tester, goRouter);

    expect(router.completedIds, ['nao-existe']);
    expect(nativeCalls, contains('close'));
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('a circle tap while the app is open completes the task',
      (tester) async {
    await pumpApp(tester, appRouter());
    expect(find.text('home-screen'), findsOneWidget);

    await openFromNative(tester, 'todo_complete:task-1');

    expect(router.completedIds, ['task-1']);
    expect(nativeCalls, contains('close'));
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('"+ tarefa" over home opens the editor and saves one task',
      (tester) async {
    await pumpApp(tester, appRouter());

    await openFromNative(tester, 'todo_add');
    expect(find.byType(FloatingTodoAddScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_text')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('todo_text')), 'Comprar pão');
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await settle(tester);

    expect(router.addedTexts, ['Comprar pão']);
    expect(nativeCalls, contains('close'));
    expect(find.text('home-screen'), findsOneWidget);
  });
}
