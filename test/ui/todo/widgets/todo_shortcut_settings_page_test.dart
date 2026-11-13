import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/todo/view_models/todo_shortcut_settings_viewmodel.dart';
import 'package:memex/ui/todo/widgets/todo_shortcut_settings_page.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ShortcutRouter implements MemexRouter {
  TodoShortcutSettings settings = TodoShortcutSettings.defaults;
  int loadFailures = 0;

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async {
    if (loadFailures > 0) {
      loadFailures--;
      return Error<TodoShortcutSettings>(StateError('load failed'));
    }
    return Ok(settings);
  }

  @override
  Future<Result<void>> saveTodoShortcutSettings(
    TodoShortcutSettings value,
  ) async {
    settings = value;
    return const Ok.v();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();
  });

  Future<_ShortcutRouter> pumpPage(
    WidgetTester tester, {
    int loadFailures = 0,
  }) async {
    final router = _ShortcutRouter()..loadFailures = loadFailures;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TodoShortcutSettingsPage(
          viewModel: TodoShortcutSettingsViewModel(router: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows defaults and persists an enabled date shortcut', (
    tester,
  ) async {
    final router = await pumpPage(tester);
    final shortcut = find.byKey(
      const ValueKey('todo_shortcut_day_inThreeDays'),
    );
    await tester.ensureVisible(shortcut);
    expect(tester.widget<SwitchListTile>(shortcut).value, isFalse);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();

    expect(
      router.settings.enabledDateShortcuts,
      contains(TodoDateShortcut.inThreeDays),
    );
    expect(
        find.text(UserStorage.l10n.todoShortcutsTimezoneValue), findsOneWidget);
  });

  testWidgets('shows a retry action when settings cannot be loaded', (
    tester,
  ) async {
    await pumpPage(tester, loadFailures: 1);
    expect(find.text(UserStorage.l10n.todoShortcutsLoadFailed), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_shortcut_retry')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('todo_shortcut_day_today')), findsOneWidget);
    expect(find.text(UserStorage.l10n.todoShortcutsLoadFailed), findsNothing);
  });

  testWidgets('edits a time shortcut and the default alert', (tester) async {
    final router = await pumpPage(tester);
    final timeShortcut = find.byKey(const ValueKey('todo_shortcut_time_0'));
    await tester.scrollUntilVisible(timeShortcut, 160);
    await tester.tap(timeShortcut);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '10');
    await tester.enterText(find.byType(TextField).at(1), '15');
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(Scaffold)),
    ).okButtonLabel;
    await tester.tap(find.text(ok));
    await tester.pumpAndSettle();

    expect(router.settings.timeShortcutsMinutes.first, 615);
    final alert = find.byKey(const ValueKey('todo_shortcut_alert_minutes'));
    await tester.scrollUntilVisible(alert, 160);
    await tester.tap(alert);
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserStorage.l10n.todoShortcutsAlertBefore(10)));
    await tester.pumpAndSettle();

    expect(router.settings.defaultAlertMinutes, 10);
  });
}
