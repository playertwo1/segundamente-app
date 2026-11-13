import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns Todo shortcut defaults when nothing is saved', () async {
    final settings = await UserStorage.getTodoShortcutSettings();

    expect(settings.enabledDateShortcuts,
        TodoShortcutSettings.defaults.enabledDateShortcuts);
    expect(settings.timeShortcutsMinutes, [540, 840, 1200]);
    expect(settings.defaultAlertMinutes, 20);
  });

  test('persists edited Todo shortcut preferences', () async {
    final settings = TodoShortcutSettings(
      enabledDateShortcuts: const {TodoDateShortcut.inThreeDays},
      timeShortcutsMinutes: const [630, 900, 1230],
      defaultAlertMinutes: 45,
    );

    await UserStorage.setTodoShortcutSettings(settings);
    final loaded = await UserStorage.getTodoShortcutSettings();

    expect(loaded.enabledDateShortcuts, {TodoDateShortcut.inThreeDays});
    expect(loaded.timeShortcutsMinutes, [630, 900, 1230]);
    expect(loaded.defaultAlertMinutes, 45);
  });
}
