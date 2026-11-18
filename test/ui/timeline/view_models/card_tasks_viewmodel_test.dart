import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/card_task_state.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/card_task_extractor.dart';
import 'package:memex/ui/timeline/view_models/card_tasks_viewmodel.dart';
import 'package:memex/utils/result.dart';

class _FakeRouter implements MemexRouter {
  _FakeRouter({List<TodoItem>? todos, this.state}) : todos = todos ?? [];

  List<TodoItem> todos;
  CardTaskState? state;
  bool stateReadFails = false;
  bool saveFails = false;
  int? failAddAt;
  String? failRemoveId;

  final List<({String text, String due})> addCalls = [];
  final List<String> removeCalls = [];
  final List<CardTaskState?> saves = [];
  int _nextId = 1;

  @override
  Future<Result<CardTaskState?>> loadCardTaskState(String cardId) async {
    if (stateReadFails) return Error(StateError('read failed'));
    return Ok(state);
  }

  @override
  Future<Result<void>> saveCardTaskState(
    String cardId,
    CardTaskState? state,
  ) async {
    saves.add(state);
    if (saveFails) return Error(StateError('disk full'));
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
    if (failAddAt == addCalls.length) return Error(StateError('add failed'));
    final item = _todo('new-${_nextId++}');
    todos = [...todos, item];
    return Ok(item);
  }

