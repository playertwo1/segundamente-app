import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';

void main() {
  test('defaults match the approved day and time shortcuts', () {
    final settings = TodoShortcutSettings.defaults;

    expect(settings.enabledDateShortcuts, {
      TodoDateShortcut.today,
      TodoDateShortcut.tomorrow,
      TodoDateShortcut.nextMonday,
    });
    expect(settings.timeShortcutsMinutes, [540, 840, 1200]);
    expect(settings.defaultAlertMinutes, 20);
  });

  test('round trips edited shortcut settings', () {
    final settings = TodoShortcutSettings(
      enabledDateShortcuts: const {TodoDateShortcut.inThreeDays},
      timeShortcutsMinutes: const [600, 900, 1260],
      defaultAlertMinutes: 35,
    );

    final restored = TodoShortcutSettings.fromJson(settings.toJson());

    expect(restored.enabledDateShortcuts, {TodoDateShortcut.inThreeDays});
    expect(restored.timeShortcutsMinutes, [600, 900, 1260]);
    expect(restored.defaultAlertMinutes, 35);
  });

  test('rejects invalid time and alert settings', () {
    expect(
      () => TodoShortcutSettings(timeShortcutsMinutes: const [540, 840]),
      throwsArgumentError,
    );
    expect(
      () => TodoShortcutSettings(timeShortcutsMinutes: const [540, 1440, 1200]),
      throwsArgumentError,
    );
    expect(() => TodoShortcutSettings(defaultAlertMinutes: -1),
        throwsArgumentError);
  });
}
