import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/card_task_state.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/timeline/view_models/card_tasks_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/card_tasks_section.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRouter implements MemexRouter {
  CardTaskState? state;
  List<TodoItem> todos = [];
  final List<({String text, String due})> addCalls = [];
  final List<String> removeCalls = [];
  bool addFails = false;
  int _nextId = 1;

  @override
  Future<Result<CardTaskState?>> loadCardTaskState(String cardId) async =>
      Ok(state);

  @override
  Future<Result<void>> saveCardTaskState(
    String cardId,
    CardTaskState? state,
  ) async {
    this.state = state;
    return const Ok.v();
  }

  @override
  Future<Result<List<TodoItem>>> loadTodos({
    bool includeDeleted = false,
  }) async =>
      Ok(todos);

  @override
  Future<Result<TodoItem>> addTodo({
    required String text,
    String? id,
    String? due,
    String? dueDate,
    String? dueTime,
    String timeZone = todoTimeZone,
    int alertMinutes = 20,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    TodoRecurrence? recurrence,
    List<String> attachments = const [],
  }) async {
    addCalls.add((text: text, due: due ?? ''));
    if (addFails) return Error(StateError('add failed'));
    final item = TodoItem(
      id: 'new-${_nextId++}',
      text: text,
      due: '',
      done: false,
      createdAt: '2026-11-17T00:00:00',
    );
    todos = [...todos, item];
    return Ok(item);
  }

  @override
  Future<Result<void>> removeTodo(String id) async {
    removeCalls.add(id);
    todos = [
      for (final item in todos)
        if (item.id != id) item,
    ];
    return const Ok.v();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _parakeet = 'Trocar o Parakeet';
const _todo = 'Melhorar o Todo';

/// Builds the block the way the detail screen will, after load().
Future<({_FakeRouter router, CardTasksViewModel vm})> _setUp(
  WidgetTester tester, {
  CardTaskState? state,
  bool reduceMotion = false,
  bool addFails = false,
  VoidCallback? onOpenTodo,
}) async {
  final router = _FakeRouter()
    ..state = state
    ..addFails = addFails;
  final vm = CardTasksViewModel(
    router: router,
    cardId: 'card-1',
    candidates: const [_parakeet, _todo],
  );
  await vm.load();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CardTasksSection(
            viewModel: vm,
            onOpenTodo: onOpenTodo ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, vm: vm);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();
  });

  testWidgets('lists the candidates checked with the add button',
      (tester) async {
    await _setUp(tester);

    expect(find.text('Tarefas deste registro'), findsOneWidget);
    expect(find.text('sem data'), findsOneWidget);
    expect(find.text(_parakeet), findsOneWidget);
    expect(find.text(_todo), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    expect(find.text('Adicionar 2 ao Todo'), findsOneWidget);
    expect(find.text('Agora não'), findsOneWidget);
  });

  testWidgets('toggling a task updates the count in the button',
      (tester) async {
    await _setUp(tester);

    await tester.tap(find.text(_todo));
    await tester.pumpAndSettle();

    expect(find.text('Adicionar 1 ao Todo'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('with nothing selected the button asks for a choice',
      (tester) async {
    final (:router, :vm) = await _setUp(tester);
    await tester.tap(find.text(_parakeet));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_todo));
    await tester.pumpAndSettle();

    expect(find.text('Marque uma tarefa'), findsOneWidget);
    await tester.tap(find.text('Marque uma tarefa'));
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pumpAndSettle();

    expect(router.addCalls, isEmpty);
    expect(vm.phase, CardTasksPhase.selecting);
    expect(find.text('Marque uma tarefa'), findsOneWidget);
  });

  testWidgets('adds only the selected tasks without a date, then shows them',
      (tester) async {
    var opened = false;
    final (:router, :vm) = await _setUp(
      tester,
      onOpenTodo: () => opened = true,
    );
    await tester.tap(find.text(_parakeet));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar 1 ao Todo'));
    await tester.pumpAndSettle();

    expect(router.addCalls, [(text: _todo, due: '')]);
    expect(router.state?.status, CardTaskStatus.added);
    expect(router.state?.todoIds, ['new-1']);
    expect(find.text('1 tarefa no Todo'), findsOneWidget);
    expect(find.text('Adicionar 1 ao Todo'), findsNothing);
    expect(find.text('1 tarefa adicionada'), findsOneWidget);

    await tester.tap(find.text('Abrir'));
    expect(opened, isTrue);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('Desfazer removes the added tasks and returns to the list',
      (tester) async {
    final (:router, :vm) = await _setUp(tester);
    await tester.tap(find.text('Adicionar 2 ao Todo'));
    await tester.pumpAndSettle();
    expect(find.text('2 tarefas no Todo'), findsOneWidget);

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();

    expect(router.removeCalls, ['new-1', 'new-2']);
    expect(router.state, isNull);
    expect(vm.phase, CardTasksPhase.selecting);
    expect(find.text('Adicionar 2 ao Todo'), findsOneWidget);
    expect(find.text(_parakeet), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('Agora não hides the block and remembers the choice',
      (tester) async {
    final (:router, :vm) = await _setUp(tester);

    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    expect(find.text('Tarefas deste registro'), findsNothing);
    expect(router.state?.status, CardTaskStatus.dismissed);
    expect(vm.phase, CardTasksPhase.hidden);
  });

  testWidgets('stays hidden when the record was dismissed earlier',
      (tester) async {
    await _setUp(
      tester,
      state: const CardTaskState(status: CardTaskStatus.dismissed),
    );

    expect(find.text('Tarefas deste registro'), findsNothing);
    expect(find.text('Adicionar 2 ao Todo'), findsNothing);
  });

  testWidgets('shows the added row when the tasks already exist',
      (tester) async {
    final router = _FakeRouter()
      ..todos = [
        const TodoItem(
          id: 't1',
          text: _parakeet,
          due: '',
          done: false,
          createdAt: '2026-11-17T00:00:00',
        ),
      ];
    router.state = const CardTaskState(
      status: CardTaskStatus.added,
      todoIds: ['t1'],
    );
    final vm = CardTasksViewModel(
      router: router,
      cardId: 'card-1',
      candidates: const [_parakeet, _todo],
    );
    await vm.load();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pt'),
        home: Scaffold(
          body: CardTasksSection(viewModel: vm, onOpenTodo: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 tarefa no Todo'), findsOneWidget);
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text(_parakeet), findsNothing);
  });

  testWidgets('a failed add shows the error and keeps the list',
      (tester) async {
    final (:router, :vm) = await _setUp(tester, addFails: true);

    await tester.tap(find.text('Adicionar 2 ao Todo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('add failed'), findsOneWidget);
    expect(find.text('Adicionar 2 ao Todo'), findsOneWidget);
    expect(vm.phase, CardTasksPhase.selecting);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('with reduced motion the add still works, without timers',
      (tester) async {
    final (:router, :vm) = await _setUp(tester, reduceMotion: true);

    await tester.tap(find.text('Adicionar 2 ao Todo'));
    await tester.pumpAndSettle();

    expect(router.addCalls.length, 2);
    expect(find.text('2 tarefas no Todo'), findsOneWidget);
    expect(vm.phase, CardTasksPhase.added);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
