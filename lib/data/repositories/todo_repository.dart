import 'package:memex/data/services/active_assistant_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/data/services/todo_alarm_service.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';

class TodoRepository {
  TodoRepository({
    TodoService? service,
    ActiveAssistantService? activeAssistantService,
  })  : _service = service ?? TodoService(),
        _activeAssistantService =
            activeAssistantService ?? ActiveAssistantService.instance;

  final TodoService _service;
  final ActiveAssistantService _activeAssistantService;

  Future<Result<ActiveAssistantSettings>> loadActiveAssistantSettings() =>
      runResult(_activeAssistantService.loadSettings);

  Future<Result<void>> saveActiveAssistantSettings(
    ActiveAssistantSettings settings,
  ) =>
      runResultVoid(() => _activeAssistantService.saveSettings(settings));

  Future<Result<TodoShortcutSettings>> loadShortcutSettings() =>
      runResult(UserStorage.getTodoShortcutSettings);

  Future<Result<void>> saveShortcutSettings(
    TodoShortcutSettings settings,
  ) =>
      runResultVoid(() => UserStorage.setTodoShortcutSettings(settings));

  Future<Result<List<TodoItem>>> load(
    String userId, {
    bool includeDeleted = false,
  }) =>
      runResult(() => _service.load(userId, includeDeleted: includeDeleted));

  Future<Result<TodoAlarmStatus>> alarmStatus() =>
      runResult(TodoAlarmService.instance.status);

  Future<Result<TodoAlarmStatus>> requestAlarmPermissions() =>
      runResult(TodoAlarmService.instance.requestPermissions);

  Future<Result<TodoAlarmStatus>> synchronizeAlarms(String userId) =>
      runResult(() => _service.synchronizeAlarms(userId));

  Future<Result<void>> refreshWidgetSnapshot(String userId) =>
      runResultVoid(() => _service.refreshWidgetSnapshot(userId));

  Future<Result<String?>> damagedLegacyFileName(String userId) =>
      runResult(() => _service.damagedLegacyFileName(userId));

  Future<Result<TodoItem>> add({
    required String userId,
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
  }) =>
      runResult(() => _service.add(
            userId: userId,
            text: text,
            id: id,
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

  Future<Result<void>> snooze({
    required String userId,
    required String id,
  }) =>
      runResultVoid(() => _service.snooze(userId: userId, id: id));

  Future<Result<void>> remove({required String userId, required String id}) =>
      runResultVoid(() => _service.remove(userId: userId, id: id));

  Future<Result<void>> restore({required String userId, required String id}) =>
      runResultVoid(() => _service.restore(userId: userId, id: id));
}
