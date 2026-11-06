import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/ui/todo/widgets/todo_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the list in memory; the real file storage has its own tests.
class _FakeRouter implements MemexRouter {
  _FakeRouter(this.items);

  List<TodoItem> items;
  var _next = 0;

  @override
  Future<Result<List<TodoItem>>> loadTodos() async => Ok([...items]);

  @override
  Future<Result<TodoItem>> addTodo({required String text, String? due}) async {
    final item = TodoItem(
      id: 'todo_${_next++}',
      text: text.trim(),
      due: (due ?? '').trim().isEmpty ? reportDueUnknown : due!.trim(),
      done: false,
      createdAt: DateTime(2026, 11, 6, 0, 0, _next).toIso8601String(),
    );
    items = [...items, item];
    return Ok(item);
  }

  @override
  Future<Result<void>> editTodo({
    required String id,
    required String text,
    required String due,
  }) async {
    items = [
      for (final i in items)
        i.id == id ? i.copyWith(text: text.trim(), due: due) : i,
    ];
    return const Ok.v();
  }

  @override
  Future<Result<void>> setTodoDone({
    required String id,
    required bool done,
  }) async {
    items = [
      for (final i in items) i.id == id ? i.copyWith(done: done) : i,
    ];
    return const Ok.v();
  }

  @override
  Future<Result<void>> removeTodo(String id) async {
    items = [
      for (final i in items)
        if (i.id != id) i,
    ];
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
  int minute = 0,
  TodoSource? source,
}) =>
    TodoItem(
      id: id,
      text: text,
      due: due,
      done: done,
      createdAt: DateTime(2026, 11, 6, 0, minute).toIso8601String(),
      source: source,
    );

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
    List<TodoItem> items,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = _FakeRouter(items);
    final viewModel = TodoViewModel(
      router: router,
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
    expect(find.text(UserStorage.l10n.todoEmpty), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
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
    expect(tester.widget<Checkbox>(box).value, isTrue);
    await tester.tap(box);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(box).value, isFalse);
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
    expect(find.textContaining('p.2'), findsOneWidget);
    expect(find.textContaining('Carlos envia a proposta'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_calendar_t1')));
    await tester.pumpAndSettle();
    expect(calendarTitles, ['Enviar a proposta']);
  });

  testWidgets('a loose date or a done item has no calendar button',
      (tester) async {
    await pump(tester, [
      _item('t1', 'Vago', due: 'sexta'),
      _item('t2', 'Pronto', due: '2026-11-21', done: true),
    ]);
    expect(find.byKey(const ValueKey('todo_calendar_t1')), findsNothing);
    expect(find.byKey(const ValueKey('todo_calendar_t2')), findsNothing);
  });

  testWidgets('search filters and says when nothing matches', (tester) async {
    await pump(tester, [
      _item('t1', 'Revisar orçamento'),
      _item('t2', 'Comprar café', minute: 1),
    ]);
    await tester.enterText(
        find.byKey(const ValueKey('todo_search')), 'ORCAMENTO');
    await tester.pumpAndSettle();
    expect(find.text('Revisar orçamento'), findsOneWidget);
    expect(find.text('Comprar café'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('todo_search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.todoNoResults), findsOneWidget);
  });

  testWidgets('removing asks first and keeps the item on cancel',
      (tester) async {
    final router = await pump(tester, [_item('t1', 'Ligar para Rui')]);

    await tester.tap(find.byKey(const ValueKey('todo_remove_t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_delete_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Ligar para Rui'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_remove_t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_delete_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Ligar para Rui'), findsNothing);
    expect(router.items, isEmpty);
  });

  testWidgets('done items go below open ones', (tester) async {
    await pump(tester, [
      _item('t1', 'Primeiro', done: true),
      _item('t2', 'Segundo', minute: 1),
    ]);
    final firstY = tester.getTopLeft(find.text('Primeiro')).dy;
    final secondY = tester.getTopLeft(find.text('Segundo')).dy;
    expect(secondY, lessThan(firstY));
  });
}
