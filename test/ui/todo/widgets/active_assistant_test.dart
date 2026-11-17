import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/active_assistant_service.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/persona_task_suggestion.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/ui/todo/widgets/active_assistant_settings_page.dart';
import 'package:memex/ui/todo/widgets/todo_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTodoRouter implements MemexRouter {
  _FakeTodoRouter(List<TodoItem> initial) : items = [...initial];

  final List<TodoItem> items;
  final List<String> addedTexts = [];
  TodoShortcutSettings shortcutSettings = TodoShortcutSettings.defaults;

  @override
  Future<Result<List<TodoItem>>> loadTodos(
          {bool includeDeleted = false}) async =>
      Ok([for (final i in items) if (includeDeleted || !i.isTombstoned) i]);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(shortcutSettings);

  @override
  Future<Result<TodoAlarmStatus>> todoAlarmStatus() async =>
      const Ok(TodoAlarmStatus.ready);

  @override
  Future<Result<String?>> todoDamagedLegacyFileName() async => const Ok(null);

  @override
  Future<Result<TodoAlarmStatus>> synchronizeTodoAlarms() async =>
      const Ok(TodoAlarmStatus.ready);

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
    addedTexts.add(text);
    final item = TodoItem(
      id: id ?? 'id-${items.length}',
      text: text,
      due: due ?? '',
      dueDate: dueDate,
      dueTime: dueTime,
      timeZone: timeZone,
      alertMinutes: alertMinutes,
      priority: priority,
      subtasks: subtasks,
      recurrence: recurrence,
      done: false,
      createdAt: '2026-11-13T00:00:00',
    );
    items.add(item);
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
    final index = items.indexWhere((i) => i.id == id);
    if (index == -1) return Error(StateError('not found'));
    final updated = items[index].copyWith(
      text: text,
      due: due,
      dueDate: dueDate,
      dueTime: dueTime,
      timeZone: timeZone ?? items[index].timeZone,
      alertMinutes: alertMinutes,
      priority: priority,
      subtasks: subtasks,
      recurrence: recurrence,
      clearRecurrence: clearRecurrence,
    );
    items[index] = updated;
    return const Ok.v();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 2026-11-16 12:30 UTC = 09:30 local America/Sao_Paulo (morning period)
  final fixedMorning = DateTime.utc(2026, 11, 16, 12, 30);

  late ActiveAssistantSettings assistantSettings;
  String? dismissedBriefingKey;
  Map<String, String> stalledSnoozeMap = {};
  String? personaSuggestionsRaw;

  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();

    assistantSettings = ActiveAssistantSettings(
      morningBriefingEnabled: true,
      afternoonBriefingEnabled: true,
      stalledReminderEnabled: true,
      stalledThresholdDays: 3,
      personaSuggestionsEnabled: true,
      quietHoursEnabled: false,
    );
    dismissedBriefingKey = null;
    stalledSnoozeMap = {};
    personaSuggestionsRaw = null;
  });

  ActiveAssistantService createAssistantService() {
    return ActiveAssistantService.forTesting(
      clock: () => fixedMorning,
      loadSettings: () async => assistantSettings,
      saveSettings: (s) async => assistantSettings = s,
      loadDismissedBriefingKey: () async => dismissedBriefingKey,
      saveDismissedBriefingKey: (k) async => dismissedBriefingKey = k,
      loadStalledSnoozeMap: () async => stalledSnoozeMap,
      saveStalledSnoozeMap: (m) async => stalledSnoozeMap = m,
      loadPersonaSuggestionsRaw: () async => personaSuggestionsRaw,
      savePersonaSuggestionsRaw: (j) async => personaSuggestionsRaw = j,
    );
  }

  Widget createTestApp(Widget home) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }

  testWidgets(
      'Morning briefing displays overdue, timed commitments, and priorities accurately, and dismissing briefing preserves tasks in TodoScreen',
      (tester) async {
    final overdueTask = const TodoItem(
      id: 'task-overdue',
      text: 'Tarefa atrasada importante',
      due: '2026-11-15',
      dueDate: '2026-11-15',
      done: false,
      createdAt: '2026-11-10T10:00:00.000Z',
    );
    final commitmentTask = const TodoItem(
      id: 'task-commitment',
      text: 'Reunião com equipe',
      due: '2026-11-16 10:00',
      dueDate: '2026-11-16',
      dueTime: '10:00',
      done: false,
      createdAt: '2026-11-15T10:00:00.000Z',
    );
    final priorityTask = const TodoItem(
      id: 'task-priority',
      text: 'Planejamento Q4',
      due: '2026-11-16',
      dueDate: '2026-11-16',
      priority: TodoPriority.high,
      done: false,
      createdAt: '2026-11-15T10:00:00.000Z',
    );

    final router = _FakeTodoRouter([overdueTask, commitmentTask, priorityTask]);
    final service = createAssistantService();
    final viewModel = TodoViewModel(
      router: router,
      activeAssistantService: service,
      now: () => fixedMorning,
    );

    await tester.pumpWidget(createTestApp(TodoScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    // Summary bar shows updates
    expect(find.byKey(const ValueKey('todo_active_assistant_bar')),
        findsOneWidget);

    // Open sheet
    await tester
        .tap(find.byKey(const ValueKey('todo_open_active_assistant')));
    await tester.pumpAndSettle();

    // Check briefing card
    final card = find.byKey(const ValueKey('active_assistant_briefing_card'));
    expect(card, findsOneWidget);
    expect(
        find.descendant(
            of: card, matching: find.text('Tarefa atrasada importante')),
        findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.text('Reunião com equipe')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Planejamento Q4')),
        findsOneWidget);

    // Dismiss briefing
    await tester
        .tap(find.byKey(const ValueKey('active_assistant_briefing_dismiss')));
    await tester.pumpAndSettle();

    // Close bottom sheet
    await tester.tap(find.byKey(const ValueKey('active_assistant_sheet_close')));
    await tester.pumpAndSettle();

    // Tasks are still visible on TodoScreen
    expect(find.text('Reunião com equipe'), findsOneWidget);
    expect(find.text('Planejamento Q4'), findsOneWidget);
  });

  testWidgets(
      'Stalled task nudge displays stalled days and snooze hides the nudge while task remains visible in TodoScreen',
      (tester) async {
    // Created 5 days before fixedMorning -> 5 days stalled
    final stalledTask = const TodoItem(
      id: 'task-stalled',
      text: 'Projeto antigo parado',
      due: '',
      done: false,
      createdAt: '2026-11-11T10:00:00.000Z',
    );

    final router = _FakeTodoRouter([stalledTask]);
    final service = createAssistantService();
    final viewModel = TodoViewModel(
      router: router,
      activeAssistantService: service,
      now: () => fixedMorning,
    );

    await tester.pumpWidget(createTestApp(TodoScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    // Open sheet
    await tester
        .tap(find.byKey(const ValueKey('todo_open_active_assistant')));
    await tester.pumpAndSettle();

    // Nudge is shown with 5d parada
    final nudge =
        find.byKey(const ValueKey('active_assistant_stalled_task-stalled'));
    expect(nudge, findsOneWidget);
    expect(
        find.descendant(
            of: nudge, matching: find.text('Projeto antigo parado')),
        findsOneWidget);
    expect(
        find.descendant(of: nudge, matching: find.text('5d parada')),
        findsOneWidget);

    // Tap Snooze
    await tester
        .tap(find.byKey(const ValueKey('stalled_snooze_task-stalled')));
    await tester.pumpAndSettle();

    // Nudge is now hidden from the sheet
    expect(find.byKey(const ValueKey('active_assistant_stalled_task-stalled')),
        findsNothing);

    // Close sheet
    await tester.tap(find.byKey(const ValueKey('active_assistant_sheet_close')));
    await tester.pumpAndSettle();

    // Task still exists in TodoScreen
    expect(find.text('Projeto antigo parado'), findsWidgets);
  });

  testWidgets(
      'Persona suggestion renders TodoProposalCard and only calls router.addTodo after review confirmation',
      (tester) async {
    final suggestion = PersonaTaskSuggestion(
      id: 'sug-1',
      characterId: 'yaoyao',
      characterName: 'Yaoyao',
      message: 'Achei que seria bom caminhar um pouco.',
      proposal: TodoProposal(
        id: 'prop-walk',
        title: 'Caminhada no parque',
        dateState: TodoProposalDateState.explicit,
        dueDate: '2026-11-20',
        timeState: TodoProposalTimeState.unspecified,
      ),
      createdAt: fixedMorning.toUtc().toIso8601String(),
    );
    personaSuggestionsRaw = jsonEncode([suggestion.toJson()]);

    final router = _FakeTodoRouter([]);
    final service = createAssistantService();
    final viewModel = TodoViewModel(
      router: router,
      activeAssistantService: service,
      now: () => fixedMorning,
    );

    await tester.pumpWidget(createTestApp(TodoScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    // Open sheet
    await tester
        .tap(find.byKey(const ValueKey('todo_open_active_assistant')));
    await tester.pumpAndSettle();

    // Verify persona suggestion
    expect(find.text('Yaoyao'), findsOneWidget);
    expect(find.text('Achei que seria bom caminhar um pouco.'), findsOneWidget);
    expect(find.text('Caminhada no parque'), findsOneWidget);

    // Verify router.addTodo has NOT been called yet
    expect(router.addedTexts, isEmpty);

    // Tap Review on the proposal card
    await tester.tap(find.byKey(const ValueKey('todo_proposal_review')));
    await tester.pumpAndSettle();

    // Cancel dialog
    await tester.tap(find.byKey(const ValueKey('todo_dialog_cancel')));
    await tester.pumpAndSettle();

    // Still not added
    expect(router.addedTexts, isEmpty);

    // Tap Review again and confirm
    await tester.tap(find.byKey(const ValueKey('todo_proposal_review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    // Now it was added!
    expect(router.addedTexts, contains('Caminhada no parque'));
  });

  testWidgets(
      'ActiveAssistantSettingsPage persists toggles, thresholds, and silence button',
      (tester) async {
    final service = createAssistantService();

    await tester.pumpWidget(createTestApp(
      ActiveAssistantSettingsPage(service: service),
    ));
    await tester.pumpAndSettle();

    // Toggle morning briefing switch
    final morningSwitch =
        find.byKey(const ValueKey('active_assistant_morning_enabled'));
    await tester.tap(morningSwitch);
    await tester.pumpAndSettle();

    final loadedAfterToggle = await service.loadSettings();
    expect(loadedAfterToggle.morningBriefingEnabled, isFalse);

    // Tap Silence button
    final silenceButton =
        find.byKey(const ValueKey('active_assistant_silence_toggle'));
    await tester.scrollUntilVisible(silenceButton, 200);
    expect(find.text('Silenciar hoje'), findsOneWidget);
    await tester.tap(silenceButton);
    await tester.pumpAndSettle();

    final loadedAfterSilence = await service.loadSettings();
    expect(loadedAfterSilence.silencedUntilIso, isNotNull);
    expect(find.text('Desativar silêncio'), findsOneWidget);

    // Tap Silence button again to clear silence
    await tester.tap(silenceButton);
    await tester.pumpAndSettle();

    final loadedAfterClear = await service.loadSettings();
    expect(loadedAfterClear.silencedUntilIso, isNull);
    expect(find.text('Silenciar hoje'), findsOneWidget);
  });
}
