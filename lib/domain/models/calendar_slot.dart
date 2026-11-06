import 'package:memex/domain/models/explicit_due.dart';

class CalendarSlot {
  const CalendarSlot({
    required this.start,
    required this.end,
    required this.allDay,
  });

  final DateTime start;
  final DateTime end;
  final bool allDay;
}

/// The calendar entry for a date the user wrote in full, or null. An event
/// with no time of day is all-day, expressed in UTC midnight as calendars
/// expect; one with a time lasts an hour.
CalendarSlot? calendarSlotFor(String due) {
  final explicit = parseExplicitDue(due);
  if (explicit == null) return null;
  final start = explicit.hasTime
      ? explicit.date
      : DateTime.utc(
          explicit.date.year, explicit.date.month, explicit.date.day);
  return CalendarSlot(
    start: start,
    end: start.add(
      explicit.hasTime ? const Duration(hours: 1) : const Duration(days: 1),
    ),
    allDay: !explicit.hasTime,
  );
}
