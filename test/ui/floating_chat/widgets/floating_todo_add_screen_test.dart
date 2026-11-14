import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/core/widgets/content_notice.dart';
import 'package:memex/ui/floating_chat/widgets/floating_todo_add_screen.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/floating_todo_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/floating_todo_add_screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> nativeCalls;
  late FloatingChatService service;
  late FakeTodoRouter router;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  setUp(() {
    nativeCalls = [];
    router = FakeTodoRouter();
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
    service = FloatingChatService.forTesting(channel: channel);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Home at '/', the "+ tarefa" sheet over it, as the app mounts it.
  Future<void> pumpSheet(WidgetTester tester) async {
    final goRouter = GoRouter(
      initialLocation: '/floating-todo-add',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home-screen')),
        ),
        GoRoute(
          path: '/floating-todo-add',
          builder: (_, __) => FloatingTodoAddScreen(
            viewModel: TodoViewModel(router: router),
            service: service,
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
        routerConfig: goRouter,
      ),
    );
    await settle(tester);
  }

  testWidgets(
      'opens the Todo editor over the sheet and saves through the router',
      (tester) async {
    await pumpSheet(tester);

    expect(find.byKey(const ValueKey('todo_text')), findsOneWidget);
    expect(find.byType(ContentNoticeCaption), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('todo_text')), 'Pagar o seguro');
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await settle(tester);

    expect(router.addedTexts, ['Pagar o seguro']);
    expect(router.items.single.text, 'Pagar o seguro');
    expect(nativeCalls, ['close']);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('cancelling adds nothing and closes back to home',
      (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('todo_dialog_cancel')));
    await settle(tester);

    expect(router.addedTexts, isEmpty);
    expect(nativeCalls, ['close']);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('an empty text is not saved; the editor stays open',
      (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await settle(tester);

    expect(router.addedTexts, isEmpty);
    expect(find.byKey(const ValueKey('todo_text')), findsOneWidget);
    expect(nativeCalls, isEmpty);
  });
}
