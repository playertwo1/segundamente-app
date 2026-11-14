import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';

void main() {
  test('uses the Todo timezone when UTC is already on the next date', () {
    final instant = DateTime.utc(2026, 11, 14, 1);

    expect(
      TodoScheduleCalculator.dateForShortcut(
        TodoDateShortcut.today,
        now: instant,
      ),
      DateTime.utc(2026, 11, 13),
    );
    expect(
      TodoScheduleCalculator.dateForShortcut(
        TodoDateShortcut.tomorrow,
        now: instant,
      ),
      DateTime.utc(2026, 11, 14),
    );
  });

  test('keeps local calendar dates continuous across a timezone DST jump', () {
    final beforeSaoPauloSpringForward = DateTime.utc(2018, 11, 4, 2, 30);

    expect(
      TodoScheduleCalculator.dateForShortcut(
        TodoDateShortcut.today,
        now: beforeSaoPauloSpringForward,
      ),
      DateTime.utc(2018, 11, 3),
    );
    expect(
      TodoScheduleCalculator.dateForShortcut(
        TodoDateShortcut.tomorrow,
        now: beforeSaoPauloSpringForward,
      ),
      DateTime.utc(2018, 11, 4),
    );
  });

  test('three days crosses month and next Monday is strictly next week', () {
    final sunday = DateTime.utc(2026, 11, 29, 16);

    expect(
      TodoScheduleCalculator.dateForShortcut(
        TodoDateShortcut.inThreeDays,
        now: sunday,
      ),
      DateTime.utc(2026, 12, 2),
    );
    expect(
      TodoScheduleCalculator.dateForShortcut(
        TodoDateShortcut.nextMonday,
        now: DateTime.utc(2026, 11, 16, 15),
      ),
      DateTime.utc(2026, 11, 23),
    );
  });

  test('weekly repetition advances to the next chosen weekday', () {
    final next = TodoScheduleCalculator.nextOccurrenceDate(
      recurrence: TodoRecurrence.weekly([1, 3, 5]),
      afterDate: DateTime.utc(2026, 11, 13),
    );

    expect(next, DateTime.utc(2026, 11, 16));
  });

  test('daily repetition advances by one calendar day', () {
    expect(
      TodoScheduleCalculator.nextOccurrenceDate(
        recurrence: TodoRecurrence.daily(),
        afterDate: DateTime.utc(2026, 11, 30),
      ),
      DateTime.utc(2026, 12, 1),
    );
  });

  test('skips completed cadence dates but keeps a future time today', () {
    final next = TodoScheduleCalculator.nextUpcomingOccurrenceDate(
      recurrence: TodoRecurrence.daily(),
      afterDate: DateTime.utc(2026, 11, 10),
      now: DateTime.utc(2026, 11, 14, 1),
      timeZone: 'America/Sao_Paulo',
      dueTime: '23:00',
    );

    expect(next, DateTime.utc(2026, 11, 13));
  });

  test('keeps an untimed occurrence due today active through that day', () {
    final next = TodoScheduleCalculator.nextUpcomingOccurrenceDate(
      recurrence: TodoRecurrence.daily(),
      afterDate: DateTime.utc(2026, 11, 12),
      now: DateTime.utc(2026, 11, 14, 1),
      timeZone: 'America/Sao_Paulo',
    );

    expect(next, DateTime.utc(2026, 11, 13));
  });

  test('classifies tasks by local date and due time', () {
    final now = DateTime.utc(2026, 11, 14, 1); // 22:00 in São Paulo on Nov 13.

    expect(
      TodoScheduleCalculator.statusFor(
        dueDate: null,
        now: now,
        timeZone: 'America/Sao_Paulo',
      ),
      TodoDateStatus.noDate,
    );
    expect(
      TodoScheduleCalculator.statusFor(
        dueDate: '2026-11-12',
        now: now,
        timeZone: 'America/Sao_Paulo',
      ),
      TodoDateStatus.overdue,
    );
    expect(
      TodoScheduleCalculator.statusFor(
        dueDate: '2026-11-13',
        dueTime: '23:00',
        now: now,
        timeZone: 'America/Sao_Paulo',
      ),
      TodoDateStatus.today,
    );
    expect(
      TodoScheduleCalculator.statusFor(
        dueDate: '2026-11-13',
        dueTime: '09:00',
        now: now,
        timeZone: 'America/Sao_Paulo',
      ),
      TodoDateStatus.overdue,
    );
    expect(
      TodoScheduleCalculator.statusFor(
        dueDate: '2026-11-14',
        now: now,
        timeZone: 'America/Sao_Paulo',
      ),
      TodoDateStatus.upcoming,
    );
  });

  test('converts completion timestamps to the task timezone', () {
    expect(
      TodoScheduleCalculator.dateTimeInTimeZone(
        DateTime.utc(2026, 11, 14, 1),
        'America/Sao_Paulo',
      ),
      DateTime(2026, 11, 13, 22),
    );
  });

  test('monthly day 31 clamps to the last day of short months', () {
    final february = TodoScheduleCalculator.nextOccurrenceDate(
      recurrence: TodoRecurrence.monthly(31),
      afterDate: DateTime.utc(2027, 1, 31),
    );
    final march = TodoScheduleCalculator.nextOccurrenceDate(
      recurrence: TodoRecurrence.monthly(31),
      afterDate: february,
    );

    expect(february, DateTime.utc(2027, 2, 28));
    expect(march, DateTime.utc(2027, 3, 31));
  });

  test('an unknown stored time zone falls back instead of throwing', () {
    // 12:00 UTC is 09:00 in the Todo default zone: a 10:00 task is still ahead.
    final now = DateTime.utc(2026, 11, 14, 12);

    expect(
      TodoScheduleCalculator.statusFor(
        dueDate: '2026-11-14',
        dueTime: '10:00',
        now: now,
        timeZone: 'Mars/Olympus',
      ),
      TodoDateStatus.today,
    );
    final alarm = TodoScheduleCalculator.alarmDateTimeFor(
      dueDate: '2026-11-14',
      dueTime: '10:00',
      timeZone: 'Mars/Olympus',
      alertMinutes: 20,
      now: now,
    );
    expect(alarm?.toUtc(), DateTime.utc(2026, 11, 14, 12, 40));
  });
}
