import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
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
  bool failLoad = false;
  var _next = 0;

  @override
  Future<Result<List<TodoItem>>> loadTodos() async => failLoad
      ? Error<List<TodoItem>>(StateError('synthetic Todo load failure'))
      : Ok(items);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(shortcutSettings);

  @override
  Future<Result<TodoItem>> addTodo({
    required String text,
    String? due,
    String? dueDate,
    String? dueTime,
    String timeZone = todoTimeZone,
    int alertMinutes = 20,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    TodoRecurrence? recurrence,
  }) async {
    final explicit = parseExplicitDue(due ?? '');
    final item = TodoItem(
      id: 'todo_${_next++}',
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
        );
      }
    }
    return const Ok.v();
  }

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
  late List<String> reminderTitles;
  var permissionGranted = true;

  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    calendarTitles = [];
    reminderTitles = [];
    permissionGranted = true;
  });

  Future<_FakeRouter> pump(
    WidgetTester tester,
    List<TodoItem> items, {
    TodoShortcutSettings? shortcutSettings,
    bool failLoad = false,
    Size viewport = const Size(800, 2000),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = _FakeRouter(items, shortcutSettings: shortcutSettings);
    router.failLoad = failLoad;
    final viewModel = TodoViewModel(
      router: router,
      now: () => DateTime.utc(2026, 11, 13, 15),
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
      ensureReminderPermission: () async => permissionGranted,
      createReminder: ({required title, required dueDate, notes}) async {
        reminderTitles.add(title);
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TodoScreen(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows an empty message and no items', (tester) async {
    await pump(tester, []);
    expect(find.text(UserStorage.l10n.todoEmptyToday), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
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
    expect(find.text(UserStorage.l10n.todoEmptyToday), findsOneWidget);
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
    final router = await pump(tester, []);
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Preparar');
    await tester.tap(find.byKey(const ValueKey('todo_priority_editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.todoPriorityUrgent).last);
    await tester.pumpAndSettle();
    final dialogScroll = find
        .descendant(
          of: find.byType(AlertDialog),
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
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_text')),
      'Revisar relatório',
    );
    final dateShortcut = find.byKey(
      const ValueKey('todo_date_shortcut_today'),
    );
    await tester.scrollUntilVisible(dateShortcut, 100,
        scrollable: dialogScroll);
    await tester.tap(dateShortcut);
    expect(find.byKey(const ValueKey('todo_no_time')), findsOneWidget);

    final timeShortcut = find.byKey(const ValueKey('todo_time_shortcut_0'));
    await tester.scrollUntilVisible(timeShortcut, 100,
        scrollable: dialogScroll);
    await tester.tap(timeShortcut);
    await tester.pump();
    expect(find.byKey(const ValueKey('todo_no_time')), findsNothing);

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

    expect(
      find.byKey(const ValueKey('todo_date_shortcut_inThreeDays')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('todo_date_shortcut_today')), findsNothing);
  });

  testWidgets('a time without a valid date stays in the draft', (tester) async {
    final router = await pump(tester, []);
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Ligar');
    await tester.enterText(find.byKey(const ValueKey('todo_time')), '09:00');
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(
      find.text(UserStorage.l10n.todoTimeRequiresDate),
      findsOneWidget,
    );
    expect(router.items, isEmpty);
  });

  testWidgets('the task editor fits a narrow screen with larger text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, [], viewport: const Size(320, 720));
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_time')), findsOneWidget);
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
    final router = await pump(tester, []);
    final dialogScroll = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.tap(find.byKey(const ValueKey('todo_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('todo_text')), 'Fechar mês');
    await tester.enterText(
      find.byKey(const ValueKey('todo_due')),
      '2027-01-31',
    );
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
          of: find.byType(AlertDialog),
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
    final router = await pump(tester, [_item('t1', 'Ligar para Rui')]);
    await tester.tap(find.byKey(const ValueKey('todo_t1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('todo_text')), 'Ligar já');
    await tester.enterText(
        find.byKey(const ValueKey('todo_due')), '2026-11-30');
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();
    expect(router.items.single.text, 'Ligar já');
    expect(router.items.single.due, '2026-11-30');
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
    await tester.tap(find.text(UserStorage.l10n.todoTabUpcoming));
    await tester.pumpAndSettle();
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
    expect(find.text('Primeiro'), findsNothing);
    expect(find.text('Segundo'), findsOneWidget);
    await tester.tap(find.text(UserStorage.l10n.todoTabCompleted));
    await tester.pumpAndSettle();
    expect(find.text('Primeiro'), findsOneWidget);
  });

  testWidgets('a reminder is created only after the user confirms',
      (tester) async {
    await pump(tester, [_item('t1', 'Ligar', due: '2026-11-21 14:30')]);
    await tester.tap(find.text(UserStorage.l10n.todoTabUpcoming));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.addToReminders));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_reminder_cancel')));
    await tester.pumpAndSettle();
    expect(reminderTitles, isEmpty);

    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.addToReminders));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_reminder_confirm')));
    await tester.pumpAndSettle();
    expect(reminderTitles, ['Ligar']);
  });

  testWidgets('a denied permission creates no reminder', (tester) async {
    permissionGranted = false;
    await pump(tester, [_item('t1', 'Ligar', due: '2026-11-21 14:30')]);
    await tester.tap(find.text(UserStorage.l10n.todoTabUpcoming));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.addToReminders));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_reminder_confirm')));
    await tester.pumpAndSettle();
    expect(reminderTitles, isEmpty);
  });

  testWidgets('a date without a time has no reminder button', (tester) async {
    await pump(tester, [_item('t1', 'Ligar', due: '2026-11-21')]);
    await tester.tap(find.text(UserStorage.l10n.todoTabUpcoming));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_actions_t1')));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.addToReminders), findsNothing);
  });

  group('accessibility', () {
    final items = [
      _item('t1', 'Ligar', due: '2026-11-21 14:30'),
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
}
