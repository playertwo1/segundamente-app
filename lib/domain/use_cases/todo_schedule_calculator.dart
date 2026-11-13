import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class TodoScheduleCalculator {
  TodoScheduleCalculator._();

  static bool _timeZonesInitialized = false;

  static DateTime dateForShortcut(
    TodoDateShortcut shortcut, {
    required DateTime now,
    String timeZone = todoTimeZone,
  }) {
    final local = tz.TZDateTime.from(now, _location(timeZone));
    final today = DateTime.utc(local.year, local.month, local.day);
    return switch (shortcut) {
      TodoDateShortcut.today => today,
      TodoDateShortcut.tomorrow => today.add(const Duration(days: 1)),
      TodoDateShortcut.inThreeDays => today.add(const Duration(days: 3)),
      TodoDateShortcut.nextMonday => today.add(Duration(
          days: today.weekday == DateTime.monday
              ? 7
              : (DateTime.monday - today.weekday + 7) % 7,
        )),
    };
  }

  static DateTime nextOccurrenceDate({
    required TodoRecurrence recurrence,
    required DateTime afterDate,
  }) {
    final after = DateTime.utc(afterDate.year, afterDate.month, afterDate.day);
    return switch (recurrence.frequency) {
      TodoRepeatFrequency.daily => after.add(const Duration(days: 1)),
      TodoRepeatFrequency.weekly => _nextWeekday(recurrence, after),
      TodoRepeatFrequency.monthly => _nextMonthDay(recurrence, after),
    };
  }

  static DateTime nextUpcomingOccurrenceDate({
    required TodoRecurrence recurrence,
    required DateTime afterDate,
    required DateTime now,
    required String timeZone,
    String? dueTime,
  }) {
    final localNow = tz.TZDateTime.from(now, _location(timeZone));
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final timePassed = _timeHasPassed(dueTime, localNow);
    var next = nextOccurrenceDate(
      recurrence: recurrence,
      afterDate: afterDate,
    );
    while (
        next.isBefore(today) || (next.isAtSameMomentAs(today) && timePassed)) {
      next = nextOccurrenceDate(recurrence: recurrence, afterDate: next);
    }
    return next;
  }

  static DateTime _nextWeekday(TodoRecurrence recurrence, DateTime after) {
    for (var offset = 1; offset <= 7; offset++) {
      final candidate = after.add(Duration(days: offset));
      if (recurrence.weekdays.contains(candidate.weekday)) return candidate;
    }
    throw StateError('weekly recurrence has no weekdays');
  }

  static DateTime _nextMonthDay(TodoRecurrence recurrence, DateTime after) {
    final firstNextMonth = DateTime.utc(after.year, after.month + 1, 1);
    final lastDay = DateTime.utc(
      firstNextMonth.year,
      firstNextMonth.month + 1,
      0,
    ).day;
    final day = recurrence.dayOfMonth!;
    return DateTime.utc(
      firstNextMonth.year,
      firstNextMonth.month,
      day > lastDay ? lastDay : day,
    );
  }

  static bool _timeHasPassed(String? dueTime, tz.TZDateTime now) {
    if (dueTime == null) return false;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(dueTime);
    if (match == null) throw FormatException('invalid Todo time: $dueTime');
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      throw FormatException('invalid Todo time: $dueTime');
    }
    return hour * 60 + minute <= now.hour * 60 + now.minute;
  }

  static tz.Location _location(String name) {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    return tz.getLocation(name);
  }
}
