import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_sync_service.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/ui/todo/widgets/todo_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the list in memory; the real file storage has its own tests.
class _FakeRouter implements MemexRouter {
  _FakeRouter(List<TodoItem> items, {TodoShortcutSettings? shortcutSettings})
      : shortcutSettings = shortcutSettings ?? TodoShortcutSettings.defaults,
        _stored = [...items];

  final List<TodoItem> _stored;
  List<TodoItem> get items => [
        for (final item in _stored)
          if (!item.isTombstoned) item,
      ];
  TodoShortcutSettings shortcutSettings;
  TodoAlarmStatus alarmStatus = TodoAlarmStatus.ready;
  TodoAlarmStatus? requestedAlarmStatus;
  String? damagedLegacyFileName;
  bool failLoad = false;
  var _next = 0;

  @override
  Future<Result<List<TodoItem>>> loadTodos(
          {bool includeDeleted = false}) async =>
      failLoad
          ? Error<List<TodoItem>>(
              StateError('synthetic Todo load failure'),
            )
          : Ok(includeDeleted ? _stored : items);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(shortcutSettings);

  @override
  Future<Result<TodoAlarmStatus>> todoAlarmStatus() async => Ok(alarmStatus);

  @override
  Future<Result<String?>> todoDamagedLegacyFileName() async =>
      Ok(damagedLegacyFileName);

  @override
  Future<Result<TodoAlarmStatus>> requestTodoAlarmPermissions() async =>
      Ok(requestedAlarmStatus ?? alarmStatus);

