import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

enum TodoDateStatus { noDate, today, upcoming, overdue }

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

  static DateTime dateTimeInTimeZone(DateTime instant, String timeZone) {
    final local = tz.TZDateTime.from(instant, _location(timeZone));
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  static tz.TZDateTime? alarmDateTimeFor({
    required String? dueDate,
    required String? dueTime,
    required String timeZone,
    required int alertMinutes,
    String? snoozedUntil,
    required DateTime now,
  }) {
    final date = _parseDate(dueDate);
    final time = _parseTime(dueTime);
    if (date == null || time == null || alertMinutes < 0) return null;

    final location = _location(timeZone);
    if (snoozedUntil != null) {
      final snooze = DateTime.tryParse(snoozedUntil);
      if (snooze != null) {
        return snooze.isAfter(now)
            ? tz.TZDateTime.from(snooze, location)
            : null;
      }
    }
    final due = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      time.$1,
      time.$2,
    );
    final nowLocal = tz.TZDateTime.from(now, location);
    final alarm = due.subtract(Duration(minutes: alertMinutes));
    if (alarm.isAfter(nowLocal)) return alarm;
    // Warning time passed but the task is still ahead: remind at the due time.
    return due.isAfter(nowLocal) ? due : null;
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

  static TodoDateStatus statusFor({
    required String? dueDate,
    required DateTime now,
    required String timeZone,
    String? dueTime,
  }) {
    final date = _parseDate(dueDate);
    if (date == null) return TodoDateStatus.noDate;
    final localNow = tz.TZDateTime.from(now, _location(timeZone));
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    if (date.isBefore(today)) return TodoDateStatus.overdue;
    if (date.isAfter(today)) return TodoDateStatus.upcoming;
    if (dueTime == null) return TodoDateStatus.today;
    try {
      return _timeHasPassed(dueTime, localNow)
          ? TodoDateStatus.overdue
          : TodoDateStatus.today;
    } on FormatException {
      return TodoDateStatus.today;
    }
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

  static DateTime? _parseDate(String? value) {
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

  static (int, int)? _parseTime(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    return hour < 24 && minute < 60 ? (hour, minute) : null;
  }

  static tz.Location _location(String name) {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    return tz.getLocation(name);
  }
}
