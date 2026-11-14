import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/utils/result.dart';

class _FakeRouter implements MemexRouter {
  _FakeRouter(this.items);

  final List<TodoItem> items;

  @override
  Future<Result<List<TodoItem>>> loadTodos(
          {bool includeDeleted = false}) async =>
      Ok(items);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(TodoShortcutSettings.defaults);

  @override
  Future<Result<TodoAlarmStatus>> todoAlarmStatus() async =>
      const Ok(TodoAlarmStatus.unsupported);

  @override
  Future<Result<TodoAlarmStatus>> synchronizeTodoAlarms() async =>
      const Ok(TodoAlarmStatus.unsupported);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TodoItem _item(
  String id,
  String text, {
  String? date,
  String? time,
  bool done = false,
  TodoPriority priority = TodoPriority.normal,
}) =>
    TodoItem(
      id: id,
      text: text,
      due: date ?? '',
      dueDate: date,
      dueTime: time,
      done: done,
      doneAt: done ? '2026-11-13T15:00:00Z' : null,
      createdAt: '2026-11-01T00:00:00Z',
      priority: priority,
    );

void main() {
  test('groups by Sao Paulo day and searches completed tasks globally',
      () async {
    final router = _FakeRouter([
      _item('today', 'Revisar', date: '2026-11-13'),
      _item('late-time', 'Ligar', date: '2026-11-13', time: '11:00'),
      _item('late-date', 'Pagar', date: '2026-11-12'),
      _item(
        'upcoming',
        'Enviar relatório',
        date: '2026-11-14',
        priority: TodoPriority.urgent,
      ),
      _item('undated', 'Anotar'),
      _item('completed', 'Relatório concluído', done: true),
    ]);
    final viewModel = TodoViewModel(
      router: router,
      now: () => DateTime.utc(2026, 11, 13, 15),
    );
    await viewModel.load();

    expect(viewModel.itemsFor(TodoListSection.today).map((item) => item.id), [
      'today',
      'undated',
    ]);
    expect(viewModel.undatedTodayItems.single.id, 'undated');
    expect(viewModel.itemsFor(TodoListSection.upcoming).single.id, 'upcoming');
    expect(
      viewModel.itemsFor(TodoListSection.overdue).map((item) => item.id),
      ['late-date', 'late-time'],
    );
    expect(
      viewModel.itemsFor(TodoListSection.completed).single.id,
      'completed',
    );
    expect(
      viewModel.searchResults('relatorio').map((item) => item.id),
      ['upcoming', 'completed'],
    );

    viewModel.setPriorityFilter(TodoPriority.urgent);
    expect(viewModel.itemsFor(TodoListSection.upcoming).single.id, 'upcoming');
    expect(viewModel.searchResults('relatorio').map((item) => item.id), [
      'upcoming',
    ]);
  });
}
