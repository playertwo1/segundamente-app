import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/ui/todo/view_models/todo_proposal_viewmodel.dart';
import 'package:memex/utils/result.dart';

class _FakeRouter implements MemexRouter {
  List<TodoItem> items = [];
  String? savedId;
  String? savedDue;
  int? savedAlertMinutes;

  @override
  Future<Result<List<TodoItem>>> loadTodos(
          {bool includeDeleted = false}) async =>
      Ok([
        for (final item in items)
          if (includeDeleted || !item.isTombstoned) item,
      ]);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(TodoShortcutSettings.defaults);

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
  }) async {
    savedId = id;
    savedDue = due;
    savedAlertMinutes = alertMinutes;
    final item = TodoItem(
      id: id ?? 'new-id',
      text: text,
      due: due ?? '',
      dueDate: dueDate,
      dueTime: dueTime,
      timeZone: timeZone,
      alertMinutes: alertMinutes,
      priority: priority,
      subtasks: subtasks,
      recurrence: recurrence,
      done: false,
      createdAt: '2026-11-13T00:00:00',
    );
    items = [...items, item];
    return Ok(item);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingSettingsRouter extends _FakeRouter {
  final settingsResult = Completer<Result<TodoShortcutSettings>>();
  int todoLoads = 0;

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() =>
      settingsResult.future;

  @override
  Future<Result<List<TodoItem>>> loadTodos({bool includeDeleted = false}) {
    todoLoads++;
    return super.loadTodos(includeDeleted: includeDeleted);
  }
}

void main() {
  test('loads tombstones and confirms with the stable proposal id', () async {
    final router = _FakeRouter();
    final viewModel = TodoProposalViewModel(router: router);
    final proposal = TodoProposal(
      id: 'proposal-7',
      title: 'Enviar relatório',
      dateState: TodoProposalDateState.explicit,
      dueDate: '2026-11-20',
      timeState: TodoProposalTimeState.unspecified,
    );

    await viewModel.load();
    final result = await viewModel.confirm(
      proposal: proposal,
      text: proposal.title,
      due: '2026-11-20',
      priority: TodoPriority.normal,
      subtasks: const [],
      alertMinutes: 15,
    );

    expect(result.isOk, isTrue);
    expect(router.savedId, 'proposal-7');
    expect(router.savedDue, '2026-11-20');
    expect(router.savedAlertMinutes, 15);
    expect(router.items.single.timeZone, todoTimeZone);

    await viewModel.load();
    expect(viewModel.taskFor('proposal-7')?.text, 'Enviar relatório');
  });

  test('stops an in-flight load after the view model is disposed', () async {
    final router = _PendingSettingsRouter();
    final viewModel = TodoProposalViewModel(router: router);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final load = viewModel.load();
    expect(notifications, 1);
    viewModel.dispose();
    router.settingsResult.complete(Ok(TodoShortcutSettings.defaults));

    await expectLater(load, completes);
    expect(router.todoLoads, 0);
    expect(notifications, 1);
  });
}
