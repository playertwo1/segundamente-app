import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/native_action_service.dart';
import 'package:memex/data/services/todo_sync_service.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';

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
    DateTime Function()? now,
    TodoSyncService? syncService,
    Future<String?> Function()? userIdResolver,
    bool autoSyncOnLoad = true,
  })  : _router = router,
        _now = now ?? DateTime.now,
        _openCalendar = openCalendar ?? NativeActionService.openCalendarInsert,
        _syncService = syncService ?? TodoSyncService.instance,
        _userIdResolver = userIdResolver ?? UserStorage.getUserId,
        _autoSyncOnLoad = autoSyncOnLoad {
    _syncService.statusNotifier.addListener(_onSyncStatusChanged);
  }

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
  final TodoSyncService _syncService;
  final Future<String?> Function() _userIdResolver;
  final bool _autoSyncOnLoad;

  List<TodoItem> _all = const [];
  TodoShortcutSettings shortcutSettings = TodoShortcutSettings.defaults;
  TodoListSection section = TodoListSection.today;
  TodoPriority? priorityFilter;
  bool loading = false;
  String? errorMessage;
  TodoAlarmStatus alarmStatus = TodoAlarmStatus.unsupported;
  String? damagedLegacyFileName;
  TodoSyncStatus syncStatus = TodoSyncStatus(
    state: TodoSyncBadgeState.localOnly,
    paired: false,
    deviceId: '',
    pendingOutbox: 0,
  );
  bool _disposed = false;
  int _reloadSeq = 0;

  List<TaskTextConflict> get conflicts => syncStatus.conflicts;

  bool isItemSynced(TodoItem item) => syncStatus.isItemSynced(item.id);

  @override
  void dispose() {
    _disposed = true;
    _syncService.statusNotifier.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

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
    if (_disposed) return;
    loading = true;
    errorMessage = null;
    notifyListeners();
    await _reloadLocalData();
    if (_disposed) return;
    loading = false;
    notifyListeners();
    await _loadSyncStatus(triggerAutoSync: _autoSyncOnLoad);
  }

  Future<void> syncNow({String reason = 'manual'}) async {
    if (_disposed) return;
    try {
      final userId = await _resolveUserId();
      final status = await _syncService.loadStatus(userId: userId);
      if (_disposed) return;
      _applySyncStatus(status);
      if (!status.paired || (reason != 'manual' && status.revoked)) {
        return;
      }
      await _runSyncNow(userId: userId, reason: reason);
    } catch (_) {
      // Keep local tasks and last known sync status if sync fails unexpectedly.
    }
  }

  Future<void> refreshOnResume() async {
    if (_disposed) return;
    await _reloadLocalData();
    if (_disposed) return;
    await syncNow(reason: 'resume');
  }

  Future<void> resolveConflict(
    String conflictId, {
    required bool keepLocal,
  }) async {
    if (_disposed) return;
    try {
      final userId = await _resolveUserId();
      if (userId == null || userId.isEmpty) {
        return;
      }
      final status = await _syncService.resolveConflict(
        userId: userId,
        conflictId: conflictId,
        keepLocal: keepLocal,
      );
      if (_disposed) return;
      _applySyncStatus(status);
      await _reloadItems();
    } catch (_) {
      await _reloadItems();
    }
  }

  Future<void> _reloadLocalData() async {
    (await _router.loadTodos()).when(
      onOk: (value) => _all = value,
      onError: (error, _) => errorMessage = '$error',
    );
    if (_disposed) return;
    (await _router.todoDamagedLegacyFileName()).when(
      onOk: (value) => damagedLegacyFileName = value,
      onError: (_, __) => damagedLegacyFileName = null,
    );
    if (_disposed) return;
    await refreshAlarmStatus();
    if (_disposed) return;
    await refreshShortcutSettings();
  }

  Future<void> _reloadItems() async {
    if (_disposed) return;
    final reqId = ++_reloadSeq;
    (await _router.loadTodos()).when(
      onOk: (value) {
        if (!_disposed && reqId == _reloadSeq) {
          _all = value;
        }
      },
      onError: (error, _) {
        if (!_disposed && reqId == _reloadSeq) {
          errorMessage = '$error';
        }
      },
    );
    if (_disposed || reqId != _reloadSeq) return;
    notifyListeners();
  }

  Future<void> _loadSyncStatus({required bool triggerAutoSync}) async {
    if (_disposed) return;
    try {
      final userId = await _resolveUserId();
      final status = await _syncService.loadStatus(userId: userId);
      if (_disposed) return;
      _applySyncStatus(status);
      if (triggerAutoSync && status.paired && !status.revoked) {
        unawaited(_runSyncNow(userId: userId, reason: 'screen_open'));
      }
    } catch (_) {
      // Keep safe localOnly fallback when platform bindings are unavailable.
    }
  }

  Future<void> _runSyncNow({
    required String? userId,
    required String reason,
  }) async {
    if (_disposed) return;
    try {
      final status = await _syncService.syncNow(
        userId: userId,
        reason: reason,
      );
      if (_disposed) return;
      _applySyncStatus(status);
      await _reloadItems();
    } catch (_) {
      // Keep local tasks and last known sync status if sync fails unexpectedly.
    }
  }

  Future<String?> _resolveUserId() async {
    try {
      return await _userIdResolver();
    } catch (_) {
      return null;
    }
  }

  void _applySyncStatus(TodoSyncStatus status) {
    if (_disposed || identical(syncStatus, status)) return;
    syncStatus = status;
    notifyListeners();
  }

  void _onSyncStatusChanged() {
    if (_disposed) return;
    final next = _syncService.statusNotifier.value;
    if (next == null) return;
    final previous = syncStatus;
    syncStatus = next;
    notifyListeners();
    if (_shouldReloadItemsAfterTransition(previous, next)) {
      unawaited(_reloadItems());
    }
  }

  bool _shouldReloadItemsAfterTransition(
    TodoSyncStatus previous,
    TodoSyncStatus next,
  ) {
    if (previous.state == TodoSyncBadgeState.syncing &&
        next.state != TodoSyncBadgeState.syncing) {
      return true;
    }
    if (previous.state != TodoSyncBadgeState.synced &&
        next.state == TodoSyncBadgeState.synced) {
      return true;
    }
    if (previous.lastSyncedAt != next.lastSyncedAt) {
      return true;
    }
    if (!_sameConflicts(previous.conflicts, next.conflicts)) {
      return true;
    }
    return false;
  }

  bool _sameConflicts(List<TaskTextConflict> a, List<TaskTextConflict> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ca = a[i];
      final cb = b[i];
      if (ca.id != cb.id ||
          ca.entityId != cb.entityId ||
          ca.field != cb.field ||
          ca.localText != cb.localText ||
          ca.remoteText != cb.remoteText ||
          ca.conflictState != cb.conflictState) {
        return false;
      }
    }
    return true;
  }

  Future<void> refreshAlarmStatus() async {
    (await _router.todoAlarmStatus()).when(
      onOk: (value) => alarmStatus = value,
      onError: (_, __) => alarmStatus = TodoAlarmStatus.unavailable,
    );
    if (_disposed) return;
    if (alarmStatus == TodoAlarmStatus.ready) {
      (await _router.synchronizeTodoAlarms()).when(
        onOk: (value) => alarmStatus = value,
        onError: (_, __) => alarmStatus = TodoAlarmStatus.unavailable,
      );
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> configureAlarmPermissions() async {
    (await _router.requestTodoAlarmPermissions()).when(
      onOk: (value) => alarmStatus = value,
      onError: (_, __) => alarmStatus = TodoAlarmStatus.unavailable,
    );
    if (_disposed) return;
    if (alarmStatus == TodoAlarmStatus.ready) {
      (await _router.synchronizeTodoAlarms()).when(
        onOk: (value) => alarmStatus = value,
        onError: (_, __) => alarmStatus = TodoAlarmStatus.unavailable,
      );
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> refreshShortcutSettings() async {
    (await _router.loadTodoShortcutSettings()).when(
      onOk: (value) => shortcutSettings = value,
      onError: (error, _) => errorMessage ??= '$error',
    );
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> add({
    required String text,
    required String due,
    TodoRecurrence? recurrence,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    int? alertMinutes,
  }) async {
    await _change(_router.addTodo(
      text: text,
      due: due,
      recurrence: recurrence,
      priority: priority,
      subtasks: subtasks,
      alertMinutes: alertMinutes ?? shortcutSettings.defaultAlertMinutes,
    ));
  }

  Future<void> edit(TodoItem item,
      {required String text,
      required String due,
      TodoRecurrence? recurrence,
      bool clearRecurrence = false,
      TodoPriority? priority,
      List<TodoSubtask>? subtasks,
      int? alertMinutes}) async {
    await _change(_router.editTodo(
      id: item.id,
      text: text,
      due: due,
      recurrence: recurrence,
      clearRecurrence: clearRecurrence,
      priority: priority,
      subtasks: subtasks,
      alertMinutes: alertMinutes,
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

  Future<bool> _change<T>(Future<Result<T>> action) async {
    var succeeded = false;
    Object? actionError;
    (await action).when(
      onOk: (_) => succeeded = true,
      onError: (error, _) => actionError = error,
    );
    await load();
    if (_disposed) return succeeded;
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
