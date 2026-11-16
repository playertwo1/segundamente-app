import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/active_assistant_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_sync_service.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/utils/result.dart';

class _FakeRouter implements MemexRouter {
  @override
  Future<Result<String?>> todoDamagedLegacyFileName() async => const Ok(null);

  _FakeRouter(this.items);

  List<TodoItem> items;

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
  Future<Result<void>> editTodo({
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
  }) async {
    final index = items.indexWhere((i) => i.id == id);
    if (index >= 0) {
      items[index] = items[index].copyWith(
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
      );
    }
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTodoSyncService extends TodoSyncService {
  _FakeTodoSyncService({
    TodoSyncStatus? initialStatus,
    this.onSyncNow,
    this.onResolveConflict,
  }) : currentStatus = initialStatus ??
            TodoSyncStatus(
              state: TodoSyncBadgeState.localOnly,
              paired: false,
              deviceId: '',
              pendingOutbox: 0,
            );

  TodoSyncStatus currentStatus;
  final Future<TodoSyncStatus> Function(String? userId, String reason)?
      onSyncNow;
  final Future<TodoSyncStatus> Function({
    required String userId,
    required String conflictId,
    required bool keepLocal,
  })? onResolveConflict;

  int loadStatusCalls = 0;
  final List<String> syncReasons = [];
  final List<({String userId, String conflictId, bool keepLocal})>
      resolvedConflicts = [];

  @override
  Future<TodoSyncStatus> loadStatus({
    String? userId,
    FileSystemService? files,
  }) async {
    loadStatusCalls++;
    statusNotifier.value = currentStatus;
    return currentStatus;
  }

  @override
  Future<TodoSyncStatus> syncNow({
    String? userId,
    String reason = 'manual',
    FileSystemService? files,
  }) async {
    syncReasons.add(reason);
    if (onSyncNow != null) {
      currentStatus = await onSyncNow!(userId, reason);
    }
    statusNotifier.value = currentStatus;
    return currentStatus;
  }

  @override
  Future<TodoSyncStatus> resolveConflict({
    required String userId,
    required String conflictId,
    required bool keepLocal,
    FileSystemService? files,
  }) async {
    resolvedConflicts.add((
      userId: userId,
      conflictId: conflictId,
      keepLocal: keepLocal,
    ));
    if (onResolveConflict != null) {
      currentStatus = await onResolveConflict!(
        userId: userId,
        conflictId: conflictId,
        keepLocal: keepLocal,
      );
    }
    statusNotifier.value = currentStatus;
    return currentStatus;
  }
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
    viewModel.dispose();
  });

  test('starts in localOnly and does not call syncNow when unpaired', () async {
    final router = _FakeRouter([_item('t1', 'Local')]);
    final fakeSync = _FakeTodoSyncService();
    final viewModel = TodoViewModel(
      router: router,
      syncService: fakeSync,
      userIdResolver: () async => null,
    );
    addTearDown(viewModel.dispose);

    expect(viewModel.syncStatus.state, TodoSyncBadgeState.localOnly);
    expect(viewModel.syncStatus.paired, isFalse);
    expect(viewModel.syncStatus.deviceId, '');
    expect(viewModel.syncStatus.pendingOutbox, 0);
    expect(viewModel.isItemSynced(router.items.single), isFalse);

    await viewModel.load();
    expect(fakeSync.loadStatusCalls, 1);
    expect(fakeSync.syncReasons, isEmpty);
    expect(viewModel.syncStatus.state, TodoSyncBadgeState.localOnly);

    await viewModel.syncNow();
    expect(fakeSync.loadStatusCalls, 2);
    expect(fakeSync.syncReasons, isEmpty);
  });

