import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/native_action_service.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/utils/result.dart';
import 'package:permission_handler/permission_handler.dart';

enum ReminderOutcome { created, noExactTime, permissionDenied, failed }

enum TodoListSection { today, upcoming, overdue, completed }

enum TodoTaskState { noDate, today, upcoming, overdue, completed }

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
    DateTime Function()? now,
  })  : _router = router,
        _now = now ?? DateTime.now,
        _openCalendar = openCalendar ?? NativeActionService.openCalendarInsert,
        _createReminder = createReminder ?? NativeActionService.addReminder,
        _ensureReminderPermission =
            ensureReminderPermission ?? _askReminderPermission;

  final MemexRouter _router;
  MemexRouter get router => _router;
  final DateTime Function() _now;
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
    final permission = Platform.isAndroid
        ? Permission.calendarFullAccess
        : Permission.reminders;
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
  TodoShortcutSettings shortcutSettings = TodoShortcutSettings.defaults;
  TodoListSection section = TodoListSection.today;
  TodoPriority? priorityFilter;
  bool loading = false;
  String? errorMessage;

  List<TodoItem> get allItems => List.unmodifiable(_all);

  List<TodoItem> get items => itemsFor(section);

  List<TodoItem> itemsFor(TodoListSection section) {
    final items = [
      for (final item in _all)
        if ((section == TodoListSection.completed
                ? item.done
                : !item.done && _belongsToSection(item, section)) &&
            (priorityFilter == null || item.priority == priorityFilter))
          item,
    ];
    return _sortForSection(items, section);
  }

  List<TodoItem> searchResults(String query) => _sortForSection([
        for (final item in searchTodos(_all, query))
          if (priorityFilter == null || item.priority == priorityFilter) item,
      ], null);

  List<TodoItem> get undatedTodayItems => [
        for (final item in itemsFor(TodoListSection.today))
          if (stateFor(item) == TodoTaskState.noDate) item,
      ];

  TodoTaskState stateFor(TodoItem item) {
    if (item.done) return TodoTaskState.completed;
    return switch (TodoScheduleCalculator.statusFor(
      dueDate: item.dueDate,
      dueTime: item.dueTime,
      now: _now(),
      timeZone: item.timeZone,
    )) {
      TodoDateStatus.noDate => TodoTaskState.noDate,
      TodoDateStatus.today => TodoTaskState.today,
      TodoDateStatus.upcoming => TodoTaskState.upcoming,
      TodoDateStatus.overdue => TodoTaskState.overdue,
    };
  }

  TodoItem? nextOccurrenceFor(TodoItem item) {
    final seriesId = item.seriesId;
    if (seriesId == null) return null;
    for (final candidate in _all) {
      if (candidate.seriesId == seriesId &&
          !candidate.done &&
          !candidate.isTombstoned) {
        return candidate;
      }
    }
    return null;
  }

  bool get hasAny => _all.isNotEmpty;

  void selectSection(TodoListSection value) {
    section = value;
    notifyListeners();
  }

  void setPriorityFilter(TodoPriority? value) {
    priorityFilter = value;
    notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    (await _router.loadTodos()).when(
      onOk: (value) => _all = value,
      onError: (error, _) => errorMessage = '$error',
    );
    await refreshShortcutSettings();
    loading = false;
    notifyListeners();
  }

  Future<void> refreshShortcutSettings() async {
    (await _router.loadTodoShortcutSettings()).when(
      onOk: (value) => shortcutSettings = value,
      onError: (error, _) => errorMessage ??= '$error',
    );
    notifyListeners();
  }

  Future<void> add({
    required String text,
    required String due,
    TodoRecurrence? recurrence,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
  }) async {
    await _change(_router.addTodo(
      text: text,
      due: due,
      recurrence: recurrence,
      priority: priority,
      subtasks: subtasks,
      alertMinutes: shortcutSettings.defaultAlertMinutes,
    ));
  }

  Future<void> edit(TodoItem item,
      {required String text,
      required String due,
      TodoRecurrence? recurrence,
      bool clearRecurrence = false,
      TodoPriority? priority,
      List<TodoSubtask>? subtasks}) async {
    await _change(_router.editTodo(
      id: item.id,
      text: text,
      due: due,
      recurrence: recurrence,
      clearRecurrence: clearRecurrence,
      priority: priority,
      subtasks: subtasks,
    ));
  }

  Future<void> toggleDone(TodoItem item) async {
    await _change(_router.setTodoDone(id: item.id, done: !item.done));
  }

  Future<void> toggleSubtask(TodoItem item, TodoSubtask subtask) async {
    await _change(_router.editTodo(
      id: item.id,
      text: item.text,
      due: item.due,
      subtasks: [
        for (final current in item.subtasks)
          if (current.id == subtask.id)
            current.copyWith(done: !current.done)
          else
            current,
      ],
    ));
  }

  Future<bool> remove(TodoItem item) {
    return _change(_router.removeTodo(item.id));
  }

  Future<bool> restore(TodoItem item) {
    return _change(_router.restoreTodo(item.id));
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

  Future<bool> _change<T>(Future<Result<T>> action) async {
    var succeeded = false;
    Object? actionError;
    (await action).when(
      onOk: (_) => succeeded = true,
      onError: (error, _) => actionError = error,
    );
    await load();
    if (actionError != null) {
      errorMessage = '$actionError';
      notifyListeners();
    }
    return succeeded;
  }

  bool _belongsToSection(TodoItem item, TodoListSection section) {
    final state = stateFor(item);
    return switch (section) {
      TodoListSection.today =>
        state == TodoTaskState.today || state == TodoTaskState.noDate,
      TodoListSection.upcoming => state == TodoTaskState.upcoming,
      TodoListSection.overdue => state == TodoTaskState.overdue,
      TodoListSection.completed => false,
    };
  }

  List<TodoItem> _sortForSection(
    List<TodoItem> items,
    TodoListSection? section,
  ) {
    final sorted = [...items];
    sorted.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (section == TodoListSection.completed) {
        final aDate = DateTime.tryParse(a.doneAt ?? '');
        final bDate = DateTime.tryParse(b.doneAt ?? '');
        if (aDate != null && bDate != null) return bDate.compareTo(aDate);
      }
      final dateOrder =
          (a.dueDate ?? '9999-99-99').compareTo(b.dueDate ?? '9999-99-99');
      if (dateOrder != 0) return dateOrder;
      final timeOrder = (a.dueTime ?? '99:99').compareTo(b.dueTime ?? '99:99');
      if (timeOrder != 0) return timeOrder;
      return a.createdAt.compareTo(b.createdAt);
    });
    return sorted;
  }
}
