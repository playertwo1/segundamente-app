import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/native_action_service.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/utils/result.dart';
import 'package:permission_handler/permission_handler.dart';

enum ReminderOutcome { created, noExactTime, permissionDenied, failed }

class TodoViewModel extends ChangeNotifier {
  TodoViewModel({
    required MemexRouter router,
    Future<bool> Function({
      required String title,
      required DateTime start,
      required DateTime end,
      String? description,
      bool allDay,
    })? openCalendar,
    Future<bool> Function({
      required String title,
      required DateTime dueDate,
      String? notes,
    })? createReminder,
    Future<bool> Function()? ensureReminderPermission,
  })  : _router = router,
        _openCalendar = openCalendar ?? NativeActionService.openCalendarInsert,
        _createReminder = createReminder ?? NativeActionService.addReminder,
        _ensureReminderPermission =
            ensureReminderPermission ?? _askReminderPermission;

  final MemexRouter _router;
  MemexRouter get router => _router;
  final Future<bool> Function({
    required String title,
    required DateTime start,
    required DateTime end,
    String? description,
    bool allDay,
  }) _openCalendar;

  final Future<bool> Function({
    required String title,
    required DateTime dueDate,
    String? notes,
  }) _createReminder;
  final Future<bool> Function() _ensureReminderPermission;

  // Android keeps reminders in the calendar; iOS has its own store.
  static Future<bool> _askReminderPermission() async {
    final permission =
        Platform.isAndroid ? Permission.calendarFullAccess : Permission.reminders;
    if ((await permission.status).isGranted) return true;
    return (await permission.request()).isGranted;
  }

  /// A reminder needs a moment. Only a date written together with a time
  /// qualifies; a bare date or a word like "sexta" is never turned into one.
  static DateTime? reminderTimeFor(String due) {
    final explicit = parseExplicitDue(due);
    return explicit != null && explicit.hasTime ? explicit.date : null;
  }

  List<TodoItem> _all = const [];
  String query = '';
  bool loading = false;
  String? errorMessage;

  /// What the screen shows: filtered by the search, open items first.
  List<TodoItem> get items => sortTodos(searchTodos(_all, query));

  bool get hasAny => _all.isNotEmpty;

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    (await _router.loadTodos()).when(
      onOk: (value) => _all = value,
      onError: (error, _) => errorMessage = '$error',
    );
    loading = false;
    notifyListeners();
  }

  void search(String value) {
    query = value;
    notifyListeners();
  }

  Future<void> add({required String text, required String due}) {
    return _change(_router.addTodo(text: text, due: due));
  }

  Future<void> edit(TodoItem item,
      {required String text, required String due}) {
    return _change(_router.editTodo(id: item.id, text: text, due: due));
  }

  Future<void> toggleDone(TodoItem item) {
    return _change(_router.setTodoDone(id: item.id, done: !item.done));
  }

  Future<void> remove(TodoItem item) {
    return _change(_router.removeTodo(item.id));
  }

  /// Opens the calendar app's new-event screen with this item. The user
  /// saves it there; nothing is written from here.
  Future<bool> addToCalendar(TodoItem item) async {
    final slot = calendarSlotFor(item.due);
    if (slot == null) return false;
    return _openCalendar(
      title: item.text,
      start: slot.start,
      end: slot.end,
      description: item.source?.excerpt,
      allDay: slot.allDay,
    );
  }

  /// Saves the reminder on the device. The screen asks the user first; the
  /// calendar permission is requested only now, when the user said yes.
  Future<ReminderOutcome> addReminder(TodoItem item) async {
    final when = reminderTimeFor(item.due);
    if (when == null) return ReminderOutcome.noExactTime;
    if (!await _ensureReminderPermission()) {
      return ReminderOutcome.permissionDenied;
    }
    final created = await _createReminder(
      title: item.text,
      dueDate: when,
      notes: item.source?.excerpt,
    );
    return created ? ReminderOutcome.created : ReminderOutcome.failed;
  }

  Future<void> _change<T>(Future<Result<T>> action) async {
    (await action).when(
      onOk: (_) => errorMessage = null,
      onError: (error, _) => errorMessage = '$error',
    );
    await load();
  }
}