  test('syncNow runs when paired, reloads router tasks, and updates isItemSynced',
      () async {
    final localTask = _item('t1', 'Local');
    final remoteTask = _item('t2', 'Do PC');
    final router = _FakeRouter([localTask]);
    final fakeSync = _FakeTodoSyncService(
      initialStatus: TodoSyncStatus(
        state: TodoSyncBadgeState.savedOnDevice,
        paired: true,
        deviceId: 'phone-1',
        pendingOutbox: 1,
        unsyncedItemIds: const {'t1'},
      ),
      onSyncNow: (userId, reason) async {
        expect(userId, 'user-1');
        router.items = [localTask, remoteTask];
        return TodoSyncStatus(
          state: TodoSyncBadgeState.synced,
          paired: true,
          deviceId: 'phone-1',
          pendingOutbox: 0,
          pendingPc: 0,
          lastSyncedAt: '2026-11-15T12:00:00.000Z',
          hasCompletedSync: true,
        );
      },
    );
    final viewModel = TodoViewModel(
      router: router,
      syncService: fakeSync,
      userIdResolver: () async => 'user-1',
      autoSyncOnLoad: false,
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();
    expect(fakeSync.syncReasons, isEmpty);
    expect(viewModel.isItemSynced(localTask), isFalse);

    await viewModel.syncNow();
    expect(fakeSync.syncReasons, ['manual']);
    expect(viewModel.syncStatus.state, TodoSyncBadgeState.synced);
    expect(viewModel.allItems.map((e) => e.id), ['t1', 't2']);
    expect(viewModel.isItemSynced(localTask), isTrue);
    expect(viewModel.isItemSynced(remoteTask), isTrue);
  });

  test('autoSyncOnLoad triggers non-blocking sync when paired and not revoked',
      () async {
    final router = _FakeRouter([_item('t1', 'Local')]);
    final syncStarted = Completer<void>();
    final syncFinish = Completer<void>();
    final fakeSync = _FakeTodoSyncService(
      initialStatus: TodoSyncStatus(
        state: TodoSyncBadgeState.savedOnDevice,
        paired: true,
        deviceId: 'phone-1',
        pendingOutbox: 0,
      ),
      onSyncNow: (_, __) async {
        syncStarted.complete();
        await syncFinish.future;
        return TodoSyncStatus(
          state: TodoSyncBadgeState.synced,
          paired: true,
          deviceId: 'phone-1',
          pendingOutbox: 0,
          pendingPc: 0,
          hasCompletedSync: true,
          lastSyncedAt: '2026-11-15T12:05:00.000Z',
        );
      },
    );
    final viewModel = TodoViewModel(
      router: router,
      syncService: fakeSync,
      userIdResolver: () async => 'user-1',
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();
    expect(viewModel.loading, isFalse);
    expect(viewModel.allItems, hasLength(1));

    await syncStarted.future;
    syncFinish.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fakeSync.syncReasons, ['screen_open']);
    expect(viewModel.syncStatus.state, TodoSyncBadgeState.synced);
  });

  test('statusNotifier transitions reload items without looping and stop on dispose',
      () async {
    final router = _FakeRouter([_item('t1', 'Inicial')]);
    final fakeSync = _FakeTodoSyncService(
      initialStatus: TodoSyncStatus(
        state: TodoSyncBadgeState.savedOnDevice,
        paired: true,
        deviceId: 'phone-1',
        pendingOutbox: 0,
      ),
    );
    final viewModel = TodoViewModel(
      router: router,
      syncService: fakeSync,
      userIdResolver: () async => 'user-1',
      autoSyncOnLoad: false,
    );

    await viewModel.load();

    // Emitting syncing -> synced updates items from router.
    fakeSync.statusNotifier.value = TodoSyncStatus(
      state: TodoSyncBadgeState.syncing,
      paired: true,
      deviceId: 'phone-1',
      pendingOutbox: 0,
    );
    router.items = [_item('t1', 'Inicial'), _item('t2', 'Chegou remoto')];
    fakeSync.statusNotifier.value = TodoSyncStatus(
      state: TodoSyncBadgeState.synced,
      paired: true,
      deviceId: 'phone-1',
      pendingOutbox: 0,
      pendingPc: 0,
      hasCompletedSync: true,
      lastSyncedAt: '2026-11-15T12:10:00.000Z',
    );
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.allItems.map((e) => e.id), ['t1', 't2']);

    // Emitting a conflict change updates conflicts and reloads items.
    const conflict = TaskTextConflict(
      id: 't1:text',
      entityId: 't1',
      field: 'text',
      localText: 'Texto local',
      remoteText: 'Texto PC',
      winnerSide: 'remote',
      winnerText: 'Texto PC',
      loserText: 'Texto local',
      localUpdatedAt: '2026-11-15T12:00:00Z',
      remoteUpdatedAt: '2026-11-15T12:01:00Z',
    );
    router.items = [_item('t1', 'Texto local'), _item('t2', 'Chegou remoto')];
    fakeSync.statusNotifier.value = TodoSyncStatus(
      state: TodoSyncBadgeState.synced,
      paired: true,
      deviceId: 'phone-1',
      pendingOutbox: 0,
      pendingPc: 0,
      hasCompletedSync: true,
      lastSyncedAt: '2026-11-15T12:10:00.000Z',
      conflicts: const [conflict],
    );
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.conflicts, hasLength(1));

    // Disposing removes listener cleanly.
    viewModel.dispose();
    router.items = [];
    fakeSync.statusNotifier.value = TodoSyncStatus(
      state: TodoSyncBadgeState.synced,
      paired: true,
      deviceId: 'phone-1',
      pendingOutbox: 0,
      lastSyncedAt: '2026-11-15T12:15:00.000Z',
    );
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.allItems, hasLength(2));
  });

  test('refreshOnResume and resolveConflict handle keepLocal and useRemote',
      () async {
    const conflict = TaskTextConflict(
      id: 't1:text',
      entityId: 't1',
      field: 'text',
      localText: 'Texto celular',
      remoteText: 'Texto PC',
      winnerSide: 'remote',
      winnerText: 'Texto PC',
      loserText: 'Texto celular',
      localUpdatedAt: '2026-11-15T12:00:00Z',
      remoteUpdatedAt: '2026-11-15T12:01:00Z',
    );
    final router = _FakeRouter([_item('t1', 'Texto celular')]);
    final fakeSync = _FakeTodoSyncService(
      initialStatus: TodoSyncStatus(
        state: TodoSyncBadgeState.savedOnDevice,
        paired: true,
        deviceId: 'phone-1',
        pendingOutbox: 0,
        conflicts: const [conflict],
      ),
      onResolveConflict: ({
        required userId,
        required conflictId,
        required keepLocal,
      }) async {
        router.items = [
          _item('t1', keepLocal ? 'Texto celular' : 'Texto PC'),
        ];
        return TodoSyncStatus(
          state: TodoSyncBadgeState.synced,
          paired: true,
          deviceId: 'phone-1',
          pendingOutbox: 0,
          pendingPc: 0,
          hasCompletedSync: true,
          lastSyncedAt: '2026-11-15T12:20:00.000Z',
        );
      },
    );
    final viewModel = TodoViewModel(
      router: router,
      syncService: fakeSync,
      userIdResolver: () async => 'user-1',
      autoSyncOnLoad: false,
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();
    await viewModel.refreshOnResume();
    expect(fakeSync.syncReasons, ['resume']);

    await viewModel.resolveConflict('t1:text', keepLocal: true);
    expect(fakeSync.resolvedConflicts.last, (
      userId: 'user-1',
      conflictId: 't1:text',
      keepLocal: true,
    ));
    expect(viewModel.conflicts, isEmpty);
    expect(viewModel.allItems.single.text, 'Texto celular');

    await viewModel.resolveConflict('t1:text', keepLocal: false);
    expect(fakeSync.resolvedConflicts.last, (
      userId: 'user-1',
      conflictId: 't1:text',
      keepLocal: false,
    ));
    expect(viewModel.allItems.single.text, 'Texto PC');

    // Missing userId fails safely without calling syncService.resolveConflict.
    final vmNoUser = TodoViewModel(
      router: router,
      syncService: fakeSync,
      userIdResolver: () async => null,
      autoSyncOnLoad: false,
    );
    addTearDown(vmNoUser.dispose);
    await vmNoUser.resolveConflict('t1:text', keepLocal: true);
    expect(fakeSync.resolvedConflicts, hasLength(2));
  });

  group('TodoViewModel - Active Assistant integration', () {
    // 2026-11-16 12:30 UTC = 2026-11-16 09:30 local
    final fixedClock = DateTime.utc(2026, 11, 16, 12, 30);

    test('loads and refreshes active assistant state on load', () async {
      final items = [
        const TodoItem(
          id: 'stalled_1',
          text: 'Stalled task',
          due: '2026-11-12',
          dueDate: '2026-11-12',
          done: false,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];
      final router = _FakeRouter(items);
      final assistantService = ActiveAssistantService.forTesting(
        clock: () => fixedClock,
        loadSettings: () async => ActiveAssistantSettings.defaults,
        loadStalledSnoozeMap: () async => const {},
        loadDismissedBriefingKey: () async => null,
      );

      final viewModel = TodoViewModel(
        router: router,
        now: () => fixedClock,
        activeAssistantService: assistantService,
        autoSyncOnLoad: false,
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();

      expect(viewModel.activeAssistantState.briefing, isNotNull);
      expect(viewModel.activeAssistantState.stalledNudges.length, 1);
      expect(viewModel.activeAssistantState.stalledNudges.first.item.id,
          'stalled_1');
    });

    test('dismissDailyBriefing updates active assistant state', () async {
      final items = [
        const TodoItem(
          id: 't1',
          text: 'Task today',
          due: '2026-11-16',
          dueDate: '2026-11-16',
          done: false,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];
      final router = _FakeRouter(items);
      String? dismissedKey;
      final assistantService = ActiveAssistantService.forTesting(
        clock: () => fixedClock,
        loadSettings: () async => ActiveAssistantSettings.defaults,
        loadStalledSnoozeMap: () async => const {},
        loadDismissedBriefingKey: () async => dismissedKey,
        saveDismissedBriefingKey: (k) async => dismissedKey = k,
      );

      final viewModel = TodoViewModel(
        router: router,
        now: () => fixedClock,
        activeAssistantService: assistantService,
        autoSyncOnLoad: false,
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();
      expect(viewModel.activeAssistantState.briefing, isNotNull);

      await viewModel
          .dismissDailyBriefing(viewModel.activeAssistantState.briefing!);
      expect(dismissedKey, '2026-11-16:morning');
      expect(viewModel.activeAssistantState.briefing, isNull);
    });

    test('silenceActiveAssistantFor silences briefings and nudges', () async {
      final items = [
        const TodoItem(
          id: 'stalled_1',
          text: 'Stalled task',
          due: '2026-11-12',
          dueDate: '2026-11-12',
          done: false,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];
      final router = _FakeRouter(items);
      var settings = ActiveAssistantSettings.defaults;
      final assistantService = ActiveAssistantService.forTesting(
        clock: () => fixedClock,
        loadSettings: () async => settings,
        saveSettings: (s) async => settings = s,
        loadStalledSnoozeMap: () async => const {},
        loadDismissedBriefingKey: () async => null,
      );

      final viewModel = TodoViewModel(
        router: router,
        now: () => fixedClock,
        activeAssistantService: assistantService,
        autoSyncOnLoad: false,
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();
      expect(viewModel.activeAssistantState.stalledNudges, isNotEmpty);

      await viewModel.silenceActiveAssistantFor(const Duration(hours: 3));
      expect(settings.silencedUntilIso, isNotNull);
      expect(viewModel.activeAssistantState.stalledNudges, isEmpty);
      expect(viewModel.activeAssistantState.briefing, isNull);
    });

    test(
        'snoozeStalledTaskNudge snoozes nudge without altering underlying TodoItem',
        () async {
      const item = TodoItem(
        id: 'stalled_1',
        text: 'Stalled task',
        due: '2026-11-12',
        dueDate: '2026-11-12',
        done: false,
        createdAt: '2026-11-01T10:00:00.000Z',
      );
      final router = _FakeRouter([item]);
      Map<String, String> snoozeMap = {};
      final assistantService = ActiveAssistantService.forTesting(
        clock: () => fixedClock,
        loadSettings: () async => ActiveAssistantSettings.defaults,
        loadStalledSnoozeMap: () async => snoozeMap,
        saveStalledSnoozeMap: (m) async => snoozeMap = m,
        loadDismissedBriefingKey: () async => null,
      );

      final viewModel = TodoViewModel(
        router: router,
        now: () => fixedClock,
        activeAssistantService: assistantService,
        autoSyncOnLoad: false,
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();
      expect(viewModel.activeAssistantState.stalledNudges.length, 1);

      await viewModel.snoozeStalledTaskNudge('stalled_1',
          duration: const Duration(days: 3));

      // Nudge is now hidden
      expect(viewModel.activeAssistantState.stalledNudges, isEmpty);
      // Underlying TodoItem is untouched!
      expect(viewModel.allItems.length, 1);
      expect(viewModel.allItems.first.id, 'stalled_1');
      expect(viewModel.allItems.first.dueDate, '2026-11-12');
      expect(viewModel.allItems.first.done, isFalse);
      expect(snoozeMap.containsKey('stalled_1'), isTrue);
    });

    test(
        'scheduleStalledTaskForToday updates due date to today local and clears snooze',
        () async {
      const item = TodoItem(
        id: 'stalled_1',
        text: 'Stalled task',
        due: '2026-11-12 14:00',
        dueDate: '2026-11-12',
        dueTime: '14:00',
        done: false,
        createdAt: '2026-11-01T10:00:00.000Z',
      );
      final router = _FakeRouter([item]);
      Map<String, String> snoozeMap = {
        'stalled_1': '2026-11-20T10:00:00.000Z'
      };
      final assistantService = ActiveAssistantService.forTesting(
        clock: () => fixedClock,
        loadSettings: () async => ActiveAssistantSettings.defaults,
        loadStalledSnoozeMap: () async => snoozeMap,
        saveStalledSnoozeMap: (m) async => snoozeMap = m,
        loadDismissedBriefingKey: () async => null,
      );

      final viewModel = TodoViewModel(
        router: router,
        now: () => fixedClock,
        activeAssistantService: assistantService,
        autoSyncOnLoad: false,
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();

      await viewModel.scheduleStalledTaskForToday(item);

      // Verify router updated the item with today's local date (2026-11-16) and preserved dueTime
      expect(router.items.first.dueDate, '2026-11-16');
      expect(router.items.first.dueTime, '14:00');
      expect(router.items.first.due, '2026-11-16 14:00');

      // Verify snooze was cleared
      expect(snoozeMap.containsKey('stalled_1'), isFalse);
    });
  });
}
