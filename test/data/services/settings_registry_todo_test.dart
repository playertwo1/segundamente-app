import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/settings_registry.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/settings/widgets/settings_page.dart';
import 'package:memex/ui/todo/widgets/active_assistant_settings_page.dart';
import 'package:memex/ui/todo/widgets/todo_shortcut_settings_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempRoot;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('todo_settings_registry_');
    await FileSystemService.init(tempRoot.path);
  });

  tearDownAll(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();
  });

  testWidgets('Todo shortcuts are searchable and open their settings page', (
    tester,
  ) async {
    final item = SettingsRegistry.allItems.firstWhere(
      (item) => item.id == 'settings.todo_shortcuts',
    );
    late Widget targetPage;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            targetPage = item.navigationTarget.pageBuilder(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(item.title, UserStorage.l10n.todoShortcutsTitle);
    expect(item.keywords, contains('tarefas'));
    expect(targetPage, isA<TodoShortcutSettingsPage>());
  });

  testWidgets('settings list opens Todo shortcut settings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('todo-shortcut-settings'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.todoShortcutsTitle), findsOneWidget);

    final timezone = find.byKey(const ValueKey('todo_shortcut_timezone'));
    await tester.scrollUntilVisible(timezone, 160);
    expect(timezone, findsOneWidget);
  });

  testWidgets('Active assistant is searchable and opens its settings page', (
    tester,
  ) async {
    final item = SettingsRegistry.allItems.firstWhere(
      (item) => item.id == 'settings.active_assistant',
    );
    late Widget targetPage;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            targetPage = item.navigationTarget.pageBuilder(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(item.title, UserStorage.l10n.activeAssistantSettingsTitle);
    expect(item.keywords, contains('assistente'));
    expect(targetPage, isA<ActiveAssistantSettingsPage>());
  });

  testWidgets('settings list opens Active Assistant settings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('active-assistant-settings'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      find.text(UserStorage.l10n.activeAssistantSettingsTitle),
      findsOneWidget,
    );
  });
}
