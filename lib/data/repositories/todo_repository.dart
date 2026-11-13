import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/utils/result.dart';

class TodoRepository {
  TodoRepository({TodoService? service}) : _service = service ?? TodoService();

  final TodoService _service;

  Future<Result<List<TodoItem>>> load(String userId) =>
      runResult(() => _service.load(userId));

  Future<Result<TodoItem>> add({
    required String userId,
    required String text,
    String? due,
    String? dueDate,
    String? dueTime,
    String timeZone = todoTimeZone,
    int alertMinutes = 20,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    TodoRecurrence? recurrence,
  }) =>
      runResult(() => _service.add(
            userId: userId,
            text: text,
            due: due,
            dueDate: dueDate,
            dueTime: dueTime,
            timeZone: timeZone,
            alertMinutes: alertMinutes,
            priority: priority,
            subtasks: subtasks,
            recurrence: recurrence,
          ));

  Future<Result<TodoItem>> addFromReport({
    required String userId,
    required String sessionId,
    required ReportItem item,
  }) =>
      runResult(() => _service.addFromReport(
            userId: userId,
            sessionId: sessionId,
            item: item,
          ));

  Future<Result<void>> edit({
    required String userId,
    required String id,
    required String text,
    required String due,
    String? dueDate,
    String? dueTime,
    String? timeZone,
    int? alertMinutes,
    TodoPriority? priority,
    List<TodoSubtask>? subtasks,
    TodoRecurrence? recurrence,
    bool clearRecurrence = false,
  }) =>
      runResultVoid(() => _service.edit(
            userId: userId,
            id: id,
            text: text,
            due: due,
            dueDate: dueDate,
            dueTime: dueTime,
            timeZone: timeZone,
            alertMinutes: alertMinutes,
            priority: priority,
            subtasks: subtasks,
            recurrence: recurrence,
            clearRecurrence: clearRecurrence,
          ));

  Future<Result<void>> setDone({
    required String userId,
    required String id,
    required bool done,
  }) =>
      runResultVoid(() => _service.setDone(
            userId: userId,
            id: id,
            done: done,
          ));

  Future<Result<void>> remove({required String userId, required String id}) =>
      runResultVoid(() => _service.remove(userId: userId, id: id));
}
