enum TodoDateShortcut { today, tomorrow, inThreeDays, nextMonday }

class TodoShortcutSettings {
  TodoShortcutSettings({
    Set<TodoDateShortcut>? enabledDateShortcuts,
    List<int>? timeShortcutsMinutes,
    this.defaultAlertMinutes = 20,
  })  : enabledDateShortcuts = Set.unmodifiable(
          enabledDateShortcuts ?? defaultEnabledDateShortcuts,
        ),
        timeShortcutsMinutes = List.unmodifiable(
          timeShortcutsMinutes ?? defaultTimeShortcutsMinutes,
        ) {
    if (this.timeShortcutsMinutes.length != 3 ||
        this
            .timeShortcutsMinutes
            .any((minutes) => minutes < 0 || minutes >= 1440)) {
      throw ArgumentError.value(timeShortcutsMinutes, 'timeShortcutsMinutes');
    }
    if (defaultAlertMinutes < 0) {
      throw ArgumentError.value(defaultAlertMinutes, 'defaultAlertMinutes');
    }
  }

  static const Set<TodoDateShortcut> defaultEnabledDateShortcuts = {
    TodoDateShortcut.today,
    TodoDateShortcut.tomorrow,
    TodoDateShortcut.nextMonday,
  };
  static const List<int> defaultTimeShortcutsMinutes = [540, 840, 1200];

  static TodoShortcutSettings get defaults => TodoShortcutSettings();

  final Set<TodoDateShortcut> enabledDateShortcuts;
  final List<int> timeShortcutsMinutes;
  final int defaultAlertMinutes;

  TodoShortcutSettings copyWith({
    Set<TodoDateShortcut>? enabledDateShortcuts,
    List<int>? timeShortcutsMinutes,
    int? defaultAlertMinutes,
  }) =>
      TodoShortcutSettings(
        enabledDateShortcuts: enabledDateShortcuts ?? this.enabledDateShortcuts,
        timeShortcutsMinutes: timeShortcutsMinutes ?? this.timeShortcutsMinutes,
        defaultAlertMinutes: defaultAlertMinutes ?? this.defaultAlertMinutes,
      );

  Map<String, dynamic> toJson() => {
        'enabled_date_shortcuts': [
          for (final shortcut in TodoDateShortcut.values)
            if (enabledDateShortcuts.contains(shortcut)) shortcut.name,
        ],
        'time_shortcuts_minutes': timeShortcutsMinutes,
        'default_alert_minutes': defaultAlertMinutes,
      };

  static TodoShortcutSettings fromJson(Map<String, dynamic> json) {
    final rawDays = json['enabled_date_shortcuts'];
    final rawTimes = json['time_shortcuts_minutes'];
    final rawAlert = json['default_alert_minutes'];
    if (rawDays != null && rawDays is! List) {
      throw const FormatException('Todo date shortcuts are malformed');
    }
    if (rawTimes != null && rawTimes is! List) {
      throw const FormatException('Todo time shortcuts are malformed');
    }
    if (rawAlert != null && rawAlert is! num) {
      throw const FormatException('Todo alert setting is malformed');
    }
    final days = rawDays is List
        ? {
            for (final value in rawDays)
              for (final shortcut in TodoDateShortcut.values)
                if (value == shortcut.name) shortcut,
          }
        : defaultEnabledDateShortcuts;
    final times = rawTimes is List
        ? rawTimes.map((value) {
            if (value is! num) {
              throw const FormatException('Todo time shortcut is malformed');
            }
            return value.toInt();
          }).toList()
        : defaultTimeShortcutsMinutes;
    try {
      return TodoShortcutSettings(
        enabledDateShortcuts: days,
        timeShortcutsMinutes: times,
        defaultAlertMinutes: (rawAlert as num?)?.toInt() ?? 20,
      );
    } on ArgumentError {
      throw const FormatException('Todo shortcut settings are out of range');
    }
  }
}
