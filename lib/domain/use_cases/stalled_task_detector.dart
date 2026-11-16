import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';

class StalledTaskNudge {
  const StalledTaskNudge({
    required this.item,
    required this.stalledDays,
    required this.isOverdueStalled,
  });

  final TodoItem item;
  TodoItem get task => item;
  final int stalledDays;
  final bool isOverdueStalled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StalledTaskNudge &&
          runtimeType == other.runtimeType &&
          item == other.item &&
          stalledDays == other.stalledDays &&
          isOverdueStalled == other.isOverdueStalled;

  @override
  int get hashCode => Object.hash(item, stalledDays, isOverdueStalled);

  @override
  String toString() =>
      'StalledTaskNudge(taskId: ${item.id}, stalledDays: $stalledDays, isOverdueStalled: $isOverdueStalled)';
}

class StalledTaskDetector {
  StalledTaskDetector._();

  static List<StalledTaskNudge> detect({
    required List<TodoItem> items,
    required DateTime now,
    required ActiveAssistantSettings settings,
    Map<String, String> snoozedUntilByTaskId = const {},
    String timeZone = todoTimeZone,
  }) {
    if (!settings.stalledReminderEnabled ||
        settings.isSilencedAt(now, timeZone: timeZone)) {
      return const [];
    }

    final nudges = <StalledTaskNudge>[];

    for (final item in items) {
      if (item.done || item.isTombstoned) continue;

      final rawSnooze = snoozedUntilByTaskId[item.id];
      if (rawSnooze != null) {
        final snoozeDate = DateTime.tryParse(rawSnooze);
        if (snoozeDate != null && snoozeDate.isAfter(now)) {
          continue;
        }
      }

      final itemTz = item.timeZone.isNotEmpty ? item.timeZone : timeZone;
      final itemLocalNow =
          TodoScheduleCalculator.dateTimeInTimeZone(now, itemTz);
      final itemToday = DateTime.utc(
        itemLocalNow.year,
        itemLocalNow.month,
        itemLocalNow.day,
      );

      final int stalledDays;
      final bool isOverdueStalled;

      if (item.dueDate != null) {
        final dueUtcDate = _parseDueDate(item.dueDate);
        if (dueUtcDate == null) continue;
        stalledDays = itemToday.difference(dueUtcDate).inDays;
        isOverdueStalled = true;
      } else {
        final created = DateTime.tryParse(item.createdAt);
        if (created == null) continue;
        final createdLocal =
            TodoScheduleCalculator.dateTimeInTimeZone(created, itemTz);
        final createdLocalDate = DateTime.utc(
          createdLocal.year,
          createdLocal.month,
          createdLocal.day,
        );
        stalledDays = itemToday.difference(createdLocalDate).inDays;
        isOverdueStalled = false;
      }

      if (stalledDays >= settings.stalledThresholdDays) {
        nudges.add(StalledTaskNudge(
          item: item,
          stalledDays: stalledDays,
          isOverdueStalled: isOverdueStalled,
        ));
      }
    }

    nudges.sort((a, b) {
      final daysCmp = b.stalledDays.compareTo(a.stalledDays);
      if (daysCmp != 0) return daysCmp;

      final priorityCmp =
          b.item.priority.index.compareTo(a.item.priority.index);
      if (priorityCmp != 0) return priorityCmp;

      return a.item.createdAt.compareTo(b.item.createdAt);
    });

    return List.unmodifiable(nudges);
  }

  static DateTime? _parseDueDate(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}
