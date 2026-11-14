import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/utils/result.dart';

/// Stands in for [MemexRouter] in the Todo floating-sheet tests (F15-05). It
/// keeps an in-memory list, records the completions and additions the sheets
/// ask for, and can be told to fail a completion.
class FakeTodoRouter implements MemexRouter {
  FakeTodoRouter([List<TodoItem> items = const []]) : _stored = [...items];

  final List<TodoItem> _stored;
  final List<String> completedIds = [];
  final List<String> addedTexts = [];
  bool failCompletion = false;

  List<TodoItem> get items => [
        for (final item in _stored)
          if (!item.isTombstoned) item,
      ];

  @override
  Future<Result<List<TodoItem>>> loadTodos(
          {bool includeDeleted = false}) async =>
      Ok(includeDeleted ? _stored : items);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(TodoShortcutSettings.defaults);

  @override
  Future<Result<TodoAlarmStatus>> todoAlarmStatus() async =>
      const Ok(TodoAlarmStatus.unsupported);

  @override
  Future<Result<String?>> todoDamagedLegacyFileName() async => const Ok(null);

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
    addedTexts.add(text.trim());
    final item = TodoItem(
      id: id ?? 'added-${addedTexts.length}',
      text: text.trim(),
      due: due ?? '',
      done: false,
      createdAt: '2026-11-14T12:00:00.000Z',
      alertMinutes: alertMinutes,
      priority: priority,
      subtasks: subtasks,
      recurrence: recurrence,
    );
    _stored.add(item);
    return Ok(item);
  }

  @override
  Future<Result<void>> setTodoDone({
    required String id,
    required bool done,
  }) async {
    completedIds.add(id);
    if (failCompletion) return Error(StateError('synthetic failure'));
    final index = _stored.indexWhere((item) => item.id == id);
    if (index < 0) return Error(StateError('todo item not found: $id'));
    if (_stored[index].done != done) {
      _stored[index] = _stored[index].copyWith(
        done: done,
        doneAt: done ? '2026-11-14T12:00:00.000Z' : null,
        clearDoneAt: !done,
      );
    }
    return const Ok.v();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A dated, open task for the sheet and snapshot tests.
TodoItem todoTask(String id, String text, {String? date, String? time}) =>
    TodoItem(
      id: id,
      text: text,
      due: date == null ? '' : '$date${time == null ? '' : ' $time'}',
      dueDate: date,
      dueTime: time,
      done: false,
      createdAt: '2026-11-01T12:00:00.000Z',
    );