  @override
  Future<Result<TodoAlarmStatus>> synchronizeTodoAlarms() async =>
      Ok(requestedAlarmStatus ?? alarmStatus);

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
    List<String> attachments = const [],
    }) async {
    final explicit = parseExplicitDue(due ?? '');
    final item = TodoItem(
      id: id ?? 'todo_${_next++}',
      text: text.trim(),
      due: (due ?? '').trim().isEmpty ? reportDueUnknown : due!.trim(),
      dueDate: explicit == null ? null : _dateOnly(explicit.date),
      dueTime: explicit?.hasTime == true ? _timeOnly(explicit!.date) : null,
      done: false,
      createdAt: DateTime(2026, 11, 6, 0, 0, _next).toIso8601String(),
      timeZone: timeZone,
      alertMinutes: alertMinutes,
      priority: priority,
      subtasks: subtasks,
      recurrence: recurrence,
      seriesId: recurrence == null ? null : 'series_${_next - 1}',
      attachments: attachments,
    );
    _stored.add(item);
    return Ok(item);
  }

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
    List<String>? attachments,
    }) async {
    final explicit = parseExplicitDue(due);
    final date = explicit == null ? null : _dateOnly(explicit.date);
    final time = explicit?.hasTime == true ? _timeOnly(explicit!.date) : null;
    for (var index = 0; index < _stored.length; index++) {
      final item = _stored[index];
      if (item.id == id) {
        _stored[index] = item.copyWith(
          text: text.trim(),
          due: due,
          dueDate: date,
          dueTime: time,
          clearDueDate: date == null,
          clearDueTime: time == null,
          recurrence: recurrence,
          clearRecurrence: clearRecurrence,
          timeZone: timeZone,
          alertMinutes: alertMinutes,
          priority: priority,
          subtasks: subtasks,
          attachments: attachments,
        );
      }
    }
    return const Ok.v();
  }

  @override
  Future<Result<List<String>>> storeTodoPhotos(
    List<String> sourcePaths,
  ) async =>
      Ok([
        for (final path in sourcePaths)
          'fs://${path.split(RegExp(r'[/\\]')).last}',
      ]);

  @override
  Future<Result<String?>> todoAttachmentPath(String reference) async =>
      const Ok(null);

  @override
  Future<Result<void>> setTodoDone({
    required String id,
    required bool done,
  }) async {
    for (var index = 0; index < _stored.length; index++) {
      final item = _stored[index];
      if (item.id == id) {
        _stored[index] = item.copyWith(
          done: done,
          doneAt: done ? '2026-11-13T15:00:00.000Z' : null,
          clearDoneAt: !done,
        );
      }
    }
    return const Ok.v();
  }

  @override
  Future<Result<void>> removeTodo(String id) async {
    for (var index = 0; index < _stored.length; index++) {
      if (_stored[index].id == id) {
        _stored[index] = _stored[index].copyWith(
          deletedAt: '2026-11-13T15:00:00.000Z',
        );
      }
    }
    return const Ok.v();
  }

  @override
  Future<Result<void>> restoreTodo(String id) async {
    for (var index = 0; index < _stored.length; index++) {
      if (_stored[index].id == id) {
        _stored[index] = _stored[index].copyWith(clearDeletedAt: true);
      }
    }
    return const Ok.v();
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

  final List<String> syncReasons = [];
  final List<({String userId, String conflictId, bool keepLocal})>
      resolvedConflicts = [];

  @override
  Future<TodoSyncStatus> loadStatus({
    String? userId,
    FileSystemService? files,
  }) async {
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
    statusNotifier.value = TodoSyncStatus(
      state: TodoSyncBadgeState.syncing,
      paired: currentStatus.paired,
      deviceId: currentStatus.deviceId,
      pendingOutbox: currentStatus.pendingOutbox,
      pendingPc: currentStatus.pendingPc,
      lastSyncedAt: currentStatus.lastSyncedAt,
      conflicts: currentStatus.conflicts,
      unsyncedItemIds: currentStatus.unsyncedItemIds,
      hasCompletedSync: currentStatus.hasCompletedSync,
    );
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
  String due = reportDueUnknown,
  bool done = false,
  bool sourceStale = false,
  int minute = 0,
  TodoSource? source,
}) =>
    TodoItem(
      id: id,
      text: text,
      due: due,
      done: done,
      createdAt: DateTime(2026, 11, 6, 0, minute).toIso8601String(),
      doneAt: done ? '2026-11-13T15:00:00.000Z' : null,
      dueDate: parseExplicitDue(due) == null
          ? null
          : _dateOnly(parseExplicitDue(due)!.date),
      dueTime: parseExplicitDue(due)?.hasTime == true
          ? _timeOnly(parseExplicitDue(due)!.date)
          : null,
      source: source,
      sourceStale: sourceStale,
    );

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _timeOnly(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

void main() {
  late List<String> calendarTitles;

  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    calendarTitles = [];
  });

  Future<_FakeRouter> pump(
    WidgetTester tester,
    List<TodoItem> items, {
    TodoShortcutSettings? shortcutSettings,
    TodoAlarmStatus alarmStatus = TodoAlarmStatus.ready,
    String? damagedLegacyFileName,
    bool failLoad = false,
    Size viewport = const Size(800, 2000),
    TodoSyncService? syncService,
    Future<String?> Function()? userIdResolver,
    bool autoSyncOnLoad = true,
    Future<String?> Function(ImageSource source)? pickPhoto,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = _FakeRouter(items, shortcutSettings: shortcutSettings);
    router.alarmStatus = alarmStatus;
    router.damagedLegacyFileName = damagedLegacyFileName;
    router.failLoad = failLoad;
    final viewModel = TodoViewModel(
      router: router,
      now: () => DateTime.utc(2026, 11, 13, 15),
      syncService: syncService,
      userIdResolver: userIdResolver,
      autoSyncOnLoad: autoSyncOnLoad,
      pickPhoto: pickPhoto,
      openCalendar: ({
        required title,
        required start,
        required end,
        description,
        allDay = false,
      }) async {
        calendarTitles.add(title);
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: TodoScreen(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows an empty message and no items', (tester) async {
    await pump(tester, []);
    expect(find.text(UserStorage.l10n.todoEmptyAll), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    await tester.tap(find.text(UserStorage.l10n.todoTabToday));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.todoEmptyToday), findsOneWidget);
  });

  testWidgets('shows a load error separately from an empty list', (
    tester,
  ) async {
    final router = await pump(tester, [], failLoad: true);
    expect(find.byKey(const ValueKey('todo_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_empty')), findsNothing);

    router.failLoad = false;
    await tester.tap(find.byKey(const ValueKey('todo_retry')));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.todoEmptyAll), findsOneWidget);
  });

  testWidgets('shows undated tasks under the No date section without a due', (
    tester,
  ) async {
    final router = await pump(tester, []);
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Ligar');
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(UserStorage.l10n.todoTabToday));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_undated_header')), findsOneWidget);
    expect(router.items.single.dueDate, isNull);
    expect(router.items.single.due, reportDueUnknown);
  });

  testWidgets('adds an item by hand, completes it and reopens it',
      (tester) async {
    final router = await pump(tester, []);
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('todo_text')), 'Pagar o seguro');
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();
    expect(find.text('Pagar o seguro'), findsOneWidget);
    await tester.tap(find.text(UserStorage.l10n.todoTabToday));
    await tester.pumpAndSettle();

    final box = find.byKey(ValueKey('todo_done_${router.items.single.id}'));
    expect(tester.widget<Checkbox>(box).value, isFalse);
    await tester.tap(box);
    await tester.pumpAndSettle();
    expect(find.text('Pagar o seguro'), findsNothing);
    await tester.tap(find.text(UserStorage.l10n.todoTabCompleted));
    await tester.pumpAndSettle();
    final completedBox = find.byKey(
      ValueKey('todo_done_${router.items.single.id}'),
    );
    expect(tester.widget<Checkbox>(completedBox).value, isTrue);
    await tester.tap(completedBox);
    await tester.pumpAndSettle();
    expect(find.text('Pagar o seguro'), findsNothing);
    await tester.tap(find.text(UserStorage.l10n.todoTabToday));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(box).value, isFalse);
  });

  testWidgets('creates and edits priority and subtasks', (tester) async {
    final router = await pump(
      tester,
      [],
      shortcutSettings: TodoShortcutSettings(defaultAlertMinutes: 12),
    );
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Preparar');
    await tester.tap(find.byKey(const ValueKey('todo_priority_editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.todoPriorityUrgent).last);
    await tester.pumpAndSettle();
    final dialogScroll = find
        .descendant(
          of: find.byKey(const ValueKey('todo_editor_scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final subtaskField = find.byKey(const ValueKey('todo_subtask_new'));
    await tester.scrollUntilVisible(subtaskField, 120,
        scrollable: dialogScroll);
    await tester.enterText(subtaskField, 'Separar documentos');
    await tester.tap(find.byKey(const ValueKey('todo_subtask_add')));
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(router.items.single.priority, TodoPriority.urgent);
    expect(router.items.single.alertMinutes, 12);
    expect(router.items.single.subtasks.single.text, 'Separar documentos');
    expect(find.text(UserStorage.l10n.todoPriorityUrgent), findsOneWidget);
    final subtaskKey = ValueKey(
      'todo_subtask_${router.items.single.id}_'
      '${router.items.single.subtasks.single.id}',
    );
    await tester.tap(find.byKey(subtaskKey));
    await tester.pumpAndSettle();
    expect(router.items.single.subtasks.single.done, isTrue);
  });

  testWidgets('an empty text is not saved', (tester) async {
    final router = await pump(tester, []);
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_text')), findsOneWidget);
    expect(router.items, isEmpty);
  });

  testWidgets('date and time shortcuts save a selected weekly recurrence', (
    tester,
  ) async {
    final router = await pump(
      tester,
      [],
      shortcutSettings: TodoShortcutSettings(defaultAlertMinutes: 10),
    );
    final today = TodoScheduleCalculator.dateForShortcut(
      TodoDateShortcut.today,
      now: DateTime.now(),
    );
    final additionalWeekday = today.weekday == DateTime.monday ? 2 : 1;
    final dialogScroll = find
        .descendant(
          of: find.byKey(const ValueKey('todo_editor_scroll')),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_text')),
      'Revisar relatório',
    );
    await tester.tap(find.byKey(const ValueKey('todo_date_row')));
    await tester.pumpAndSettle();
    final dateShortcut = find.byKey(
      const ValueKey('todo_date_shortcut_today'),
    );
    await tester.scrollUntilVisible(dateShortcut, 100,
        scrollable: dialogScroll);
    await tester.tap(dateShortcut);
    expect(find.byKey(const ValueKey('todo_no_time')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_time_row')));
    await tester.pumpAndSettle();
    final timeShortcut = find.byKey(const ValueKey('todo_time_shortcut_0'));
    await tester.scrollUntilVisible(timeShortcut, 100,
        scrollable: dialogScroll);
    await tester.tap(timeShortcut);
    await tester.pump();
    expect(find.byKey(const ValueKey('todo_no_time')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('todo_repeat_row')));
    await tester.pumpAndSettle();
    final weekly = find.byKey(const ValueKey('todo_repeat_weekly'));
    await tester.scrollUntilVisible(weekly, 100, scrollable: dialogScroll);
    await tester.tap(weekly);
    final day = find.byKey(
      ValueKey('todo_repeat_weekday_$additionalWeekday'),
    );
    await tester.scrollUntilVisible(day, 100, scrollable: dialogScroll);
    await tester.tap(day);
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    final saved = router.items.single;
    expect(saved.text, 'Revisar relatório');
    expect(saved.due, matches(RegExp(r'^\d{4}-\d{2}-\d{2} 09:00$')));
    expect(saved.recurrence?.frequency, TodoRepeatFrequency.weekly);
    expect(saved.recurrence?.weekdays, contains(today.weekday));
    expect(saved.recurrence?.weekdays, contains(additionalWeekday));
    expect(saved.alertMinutes, 10);
  });

  testWidgets('reloads edited shortcut settings before opening the editor', (
    tester,
  ) async {
    final router = await pump(tester, []);
    router.shortcutSettings = TodoShortcutSettings(
      enabledDateShortcuts: const {TodoDateShortcut.inThreeDays},
    );
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_date_row')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_date_shortcut_inThreeDays')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('todo_date_shortcut_today')), findsNothing);
  });

  testWidgets('a time without a valid date stays in the draft', (tester) async {
    final router = await pump(tester, [
      const TodoItem(
        id: 'timeonly',
        text: 'Ligar',
        due: reportDueUnknown,
        dueTime: '09:00',
        done: false,
        createdAt: '2026-11-01T00:00:00Z',
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey('todo_timeonly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(
      find.text(UserStorage.l10n.todoTimeRequiresDate),
      findsOneWidget,
    );
    expect(router.items.single.dueTime, '09:00');
  });

  testWidgets('the task editor fits a narrow screen with larger text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, [], viewport: const Size(320, 720));
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_time_row')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('todo_repeat_row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_repeat_monthly')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the task list fits 320 dp with enlarged text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(
      tester,
      [
        TodoItem(
          id: 'narrow',
          text: 'Preparar a documentação para a reunião de planejamento',
          due: '2026-11-13',
          dueDate: '2026-11-13',
          subtasks: const [TodoSubtask(id: 'step', text: 'Revisar anexos')],
          done: false,
          createdAt: '2026-11-01T00:00:00Z',
        ),
      ],
      viewport: const Size(320, 720),
    );
    expect(find.text('Preparar a documentação para a reunião de planejamento'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly recurrence uses the explicit day of the month', (
    tester,
  ) async {
    final router = await pump(tester, [
      _item('monthly', 'Fechar mês', due: '2027-01-31'),
    ]);
    final dialogScroll = find
        .descendant(
          of: find.byKey(const ValueKey('todo_editor_scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(
      find.byKey(const ValueKey('todo_section_toggle_upcoming')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('todo_monthly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_repeat_row')));
    await tester.pumpAndSettle();
    final monthly = find.byKey(const ValueKey('todo_repeat_monthly'));
    await tester.scrollUntilVisible(monthly, 100, scrollable: dialogScroll);
    await tester.tap(monthly);
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(router.items.single.recurrence?.dayOfMonth, 31);
  });

  testWidgets('editing an occurrence preserves its weekly day selection', (
    tester,
  ) async {
    final router = await pump(tester, [
      TodoItem(
        id: 'weekly',
        text: 'Revisar',
        due: '2026-11-13',
        dueDate: '2026-11-13',
        recurrence: TodoRecurrence.weekly([5]),
        seriesId: 'series-1',
        done: false,
        createdAt: '2026-11-01T00:00:00Z',
      ),
    ]);
    final friday = find.byKey(const ValueKey('todo_repeat_weekday_5'));
    final dialogScroll = find
        .descendant(
          of: find.byKey(const ValueKey('todo_editor_scroll')),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.tap(find.byKey(const ValueKey('todo_weekly')));
    await tester.pumpAndSettle();
    final weekly = find.byKey(const ValueKey('todo_repeat_weekly'));
    await tester.scrollUntilVisible(weekly, 100, scrollable: dialogScroll);
    await tester.tap(weekly);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(friday, 100, scrollable: dialogScroll);
    expect(tester.widget<FilterChip>(friday).selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(router.items.single.recurrence?.weekdays, [5]);
  });

  testWidgets('editing changes the text and the date', (tester) async {
    final router = await pump(tester, [
      const TodoItem(
        id: 't1',
        text: 'Ligar para Rui',
        due: '2026-11-13',
        dueDate: '2026-11-13',
        alertMinutes: 5,
        done: false,
        createdAt: '2026-11-01T00:00:00Z',
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey('todo_t1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Ligar já');
    await tester.tap(find.byKey(const ValueKey('todo_date_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(CalendarDatePicker),
      matching: find.text('30'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();
    expect(router.items.single.text, 'Ligar já');
    expect(router.items.single.due, '2026-11-30');
    expect(router.items.single.alertMinutes, 5);
  });

  testWidgets('a report item shows its source and a date offers the calendar',
      (tester) async {
    await pump(tester, [
      _item(
        't1',
        'Enviar a proposta',
        due: '2026-11-21',
        source: const TodoSource(
          sessionId: 'pdf_1',
          itemId: 'item_1',
          excerpt: 'Carlos envia a proposta',
          clock: 'p.2',
        ),
      ),
    ]);
    expect(
      find.byKey(const ValueKey('todo_section_toggle_upcoming')),
      findsOneWidget,
    );
    expect(find.textContaining('p.2'), findsOneWidget);
    expect(find.textContaining('Carlos envia a proposta'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.addToCalendar));
    await tester.pumpAndSettle();
    expect(calendarTitles, ['Enviar a proposta']);
  });

  testWidgets('shows when the report source changed after adding the Todo',
      (tester) async {
    await pump(tester, [
      _item(
        't1',
        'Enviar a proposta',
        source: const TodoSource(
          sessionId: 'pdf_1',
          itemId: 'item_1',
          excerpt: 'Carlos envia a proposta',
        ),
        sourceStale: true,
      ),
    ]);

    expect(find.byKey(const ValueKey('todo_source_stale_t1')), findsOneWidget);
    expect(find.text(UserStorage.l10n.todoSourceChanged), findsOneWidget);
  });

  testWidgets('a loose date or a done item has no calendar button',
      (tester) async {
    await pump(tester, [
      _item('t1', 'Vago', due: 'sexta'),
      _item('t2', 'Pronto', due: '2026-11-21', done: true),
    ]);
    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.addToCalendar), findsNothing);
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.todoTabCompleted));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_actions_t2')));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.addToCalendar), findsNothing);
  });

  testWidgets('search filters and says when nothing matches', (tester) async {
    await pump(tester, [
      _item('t1', 'Revisar orçamento', due: '2026-11-12', done: true),
      _item('t2', 'Comprar café', minute: 1),
      TodoItem(
        id: 'legacy-done',
        text: 'Legado concluído',
        due: reportDueUnknown,
        done: true,
        createdAt: '2026-11-06T00:00:00Z',
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey('todo_open_search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('todo_search')), 'ORCAMENTO');
    await tester.pumpAndSettle();
    expect(find.text('Revisar orçamento'), findsOneWidget);
    final stateDate = tester
        .widget<Text>(
          find.byKey(const ValueKey('todo_status_date_t1')),
        )
        .data!;
    expect(stateDate, contains(UserStorage.l10n.todoStatusCompleted));
    expect(stateDate, contains('13'));
    expect(find.text('Comprar café'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('todo_search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.todoNoResults), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('todo_search')), 'Legado');
    await tester.pumpAndSettle();
    final legacyStateDate = tester
        .widget<Text>(
          find.byKey(const ValueKey('todo_status_date_legacy-done')),
        )
        .data!;
    expect(legacyStateDate, contains(UserStorage.l10n.todoStatusCompleted));
    expect(legacyStateDate, contains('6'));
  });

  testWidgets('filters the single list by priority', (tester) async {
    await pump(tester, [
      _item('low', 'Baixa').copyWith(priority: TodoPriority.low),
      _item('urgent', 'Urgente').copyWith(priority: TodoPriority.urgent),
    ]);
    await tester.tap(find.byKey(const ValueKey('todo_priority_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.todoPriorityUrgent).last);
    await tester.pumpAndSettle();
    expect(find.text('Urgente'), findsOneWidget);
    expect(find.text('Baixa'), findsNothing);
  });

  testWidgets('deleting offers undo and restores the task', (tester) async {
    final router = await pump(tester, [_item('t1', 'Ligar para Rui')]);
    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.delete));
    await tester.pumpAndSettle();
    expect(find.text('Ligar para Rui'), findsNothing);
    expect(router.items, isEmpty);
    expect(find.text(UserStorage.l10n.todoDeleted), findsOneWidget);
    await tester.tap(find.text(UserStorage.l10n.todoUndo));
    await tester.pumpAndSettle();
    expect(find.text('Ligar para Rui'), findsOneWidget);
    expect(router.items, hasLength(1));
  });

  testWidgets('completed items appear in the Completed tab', (tester) async {
    await pump(tester, [
      _item('t1', 'Primeiro', done: true),
      _item('t2', 'Segundo', minute: 1),
    ]);
    await tester.tap(find.text(UserStorage.l10n.todoTabToday));
    await tester.pumpAndSettle();
    expect(find.text('Primeiro'), findsNothing);
    expect(find.text('Segundo'), findsOneWidget);
    await tester.tap(find.text(UserStorage.l10n.todoTabCompleted));
    await tester.pumpAndSettle();
    expect(find.text('Primeiro'), findsOneWidget);
  });

  testWidgets('warns when task alarm permissions are denied', (tester) async {
    final router = await pump(
      tester,
      [_item('t1', 'Ligar')],
      alarmStatus: TodoAlarmStatus.bothPermissionsDenied,
    );
    expect(find.byKey(const ValueKey('todo_alarm_permission_banner')),
        findsOneWidget);
    expect(find.text(UserStorage.l10n.todoAlarmBothDenied), findsOneWidget);

    router.requestedAlarmStatus = TodoAlarmStatus.ready;
    await tester.tap(find.byKey(const ValueKey('todo_alarm_configure')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_alarm_permission_banner')),
        findsNothing);
  });

  testWidgets('warns when the old task file was damaged and kept aside',
      (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();
    await pump(
      tester,
      [_item('t1', 'Ligar')],
      damagedLegacyFileName: 'todo.json.corrupt-20261114T101500',
    );
    expect(
      find.byKey(const ValueKey('todo_legacy_damaged_banner')),
      findsOneWidget,
    );
    expect(
      find.text(
        'O arquivo antigo de tarefas estava danificado e foi guardado como '
        'todo.json.corrupt-20261114T101500.',
      ),
      findsOneWidget,
    );
    expect(find.text(UserStorage.l10n.todoEmptyToday), findsNothing);
  });

  testWidgets('Todo tasks are not exported to native reminders',
      (tester) async {
    await pump(tester, [_item('t1', 'Ligar', due: '2026-11-21 14:30')]);
    expect(
      find.byKey(const ValueKey('todo_section_toggle_upcoming')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.addToReminders), findsNothing);
  });

  group('accessibility', () {
    final items = [
      _item(
        't1',
        'Ligar',
        due: '2026-11-21 14:30',
        source: const TodoSource(
          sessionId: 'pdf_1',
          itemId: 'item_1',
          excerpt: 'Confirmar horário',
          clock: '10:00',
        ),
      ).copyWith(
        subtasks: const [TodoSubtask(id: 's1', text: 'Separar número')],
      ),
      _item('t2', 'Enviar resumo', done: true, minute: 1),
      _item('t3', 'Revisar', sourceStale: true, minute: 2),
    ];

    testWidgets('tap targets are large and labeled', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, items);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('large text does not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, items);
      expect(tester.takeException(), isNull);
    });
  });

  group('sync status and conflicts', () {
    testWidgets(
        'offline says saved on device with no connection, not sync failed',
        (tester) async {
      for (final language in ['pt', 'en']) {
        SharedPreferences.setMockInitialValues({'language': language});
        await UserStorage.initL10n();
        final l10n = UserStorage.l10n;
        final statusBar = find.byKey(const ValueKey('todo_sync_status_bar'));
        final fakeSync = _FakeTodoSyncService(
          initialStatus: TodoSyncStatus(
            state: TodoSyncBadgeState.savedOnDevice,
            paired: true,
            deviceId: 'dev-1',
            pendingOutbox: 1,
          ),
        );
        await pump(
          tester,
          [_item('t1', 'Local')],
          syncService: fakeSync,
          autoSyncOnLoad: false,
        );

        fakeSync.statusNotifier.value = TodoSyncStatus(
          state: TodoSyncBadgeState.offline,
          paired: true,
          deviceId: 'dev-1',
          pendingOutbox: 1,
          lastError: 'http_0',
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
              of: statusBar, matching: find.text(l10n.todoSyncOffline)),
          findsOneWidget,
        );
        expect(
          find.descendant(
              of: statusBar, matching: find.text(l10n.todoSyncError)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: statusBar,
            matching: find.byIcon(Icons.cloud_off_outlined),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('todo_sync_now_button')),
          findsOneWidget,
        );
      }
    });

    testWidgets(
      'separates Saved on device from Synced across states and per item',
      (tester) async {
        SharedPreferences.setMockInitialValues({'language': 'pt'});
        await UserStorage.initL10n();
        final l10n = UserStorage.l10n;
        final statusBar = find.byKey(const ValueKey('todo_sync_status_bar'));
        final syncNowBtn = find.byKey(const ValueKey('todo_sync_now_button'));

        final fakeSync = _FakeTodoSyncService(
          initialStatus: TodoSyncStatus(
            state: TodoSyncBadgeState.localOnly,
            paired: false,
            deviceId: '',
            pendingOutbox: 0,
          ),
        );
        await pump(
          tester,
          [_item('t1', 'Local'), _item('t2', 'Pendente', minute: 1)],
          syncService: fakeSync,
          autoSyncOnLoad: false,
        );

        // localOnly without pending/error hides sync bar and per-item labels
        expect(statusBar, findsNothing);
        expect(syncNowBtn, findsNothing);
        expect(
          find.byKey(const ValueKey('todo_item_sync_label_t1')),
          findsNothing,
        );

        // localOnly with pending outbox surfaces sync bar and per-item labels
        fakeSync.statusNotifier.value = TodoSyncStatus(
          state: TodoSyncBadgeState.localOnly,
          paired: false,
          deviceId: '',
          pendingOutbox: 1,
          unsyncedItemIds: const {'t1'},
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: statusBar,
            matching: find.text(l10n.todoSyncPendingChanges(1)),
          ),
          findsOneWidget,
        );
        expect(syncNowBtn, findsNothing);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('todo_item_sync_label_t1')),
              )
              .data,
          l10n.todoSyncSavedOnDevice,
        );

        // savedOnDevice with pending outbox
        fakeSync.statusNotifier.value = TodoSyncStatus(
          state: TodoSyncBadgeState.savedOnDevice,
          paired: true,
          deviceId: 'dev-1',
          pendingOutbox: 2,
          unsyncedItemIds: const {'t1', 't2'},
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: statusBar,
            matching: find.text(l10n.todoSyncPendingChanges(2)),
          ),
          findsOneWidget,
        );
        expect(syncNowBtn, findsOneWidget);

        // waitingPc keeps item labeled Saved on device
        fakeSync.statusNotifier.value = TodoSyncStatus(
          state: TodoSyncBadgeState.waitingPc,
          paired: true,
          deviceId: 'dev-1',
          pendingOutbox: 0,
          pendingPc: 1,
          hasCompletedSync: true,
          awaitingPcIds: const {'t1'},
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: statusBar,
            matching: find.text(l10n.todoSyncPendingChanges(1)),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('todo_item_sync_label_t1')),
              )
              .data,
          l10n.todoSyncSavedOnDevice,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('todo_item_sync_label_t2')),
              )
              .data,
          l10n.todoSyncSynced,
        );

        // error keeps retry button visible
        fakeSync.statusNotifier.value = TodoSyncStatus(
          state: TodoSyncBadgeState.error,
          paired: true,
          deviceId: 'dev-1',
          pendingOutbox: 1,
          lastError: 'network_timeout',
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: statusBar,
            matching: find.text(l10n.todoSyncError),
          ),
          findsOneWidget,
        );
        expect(syncNowBtn, findsOneWidget);

        // revoked hides Sync now button
        fakeSync.statusNotifier.value = TodoSyncStatus(
          state: TodoSyncBadgeState.revoked,
          paired: true,
          deviceId: 'dev-1',
          pendingOutbox: 0,
          revoked: true,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: statusBar,
            matching: find.text(l10n.todoSyncRevoked),
          ),
          findsOneWidget,
        );
        expect(syncNowBtn, findsNothing);

        // synced shows last success time and per-item mixed sync labels
        const syncedIso = '2026-11-15T14:30:00.000Z';
        fakeSync.statusNotifier.value = TodoSyncStatus(
          state: TodoSyncBadgeState.synced,
          paired: true,
          deviceId: 'dev-1',
          pendingOutbox: 0,
          pendingPc: 0,
          hasCompletedSync: true,
          lastSyncedAt: syncedIso,
          unsyncedItemIds: const {'t2'},
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: statusBar,
            matching: find.text(l10n.todoSyncSynced),
          ),
          findsOneWidget,
        );
        final expectedTime =
            DateFormat.Hm('pt').format(DateTime.parse(syncedIso).toLocal());
        expect(
          find.descendant(
            of: statusBar,
            matching: find.text(l10n.todoSyncLastSuccess(expectedTime)),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('todo_item_sync_label_t1')),
              )
              .data,
          l10n.todoSyncSynced,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('todo_item_sync_label_t2')),
              )
              .data,
          l10n.todoSyncSavedOnDevice,
        );
      },
    );

    testWidgets(
      'Sync now button triggers manual sync without hiding tasks and resume refreshes',
      (tester) async {
        final l10n = UserStorage.l10n;
        final syncGate = Completer<void>();
        late _FakeRouter router;
        var syncCounter = 0;

        final fakeSync = _FakeTodoSyncService(
          initialStatus: TodoSyncStatus(
            state: TodoSyncBadgeState.savedOnDevice,
            paired: true,
            deviceId: 'dev-1',
            pendingOutbox: 1,
            unsyncedItemIds: const {'t1'},
          ),
          onSyncNow: (_, reason) async {
            syncCounter++;
            if (syncCounter == 1) {
              await syncGate.future;
              router._stored.add(_item('t2', 'Do PC', minute: 1));
            }
            return TodoSyncStatus(
              state: TodoSyncBadgeState.synced,
              paired: true,
              deviceId: 'dev-1',
              pendingOutbox: 0,
              pendingPc: 0,
              hasCompletedSync: true,
              lastSyncedAt: '2026-11-15T15:00:00.000Z',
            );
          },
        );

        router = await pump(
          tester,
          [_item('t1', 'Local')],
          syncService: fakeSync,
          autoSyncOnLoad: false,
        );

        await tester.tap(find.byKey(const ValueKey('todo_sync_now_button')));
        await tester.pump();

        expect(find.text(l10n.todoSyncSyncing), findsOneWidget);
        expect(find.text('Local'), findsOneWidget);

        syncGate.complete();
        await tester.pumpAndSettle();

        expect(fakeSync.syncReasons, ['manual']);
        expect(find.text('Do PC'), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('todo_item_sync_label_t2')),
              )
              .data,
          l10n.todoSyncSynced,
        );

        // Returning to foreground triggers refreshOnResume -> syncNow('resume').
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(fakeSync.syncReasons, ['manual', 'resume']);
      },
    );

    testWidgets(
      'empty list with sync bar and conflict card renders zero ListTiles',
      (tester) async {
        final l10n = UserStorage.l10n;
        const conflict1 = TaskTextConflict(
          id: 't1:text',
          entityId: 't1',
          field: 'text',
          localText: 'Comprar leite integral',
          remoteText: 'Comprar leite sem lactose',
          winnerSide: 'remote',
          winnerText: 'Comprar leite sem lactose',
          loserText: 'Comprar leite integral',
          localUpdatedAt: '2026-11-15T10:00:00Z',
          remoteUpdatedAt: '2026-11-15T10:05:00Z',
        );
        final fakeSync = _FakeTodoSyncService(
          initialStatus: TodoSyncStatus(
            state: TodoSyncBadgeState.savedOnDevice,
            paired: true,
            deviceId: 'dev-1',
            pendingOutbox: 0,
            conflicts: const [conflict1],
          ),
        );

        await pump(
          tester,
          const [],
          syncService: fakeSync,
          userIdResolver: () async => 'u1',
          autoSyncOnLoad: false,
        );

        expect(find.text(l10n.todoEmptyAll), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
        expect(
          find.byKey(const ValueKey('todo_conflict_card_t1:text')),
          findsOneWidget,
        );
        expect(find.text(l10n.todoConflictBannerTitle), findsOneWidget);
        expect(find.text(l10n.todoConflictBannerSubtitle), findsOneWidget);
        expect(find.text(l10n.todoConflictLocalLabel), findsOneWidget);
        expect(find.text('Comprar leite integral'), findsOneWidget);
        expect(find.text(l10n.todoConflictRemoteLabel), findsOneWidget);
        expect(find.text('Comprar leite sem lactose'), findsOneWidget);
      },
    );

    testWidgets(
      'conflict buttons resolve pending_review with Keep local and Use from PC',
      (tester) async {
        const conflict1 = TaskTextConflict(
          id: 't1:text',
          entityId: 't1',
          field: 'text',
          localText: 'Comprar leite integral',
          remoteText: 'Comprar leite sem lactose',
          winnerSide: 'remote',
          winnerText: 'Comprar leite sem lactose',
          loserText: 'Comprar leite integral',
          localUpdatedAt: '2026-11-15T10:00:00Z',
          remoteUpdatedAt: '2026-11-15T10:05:00Z',
        );
        const conflict2 = TaskTextConflict(
          id: 't2:text',
          entityId: 't2',
          field: 'text',
          localText: 'Ligar para Ana',
          remoteText: 'Ligar para Ana às 15h',
          winnerSide: 'remote',
          winnerText: 'Ligar para Ana às 15h',
          loserText: 'Ligar para Ana',
          localUpdatedAt: '2026-11-15T10:00:00Z',
          remoteUpdatedAt: '2026-11-15T10:05:00Z',
        );
        late _FakeRouter router;
        final activeConflicts = <TaskTextConflict>[conflict1, conflict2];
        final interactiveSync = _FakeTodoSyncService(
          initialStatus: TodoSyncStatus(
            state: TodoSyncBadgeState.savedOnDevice,
            paired: true,
            deviceId: 'dev-1',
            pendingOutbox: 0,
            conflicts: activeConflicts,
          ),
          onResolveConflict: ({
            required userId,
            required conflictId,
            required keepLocal,
          }) async {
            final resolved =
                activeConflicts.firstWhere((c) => c.id == conflictId);
            activeConflicts.removeWhere((c) => c.id == conflictId);
            final chosen = keepLocal ? resolved.localText : resolved.remoteText;
            final idx =
                router._stored.indexWhere((t) => t.id == resolved.entityId);
            if (idx >= 0) {
              router._stored[idx] = router._stored[idx].copyWith(text: chosen);
            }
            return TodoSyncStatus(
              state: TodoSyncBadgeState.synced,
              paired: true,
              deviceId: 'dev-1',
              pendingOutbox: 0,
              pendingPc: 0,
              hasCompletedSync: true,
              lastSyncedAt: '2026-11-15T16:00:00.000Z',
              conflicts: [...activeConflicts],
            );
          },
        );

        router = await pump(
          tester,
          [
            _item('t1', 'Comprar leite integral'),
            _item('t2', 'Ligar para Ana', minute: 1),
          ],
          syncService: interactiveSync,
          userIdResolver: () async => 'u1',
          autoSyncOnLoad: false,
        );

        await tester.tap(
          find.byKey(const ValueKey('todo_conflict_keep_local_t1:text')),
        );
        await tester.pumpAndSettle();
        expect(interactiveSync.resolvedConflicts.last.keepLocal, isTrue);
        expect(
          find.byKey(const ValueKey('todo_conflict_card_t1:text')),
          findsNothing,
        );
        expect(router.items.first.text, 'Comprar leite integral');

        await tester.tap(
          find.byKey(const ValueKey('todo_conflict_use_remote_t2:text')),
        );
        await tester.pumpAndSettle();
        expect(interactiveSync.resolvedConflicts.last.keepLocal, isFalse);
        expect(
          find.byKey(const ValueKey('todo_conflict_card_t2:text')),
          findsNothing,
        );
        expect(find.text('Ligar para Ana às 15h'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'sync bar and conflict card satisfy tap target guidelines and 2.0x text scale on 320dp',
      (tester) async {
        const conflict = TaskTextConflict(
          id: 't1:text',
          entityId: 't1',
          field: 'text',
          localText: 'Revisar contrato com o jurídico amanhã cedo',
          remoteText: 'Revisar contrato e enviar parecer até 17h',
          winnerSide: 'remote',
          winnerText: 'Revisar contrato e enviar parecer até 17h',
          loserText: 'Revisar contrato com o jurídico amanhã cedo',
          localUpdatedAt: '2026-11-15T10:00:00Z',
          remoteUpdatedAt: '2026-11-15T10:05:00Z',
        );
        final fakeSync = _FakeTodoSyncService(
          initialStatus: TodoSyncStatus(
            state: TodoSyncBadgeState.synced,
            paired: true,
            deviceId: 'dev-1',
            pendingOutbox: 0,
            pendingPc: 0,
            hasCompletedSync: true,
            lastSyncedAt: '2026-11-15T14:30:00.000Z',
            conflicts: const [conflict],
          ),
        );

        final handle = tester.ensureSemantics();
        await pump(
          tester,
          [_item('t1', 'Revisar contrato com o jurídico amanhã cedo')],
          syncService: fakeSync,
          userIdResolver: () async => 'u1',
          autoSyncOnLoad: false,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();

        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(
          tester,
          [_item('t1', 'Revisar contrato com o jurídico amanhã cedo')],
          viewport: const Size(320, 720),
          syncService: fakeSync,
          userIdResolver: () async => 'u1',
          autoSyncOnLoad: false,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('round 2: tabs, sections, add button, priority, photos', () {
    testWidgets('tabs are Todas, Hoje, Atrasadas, Concluídas with Todas first',
        (tester) async {
      await pump(tester, [_item('t1', 'Ligar')]);
      final l10n = UserStorage.l10n;
      final labels = [
        for (final tab in find.byType(Tab).evaluate()) (tab.widget as Tab).text,
      ];

      expect(labels, [
        l10n.todoTabAll,
        l10n.todoTabToday,
        l10n.todoTabOverdue,
        l10n.todoTabCompleted,
      ]);
      expect(find.byKey(const ValueKey('todo_section_all')), findsOneWidget);
    });

    testWidgets('the all tab lists sections in order and hides empty ones',
        (tester) async {
      final l10n = UserStorage.l10n;
      await pump(tester, [
        _item('done', 'Feita', done: true),
        _item('undated', 'Sem data', minute: 1),
        _item('upcoming', 'Próxima', due: '2026-11-21', minute: 2),
        _item('today', 'Hoje', due: '2026-11-13', minute: 3),
        _item('late', 'Atrasada', due: '2026-11-10', minute: 4),
      ]);

      final headers = [
        'todo_section_toggle_overdue',
        'todo_section_toggle_today',
        'todo_section_toggle_upcoming',
        'todo_section_toggle_undated',
        'todo_section_toggle_completed',
      ].map((key) => find.byKey(ValueKey(key))).toList();
      final tops = [
        for (final header in headers) tester.getTopLeft(header).dy,
      ];
      expect(tops, [...tops]..sort());
      expect(find.text('${l10n.todoTabOverdue} · 1'), findsOneWidget);
      expect(find.text('${l10n.todoTabCompleted} · 1'), findsOneWidget);
    });

    testWidgets('a section with no items does not show its header',
        (tester) async {
      await pump(tester, [_item('only', 'Só hoje', due: '2026-11-13')]);

      expect(find.byKey(const ValueKey('todo_section_toggle_today')),
          findsOneWidget);
      expect(
        find.byKey(const ValueKey('todo_section_toggle_overdue')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('todo_section_toggle_upcoming')),
        findsNothing,
      );
    });

    testWidgets('a section header collapses and reopens its items',
        (tester) async {
      await pump(tester, [
        _item('today', 'Hoje tarefa', due: '2026-11-13'),
        _item('late', 'Atrasada tarefa', due: '2026-11-10', minute: 1),
      ]);
      final toggle = find.byKey(const ValueKey('todo_section_toggle_today'));
      expect(find.text('Hoje tarefa'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Hoje tarefa'), findsNothing);
      expect(find.text('Atrasada tarefa'), findsOneWidget);
      final semantics = tester.getSemantics(toggle).getSemanticsData();
      expect(semantics.label, '${UserStorage.l10n.todoTabToday} · 1');
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(semantics.hasFlag(SemanticsFlag.hasExpandedState), isTrue);
      expect(semantics.hasFlag(SemanticsFlag.isExpanded), isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Hoje tarefa'), findsOneWidget);
    });

    testWidgets('the + button opens the editor and has a labelled semantics',
        (tester) async {
      await pump(tester, []);
      expect(find.bySemanticsLabel(UserStorage.l10n.todoAdd), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('todo_text')), findsOneWidget);
    });

    testWidgets('the task text is a larger multi-line field', (tester) async {
      await pump(tester, []);
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('todo_text')),
      );
      expect(field.minLines, 2);
      expect(field.maxLines, 5);
      expect(field.style?.fontSize, 20);
    });

    testWidgets('priority colours: low blue, high yellow, urgent red',
        (tester) async {
      await pump(tester, [
        _item('low', 'Baixa').copyWith(priority: TodoPriority.low),
        _item('high', 'Alta', minute: 1).copyWith(priority: TodoPriority.high),
        _item('urgent', 'Urgente', minute: 2)
            .copyWith(priority: TodoPriority.urgent),
      ]);
      final l10n = UserStorage.l10n;

      Color? colourOf(String id) => tester
          .widget<Text>(find.byKey(ValueKey('todo_priority_$id')))
          .style
          ?.color;
      expect(colourOf('low'), AppColors.priorityLow);
      expect(colourOf('high'), AppColors.warning);
      expect(colourOf('urgent'), AppColors.danger);
      // The label stays next to the colour.
      expect(find.text(l10n.todoPriorityLow), findsOneWidget);
      expect(find.text(l10n.todoPriorityHigh), findsOneWidget);
      expect(find.text(l10n.todoPriorityUrgent), findsOneWidget);
    });

    testWidgets('a photo is picked, shown, saved and counted on the card',
        (tester) async {
      final picks = <ImageSource>[];
      final router = await pump(
        tester,
        [],
        pickPhoto: (source) async {
          picks.add(source);
          return '/fotos/recibo.jpg';
        },
      );
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Recibo');

      await tester.tap(find.byKey(const ValueKey('todo_photo_gallery')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(picks, [ImageSource.gallery]);
      expect(find.byKey(const ValueKey('todo_photo_0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('todo_photo_camera')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(picks, [ImageSource.gallery, ImageSource.camera]);
      expect(find.byKey(const ValueKey('todo_photo_1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();

      final item = router.items.single;
      expect(item.attachments, ['fs://recibo.jpg', 'fs://recibo.jpg']);
      expect(
        find.byKey(ValueKey('todo_photos_${item.id}')),
        findsOneWidget,
      );
      expect(
        find.text(UserStorage.l10n.todoPhotoCount(2)),
        findsOneWidget,
      );
    });

    testWidgets('removing a thumbnail takes it out of the draft',
        (tester) async {
      final router = await pump(
        tester,
        [],
        pickPhoto: (_) async => '/fotos/nota.jpg',
      );
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Nota');
      await tester.tap(find.byKey(const ValueKey('todo_photo_gallery')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('todo_photo_0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('todo_photo_remove_0')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('todo_photo_0')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();
      expect(router.items.single.attachments, isEmpty);
    });

    testWidgets('a cancelled pick adds no photo', (tester) async {
      await pump(tester, [], pickPhoto: (_) async => null);
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('todo_photo_camera')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('todo_photo_0')), findsNothing);
    });
  });

  group('impeccable polish', () {
    testWidgets('horizontal swipe switches between tabs', (tester) async {
      await pump(tester, [
        _item('today', 'Hoje tarefa'),
        _item('upcoming', 'Futura tarefa', due: '2026-11-21'),
      ]);
      expect(find.text('Hoje tarefa'), findsOneWidget);
      expect(find.text('Futura tarefa'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('todo_section_all')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Futura tarefa'), findsNothing);
      expect(find.text('Hoje tarefa'), findsOneWidget);
    });

    testWidgets('empty title shows inline error instead of failing silently', (
      tester,
    ) async {
      final router = await pump(tester, []);
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.text(UserStorage.l10n.todoTextRequired), findsOneWidget);
      expect(router.items, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Ligar');
      await tester.pump();
      expect(find.text(UserStorage.l10n.todoTextRequired), findsNothing);
    });

    testWidgets('calendar day and time shortcut populate the editor fields', (
      tester,
    ) async {
      final router = await pump(tester, [
        _item('t1', 'Ligar para Rui', due: '2026-11-13'),
      ]);
      await tester.tap(find.byKey(const ValueKey('todo_t1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_date_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('20'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_time_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_time_shortcut_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();

      final minutes = TodoShortcutSettings.defaults.timeShortcutsMinutes.first;
      final clock = '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
          '${(minutes % 60).toString().padLeft(2, '0')}';
      expect(router.items.single.due, '2026-11-20 $clock');
    });

    testWidgets(
      'priority filter displays active bar and clears from filtered empty state',
      (tester) async {
        await pump(tester, [
          _item('low', 'Baixa').copyWith(priority: TodoPriority.low),
        ]);
        await tester.tap(find.byKey(const ValueKey('todo_priority_filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(UserStorage.l10n.todoPriorityUrgent).last);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('todo_active_filter_bar')),
          findsOneWidget,
        );
        expect(find.text(UserStorage.l10n.todoFilterEmpty), findsOneWidget);
        expect(
          find.byKey(const ValueKey('todo_empty_clear_filter')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('todo_empty_clear_filter')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('todo_active_filter_bar')),
          findsNothing,
        );
        expect(find.text('Baixa'), findsOneWidget);
      },
    );

    testWidgets('search screen exposes a clear query button', (tester) async {
      await pump(tester, [_item('t1', 'Revisar orçamento')]);
      await tester.tap(find.byKey(const ValueKey('todo_open_search')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('todo_search_clear')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('todo_search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo_search_clear')), findsOneWidget);
      expect(find.text(UserStorage.l10n.todoNoResults), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('todo_search_clear')));
      await tester.pumpAndSettle();
      expect(find.text(UserStorage.l10n.todoSearchStart), findsOneWidget);
    });
  });

  group('full-screen editor and task cards', () {
    testWidgets('tapping Data expands the calendar and a picked day sets it',
        (tester) async {
      final router = await pump(tester, [
        _item('t1', 'Ligar para Rui', due: '2026-11-13'),
      ]);
      await tester.tap(find.byKey(const ValueKey('todo_t1')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);

      await tester.tap(find.byKey(const ValueKey('todo_date_row')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('20'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();

      expect(router.items.single.due, '2026-11-20');
    });

    testWidgets('Daqui a 1 hora sets the time from now, on a 5 minute step',
        (tester) async {
      final router = await pump(tester, []);
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('todo_text')),
        'Revisar relatório',
      );
      await tester.tap(find.byKey(const ValueKey('todo_time_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_time_in_1h')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();

      final saved = router.items.single;
      expect(
        saved.due,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')),
      );
      expect(int.parse(saved.due.substring(14, 16)) % 5, 0);
      expect(saved.dueTime, isNotNull);
    });

    testWidgets('removing the date also removes the time and the repeat',
        (tester) async {
      final router = await pump(tester, []);
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('todo_text')),
        'Pagar conta',
      );
      await tester.tap(find.byKey(const ValueKey('todo_date_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_date_shortcut_today')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_time_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_time_shortcut_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_repeat_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_repeat_daily')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo_no_time')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('todo_clear_date')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo_clear_date')), findsNothing);
      expect(find.byKey(const ValueKey('todo_clear_time')), findsNothing);
      expect(find.byKey(const ValueKey('todo_no_time')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();

      expect(router.items.single.due, reportDueUnknown);
      expect(router.items.single.dueTime, isNull);
      expect(router.items.single.recurrence, isNull);
    });

    testWidgets('early alert page saves 1 hora antes and a custom value',
        (tester) async {
      final router = await pump(tester, [
        const TodoItem(
          id: 'alarm',
          text: 'Ligar para a escola',
          due: '2026-11-13 23:30',
          dueDate: '2026-11-13',
          dueTime: '23:30',
          alertMinutes: 20,
          done: false,
          createdAt: '2026-11-01T00:00:00Z',
        ),
      ]);
      await tester.tap(find.byKey(const ValueKey('todo_alarm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_alert_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_alert_option_60')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();
      expect(router.items.single.alertMinutes, 60);

      await tester.tap(find.byKey(const ValueKey('todo_alarm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_alert_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_alert_option_custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_alert_done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
      await tester.pumpAndSettle();
      expect(router.items.single.alertMinutes, 30);
    });

    testWidgets('the bottom pill cancels without saving', (tester) async {
      final router = await pump(tester, []);
      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('todo_text')),
        'Não salvar',
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('todo_dialog_save'))).dy,
        greaterThan(
          tester.getCenter(find.byKey(const ValueKey('todo_text'))).dy,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('todo_dialog_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo_text')), findsNothing);
      expect(router.items, isEmpty);
    });

    testWidgets(
        'the list shows task cards and the bottom pill opens the editor',
        (tester) async {
      await pump(
        tester,
        [_item('t1', 'Revisar orçamento', due: '2026-11-13')],
      );

      final card = tester.widget<Material>(
        find.byKey(const ValueKey('todo_card_t1')),
      );
      expect(card.color, AppColors.surface);
      expect(find.byKey(const ValueKey('todo_status_date_t1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('todo_add')));
      await tester.pumpAndSettle();
      expect(find.text(UserStorage.l10n.todoNewTask), findsOneWidget);
      expect(find.byKey(const ValueKey('todo_text')), findsOneWidget);
    });
  });
}
