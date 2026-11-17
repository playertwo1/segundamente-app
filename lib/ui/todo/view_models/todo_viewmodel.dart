import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/active_assistant_service.dart';
import 'package:memex/data/services/native_action_service.dart';
import 'package:memex/data/services/todo_sync_service.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/daily_briefing_builder.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';

/// Screens the Todo list can show. [upcoming] has no tab of its own: it is a
/// section of [all].
enum TodoListSection { all, today, upcoming, overdue, completed }

/// The tabs of the Todo screen, in display order.
const todoTabSections = [
  TodoListSection.all,
  TodoListSection.today,
  TodoListSection.overdue,
  TodoListSection.completed,
];

/// Sections of the [TodoListSection.all] tab, in display order.
enum TodoSectionKey { overdue, today, upcoming, undated, completed }

class TodoSectionGroup {
  const TodoSectionGroup({required this.key, required this.items});

  final TodoSectionKey key;
  final List<TodoItem> items;
}

enum TodoTaskState { noDate, today, upcoming, overdue, completed }

class TodoViewModel extends ChangeNotifier {
  static final _logger = getLogger('TodoViewModel');

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
    ActiveAssistantService? activeAssistantService,
    Future<String?> Function(ImageSource source)? pickPhoto,
  })  : _router = router,
        _now = now ?? DateTime.now,
        _openCalendar = openCalendar ?? NativeActionService.openCalendarInsert,
        _syncService = syncService ?? TodoSyncService.instance,
        _userIdResolver = userIdResolver ?? UserStorage.getUserId,
        _autoSyncOnLoad = autoSyncOnLoad,
        _activeAssistantService =
            activeAssistantService ?? ActiveAssistantService.instance,
        _pickPhoto = pickPhoto ?? _systemPickPhoto {
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
  final ActiveAssistantService _activeAssistantService;
  ActiveAssistantService get activeAssistantService => _activeAssistantService;
  final Future<String?> Function(ImageSource source) _pickPhoto;
  final Set<TodoSectionKey> _collapsedSections = {};

  List<TodoItem> _all = const [];
  TodoShortcutSettings shortcutSettings = TodoShortcutSettings.defaults;
  ActiveAssistantState activeAssistantState =
      ActiveAssistantState(settings: ActiveAssistantSettings.defaults);
  TodoListSection section = TodoListSection.all;
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
        if ((section == TodoListSection.all ||
                (section == TodoListSection.completed
                    ? item.done
                    : !item.done && _belongsToSection(item, section))) &&
            (priorityFilter == null || item.priority == priorityFilter))
          item,
    ];
    return _sortForSection(
      items,
      section == TodoListSection.all ? null : section,
    );
  }

  /// The sections of the [TodoListSection.all] tab, in order. Empty sections
  /// are left out.
  List<TodoSectionGroup> get allSections {
    final groups = [
      for (final key in TodoSectionKey.values)
        TodoSectionGroup(key: key, items: _sectionItems(key)),
    ];
    return [
      for (final group in groups)
        if (group.items.isNotEmpty) group,
    ];
  }

  bool isSectionCollapsed(TodoSectionKey key) =>
      _collapsedSections.contains(key);

  /// Open or close a section of the all tab. Kept in memory only.
  void toggleSection(TodoSectionKey key) {
    if (!_collapsedSections.remove(key)) _collapsedSections.add(key);
    notifyListeners();
  }

  List<TodoItem> _sectionItems(TodoSectionKey key) {
    final items = [
      for (final item in _all)
        if (_inSection(item, key) &&
            (priorityFilter == null || item.priority == priorityFilter))
          item,
    ];
    return _sortForSection(
      items,
      key == TodoSectionKey.completed ? TodoListSection.completed : null,
    );
  }

  bool _inSection(TodoItem item, TodoSectionKey key) {
    if (key == TodoSectionKey.completed) return item.done;
    if (item.done) return false;
    final state = stateFor(item);
    return switch (key) {
      TodoSectionKey.overdue => state == TodoTaskState.overdue,
      TodoSectionKey.today => state == TodoTaskState.today,
      TodoSectionKey.upcoming => state == TodoTaskState.upcoming,
      TodoSectionKey.undated => state == TodoTaskState.noDate,
      TodoSectionKey.completed => false,
    };
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
    } catch (e, st) {
      // Keep local tasks and last known sync status if sync fails unexpectedly.
      _logger.warning('Todo sync ($reason) failed in view model', e, st);
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
    } catch (e, st) {
      _logger.warning('Todo conflict resolution failed in view model', e, st);
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
    if (_disposed) return;
    await refreshActiveAssistantState();
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
    } catch (e, st) {
      // Keep safe localOnly fallback when platform bindings are unavailable.
      _logger.warning('Todo sync status load failed in view model', e, st);
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
    } catch (e, st) {
      // Keep local tasks and last known sync status if sync fails unexpectedly.
      _logger.warning('Todo sync ($reason) failed in view model', e, st);
    }
  }

  Future<String?> _resolveUserId() async {
    try {
      return await _userIdResolver();
    } catch (e, st) {
      _logger.warning('Todo user id resolution failed', e, st);
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

  Future<void> refreshActiveAssistantState() async {
    if (_disposed) return;
    try {
      final state = await _activeAssistantService.buildState(_all, now: _now());
      if (_disposed) return;
      activeAssistantState = state;
      notifyListeners();
    } catch (e, st) {
      _logger.warning('Failed to refresh active assistant state', e, st);
    }
  }

  int get activeAssistantItemCount =>
      (activeAssistantState.briefing != null ? 1 : 0) +
      activeAssistantState.stalledNudges.length +
      activeAssistantState.personaSuggestions.length;

  Future<void> dismissDailyBriefing(DailyBriefing briefing) async {
    if (_disposed) return;
    try {
      await _activeAssistantService.dismissBriefing(briefing);
      await refreshActiveAssistantState();
    } catch (e, st) {
      _logger.warning('Failed to dismiss daily briefing in view model', e, st);
    }
  }

  Future<void> dismissPersonaSuggestion(String suggestionId) async {
    if (_disposed) return;
    try {
      await _activeAssistantService.dismissPersonaSuggestion(suggestionId);
      await refreshActiveAssistantState();
    } catch (e, st) {
      _logger.warning(
        'Failed to dismiss persona suggestion in view model',
        e,
        st,
      );
    }
  }

  Future<void> silenceActiveAssistantFor(Duration duration) async {
    if (_disposed) return;
    try {
      await _activeAssistantService.silenceFor(duration, now: _now());
      await refreshActiveAssistantState();
    } catch (e, st) {
      _logger.warning('Failed to silence active assistant in view model', e, st);
    }
  }

  Future<void> snoozeStalledTaskNudge(
    String taskId, {
    Duration duration = const Duration(days: 3),
  }) async {
    if (_disposed) return;
    try {
      await _activeAssistantService.snoozeStalledTask(
        taskId,
        duration: duration,
        now: _now(),
      );
      await refreshActiveAssistantState();
    } catch (e, st) {
      _logger.warning(
        'Failed to snooze stalled task nudge in view model',
        e,
        st,
      );
    }
  }

  Future<void> scheduleStalledTaskForToday(TodoItem item) async {
    final today = TodoScheduleCalculator.dateForShortcut(
      TodoDateShortcut.today,
      now: _now(),
      timeZone: item.timeZone,
    );
    final dateStr = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final due = item.dueTime != null ? '$dateStr ${item.dueTime}' : dateStr;

    try {
      await _activeAssistantService.clearStalledSnooze(item.id);
    } catch (e, st) {
      _logger.warning('Failed to clear stalled snooze in view model', e, st);
    }
    await _change(_router.editTodo(
      id: item.id,
      text: item.text,
      due: due,
      dueDate: dateStr,
      dueTime: item.dueTime,
      recurrence: item.recurrence,
      priority: item.priority,
      subtasks: item.subtasks,
      alertMinutes: item.alertMinutes,
      timeZone: item.timeZone,
    ));
    await refreshActiveAssistantState();
  }

  Future<void> add({
    required String text,
    required String due,
    TodoRecurrence? recurrence,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    int? alertMinutes,
    List<String> attachments = const [],
  }) async {
    await _change(_router.addTodo(
      text: text,
      due: due,
      recurrence: recurrence,
      priority: priority,
      subtasks: subtasks,
      alertMinutes: alertMinutes ?? shortcutSettings.defaultAlertMinutes,
      attachments: attachments,
    ));
  }

  Future<void> edit(TodoItem item,
      {required String text,
      required String due,
      TodoRecurrence? recurrence,
      bool clearRecurrence = false,
      TodoPriority? priority,
      List<TodoSubtask>? subtasks,
      int? alertMinutes,
      List<String>? attachments}) async {
    await _change(_router.editTodo(
      id: item.id,
      text: text,
      due: due,
      recurrence: recurrence,
      clearRecurrence: clearRecurrence,
      priority: priority,
      subtasks: subtasks,
      alertMinutes: alertMinutes,
      attachments: attachments,
    ));
  }

  /// Lets the user pick one photo; returns its local path, or null on cancel.
  /// Nothing is copied into the workspace until the task is saved.
  Future<String?> pickPhoto(ImageSource source) => _pickPhoto(source);

  /// Copies picked photos into the workspace; returns their `fs://` references
  /// in the same order. Throws when a photo cannot be copied.
  Future<List<String>> storePhotos(List<String> sourcePaths) async {
    if (sourcePaths.isEmpty) return const [];
    return (await _router.storeTodoPhotos(sourcePaths)).valueOrThrow;
  }

  /// Local file of a saved photo, or null when it cannot be resolved.
  Future<String?> photoPath(String reference) async {
    final result = await _router.todoAttachmentPath(reference);
    return result.isOk ? result.valueOrThrow : null;
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
      TodoListSection.all => true,
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

/// Camera or gallery through the system picker, downscaled like the capture flow.
Future<String?> _systemPickPhoto(ImageSource source) async =>
    (await ImagePicker().pickImage(source: source, imageQuality: 85))?.path;