  @override
  Future<Result<void>> removeTodo(String id) async {
    removeCalls.add(id);
    if (id == failRemoveId) return Error(StateError('remove failed'));
    todos = [
      for (final item in todos)
        if (item.id != id) item,
    ];
    return const Ok.v();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TodoItem _todo(String id, {bool deleted = false}) => TodoItem(
      id: id,
      text: 'Tarefa $id',
      due: '',
      done: false,
      createdAt: '2026-11-17T00:00:00',
      deletedAt: deleted ? '2026-11-17T01:00:00' : null,
    );

CardTasksViewModel _viewModel(
  _FakeRouter router, {
  List<String> candidates = const ['Trocar o Parakeet', 'Melhorar o Todo'],
}) =>
    CardTasksViewModel(
      router: router,
      cardId: 'card-1',
      candidates: candidates.map(CardTaskCandidate.new).toList(),
    );

void main() {
  test('is hidden without candidates and does not read storage', () async {
    final router = _FakeRouter();
    final vm = _viewModel(router, candidates: const []);

    await vm.load();

    expect(vm.phase, CardTasksPhase.hidden);
    expect(router.saves, isEmpty);
  });

  test('starts in the selecting phase with every candidate checked', () async {
    final vm = _viewModel(_FakeRouter());

    await vm.load();

    expect(vm.phase, CardTasksPhase.selecting);
    expect(vm.candidates.map((task) => task.text),
        ['Trocar o Parakeet', 'Melhorar o Todo']);
    expect(vm.isSelected(0), isTrue);
    expect(vm.isSelected(1), isTrue);
    expect(vm.selectedCount, 2);
  });

  test('is hidden when the record was dismissed', () async {
    final router = _FakeRouter(
      state: const CardTaskState(status: CardTaskStatus.dismissed),
    );
    final vm = _viewModel(router);

    await vm.load();

    expect(vm.phase, CardTasksPhase.hidden);
  });

  test('is hidden when the saved state cannot be read', () async {
    final router = _FakeRouter()..stateReadFails = true;
    final vm = _viewModel(router);

    await vm.load();

    expect(vm.phase, CardTasksPhase.hidden);
  });

  test('shows the added phase and counts only live Todo tasks', () async {
    final router = _FakeRouter(
      todos: [_todo('t1'), _todo('t2', deleted: true)],
      state: const CardTaskState(
        status: CardTaskStatus.added,
        todoIds: ['t1', 't2', 'gone'],
      ),
    );
    final vm = _viewModel(router);

    await vm.load();

    expect(vm.phase, CardTasksPhase.added);
    expect(vm.addedCount, 1);
  });

  test('is hidden when every saved Todo task is gone', () async {
    final router = _FakeRouter(
      state: const CardTaskState(status: CardTaskStatus.added, todoIds: ['x']),
    );
    final vm = _viewModel(router);

    await vm.load();

    expect(vm.phase, CardTasksPhase.hidden);
  });

  test('toggle flips one candidate and the count follows', () async {
    final vm = _viewModel(_FakeRouter());
    await vm.load();

    vm.toggle(0);

    expect(vm.isSelected(0), isFalse);
    expect(vm.selectedCount, 1);
    vm.toggle(0);
    expect(vm.selectedCount, 2);
  });

  test('addSelected does nothing and returns false with none selected',
      () async {
    final router = _FakeRouter();
    final vm = _viewModel(router);
    await vm.load();
    vm.toggle(0);
    vm.toggle(1);

    final ok = await vm.addSelected();

    expect(ok, isFalse);
    expect(router.addCalls, isEmpty);
    expect(router.saves, isEmpty);
    expect(vm.phase, CardTasksPhase.selecting);
  });

  test('addSelected creates only selected tasks, without a date', () async {
    final router = _FakeRouter();
    final vm = _viewModel(router);
    await vm.load();
    vm.toggle(0);

    final ok = await vm.addSelected();

    expect(ok, isTrue);
    expect(router.addCalls, [(text: 'Melhorar o Todo', due: '')]);
    expect(router.saves.last?.status, CardTaskStatus.added);
    expect(router.saves.last?.todoIds, ['new-1']);
    expect(vm.phase, CardTasksPhase.added);
    expect(vm.addedCount, 1);
    expect(vm.errorMessage, isNull);
    expect(vm.busy, isFalse);
  });

  test('addSelected keeps created tasks when a later one fails', () async {
    final router = _FakeRouter()..failAddAt = 2;
    final vm = _viewModel(router, candidates: const ['A', 'B', 'C']);
    await vm.load();

    final ok = await vm.addSelected();

    expect(ok, isFalse);
    expect(router.addCalls.length, 2);
    expect(router.state?.todoIds, ['new-1']);
    expect(vm.phase, CardTasksPhase.added);
    expect(vm.addedCount, 1);
    expect(vm.errorMessage, contains('add failed'));
  });

  test('addSelected reports a save failure and keeps the phase', () async {
    final router = _FakeRouter()..saveFails = true;
    final vm = _viewModel(router);
    await vm.load();

    final ok = await vm.addSelected();

    expect(ok, isFalse);
    expect(router.addCalls.length, 2);
    expect(vm.errorMessage, contains('disk full'));
    expect(vm.phase, CardTasksPhase.added);
  });

  test('undo removes the saved tasks and returns to the full list', () async {
    final router = _FakeRouter();
    final vm = _viewModel(router);
    await vm.load();
    await vm.addSelected();

    final ok = await vm.undo();

    expect(ok, isTrue);
    expect(router.removeCalls, ['new-1', 'new-2']);
    expect(router.state, isNull);
    expect(vm.phase, CardTasksPhase.selecting);
    expect(vm.selectedCount, 2);
    expect(vm.addedCount, 0);
  });

  test('undo skips tasks the user already deleted', () async {
    final router = _FakeRouter(
      todos: [_todo('t1'), _todo('t2', deleted: true)],
      state: const CardTaskState(
        status: CardTaskStatus.added,
        todoIds: ['t1', 't2'],
      ),
    );
    final vm = _viewModel(router);
    await vm.load();

    await vm.undo();

    expect(router.removeCalls, ['t1']);
    expect(vm.phase, CardTasksPhase.selecting);
  });

  test('a failed removal keeps the rest saved for a retry', () async {
    final router = _FakeRouter(
      todos: [_todo('t1'), _todo('t2'), _todo('t3')],
      state: const CardTaskState(
        status: CardTaskStatus.added,
        todoIds: ['t1', 't2', 't3'],
      ),
    )..failRemoveId = 't2';
    final vm = _viewModel(router);
    await vm.load();

    final ok = await vm.undo();

    expect(ok, isFalse);
    expect(router.removeCalls, ['t1', 't2']);
    expect(router.state?.todoIds, ['t2', 't3']);
    expect(vm.phase, CardTasksPhase.added);
    expect(vm.addedCount, 2);
    expect(vm.errorMessage, contains('remove failed'));
  });

  test('dismiss saves the decision and hides the block', () async {
    final router = _FakeRouter();
    final vm = _viewModel(router);
    await vm.load();

    final ok = await vm.dismiss();

    expect(ok, isTrue);
    expect(router.state?.status, CardTaskStatus.dismissed);
    expect(vm.phase, CardTasksPhase.hidden);
  });

  test('finishes pending work after dispose without notifying', () async {
    final router = _FakeRouter();
    final vm = _viewModel(router);
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.load();
    expect(notifications, greaterThan(0));

    final pending = vm.addSelected();
    final before = notifications;
    vm.dispose();

    expect(await pending, isTrue);
    expect(router.state?.todoIds, ['new-1', 'new-2']);
    expect(notifications, before);
  });
}
