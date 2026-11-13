import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/todo/view_models/todo_proposal_viewmodel.dart';
import 'package:memex/ui/todo/widgets/todo_proposal_card.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProposalRouter implements MemexRouter {
  final List<TodoItem> items = [];
  int addCalls = 0;
  String? savedId;
  String? savedDue;
  String? savedText;
  int? savedAlertMinutes;

  @override
  Future<Result<List<TodoItem>>> loadTodos(
          {bool includeDeleted = false}) async =>
      Ok([
        for (final item in items)
          if (includeDeleted || !item.isTombstoned) item,
      ]);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(TodoShortcutSettings.defaults);

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
  }) async {
    addCalls++;
    savedId = id;
    savedDue = due;
    savedText = text;
    savedAlertMinutes = alertMinutes;
    final item = TodoItem(
      id: id ?? 'generated-id',
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  Future<_ProposalRouter> pumpProposal(
    WidgetTester tester,
    TodoProposal proposal,
  ) async {
    final router = _ProposalRouter();
    final viewModel = TodoProposalViewModel(router: router);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: TodoProposalCard(
              proposal: proposal,
              viewModel: viewModel,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('reviews a missing-time proposal before saving it', (
    tester,
  ) async {
    final router = await pumpProposal(
      tester,
      TodoProposal(
        id: 'proposal-1',
        title: 'Enviar relatório',
        dateState: TodoProposalDateState.explicit,
        dueDate: '2026-11-20',
        timeState: TodoProposalTimeState.unspecified,
      ),
    );

    expect(router.addCalls, 0);
    expect(
      find.textContaining(UserStorage.l10n.todoNoTime),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('todo_proposal_review')));
    await tester.pumpAndSettle();

    expect(find.text(UserStorage.l10n.todoNoTime), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('todo_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(router.addCalls, 0);

    await tester.tap(find.byKey(const ValueKey('todo_proposal_review')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_text')),
      'Enviar relatório revisado',
    );
    await tester.enterText(
      find.byKey(const ValueKey('todo_alert_minutes')),
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(router.addCalls, 1);
    expect(router.savedId, 'proposal-1');
    expect(router.savedText, 'Enviar relatório revisado');
    expect(router.savedDue, '2026-11-20');
    expect(router.savedAlertMinutes, 10);
    expect(find.byKey(const ValueKey('todo_proposal_added')), findsOneWidget);
  });

  testWidgets('weekday-only date stays unresolved until owner chooses', (
    tester,
  ) async {
    final router = await pumpProposal(
      tester,
      TodoProposal(
        id: 'proposal-2',
        title: 'Enviar relatório',
        dateState: TodoProposalDateState.ambiguous,
        datePhrase: 'sexta',
        timeState: TodoProposalTimeState.unspecified,
      ),
    );

    expect(find.text('sexta · ${UserStorage.l10n.todoNoTime}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('todo_proposal_review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(router.addCalls, 0);
    expect(
      find.text(UserStorage.l10n.todoProposalDateMustResolve),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('todo_proposal_no_date')),
    );
    await tester.tap(find.byKey(const ValueKey('todo_proposal_no_date')));
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(router.addCalls, 1);
    expect(router.savedDue, '');
  });

  testWidgets('vague time requires the owner to resolve it', (tester) async {
    final router = await pumpProposal(
      tester,
      TodoProposal(
        id: 'proposal-3',
        title: 'Ligar para a escola',
        dateState: TodoProposalDateState.explicit,
        dueDate: '2026-11-20',
        timeState: TodoProposalTimeState.ambiguous,
        timePhrase: 'de manhã',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('todo_proposal_review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();
    expect(router.addCalls, 0);
    expect(
      find.text(UserStorage.l10n.todoProposalTimeMustResolve),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('todo_proposal_no_time')),
    );
    await tester.tap(find.byKey(const ValueKey('todo_proposal_no_time')));
    await tester.tap(find.byKey(const ValueKey('todo_dialog_save')));
    await tester.pumpAndSettle();

    expect(router.addCalls, 1);
    expect(router.savedDue, '2026-11-20');
  });
}
