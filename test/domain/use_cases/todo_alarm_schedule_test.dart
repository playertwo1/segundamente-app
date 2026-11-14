import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';

void main() {
  group('TodoScheduleCalculator.alarmDateTimeFor', () {
    test('converts the due time minus alert into its chosen time zone', () {
      final alarm = TodoScheduleCalculator.alarmDateTimeFor(
        dueDate: '2026-11-14',
        dueTime: '08:30',
        timeZone: 'America/Sao_Paulo',
        alertMinutes: 20,
        now: DateTime.utc(2026, 11, 14, 11, 9),
      );

      expect(alarm, isNotNull);
      expect(alarm!.year, 2026);
      expect(alarm.month, 11);
      expect(alarm.day, 14);
      expect(alarm.hour, 8);
      expect(alarm.minute, 10);
      expect(alarm.toUtc(), DateTime.utc(2026, 11, 14, 11, 10));
    });

    test('does not schedule an undated or untimed Todo', () {
      expect(
        TodoScheduleCalculator.alarmDateTimeFor(
          dueDate: '2026-11-14',
          dueTime: null,
          timeZone: 'America/Sao_Paulo',
          alertMinutes: 20,
          now: DateTime.utc(2026, 11, 14, 11),
        ),
        isNull,
      );
      expect(
        TodoScheduleCalculator.alarmDateTimeFor(
          dueDate: null,
          dueTime: '08:30',
          timeZone: 'America/Sao_Paulo',
          alertMinutes: 20,
          now: DateTime.utc(2026, 11, 14, 11),
        ),
        isNull,
      );
    });

    test('keeps the warning time while it is still ahead', () {
      final alarm = TodoScheduleCalculator.alarmDateTimeFor(
        dueDate: '2026-11-14',
        dueTime: '08:30',
        timeZone: 'America/Sao_Paulo',
        alertMinutes: 20,
        now: DateTime.utc(2026, 11, 14, 10),
      );

      expect(alarm, isNotNull);
      expect(alarm!.toUtc(), DateTime.utc(2026, 11, 14, 11, 10));
    });

    test('fires at the due time once the warning time has passed', () {
      for (final now in [
        DateTime.utc(2026, 11, 14, 11, 10),
        DateTime.utc(2026, 11, 14, 11, 25),
      ]) {
        final alarm = TodoScheduleCalculator.alarmDateTimeFor(
          dueDate: '2026-11-14',
          dueTime: '08:30',
          timeZone: 'America/Sao_Paulo',
          alertMinutes: 20,
          now: now,
        );

        expect(alarm, isNotNull, reason: 'now=$now');
        expect(alarm!.toUtc(), DateTime.utc(2026, 11, 14, 11, 30));
      }
    });

    test('skips alarms once the due time has passed or is now', () {
      for (final now in [
        DateTime.utc(2026, 11, 14, 11, 30),
        DateTime.utc(2026, 11, 14, 11, 40),
      ]) {
        expect(
          TodoScheduleCalculator.alarmDateTimeFor(
            dueDate: '2026-11-14',
            dueTime: '08:30',
            timeZone: 'America/Sao_Paulo',
            alertMinutes: 20,
            now: now,
          ),
          isNull,
          reason: 'now=$now',
        );
      }
    });

    test('rejects invalid wall-clock times', () {
      expect(
        TodoScheduleCalculator.alarmDateTimeFor(
          dueDate: '2026-11-14',
          dueTime: '24:00',
          timeZone: 'America/Sao_Paulo',
          alertMinutes: 20,
          now: DateTime.utc(2026, 11, 14, 11),
        ),
        isNull,
      );
    });

    test('a future snooze replaces the original alarm time', () {
      final alarm = TodoScheduleCalculator.alarmDateTimeFor(
        dueDate: '2026-11-14',
        dueTime: '08:30',
        timeZone: 'America/Sao_Paulo',
        alertMinutes: 20,
        snoozedUntil: '2026-11-14T11:25:00.000Z',
        now: DateTime.utc(2026, 11, 14, 11, 10),
      );

      expect(alarm, isNotNull);
      expect(alarm!.toUtc(), DateTime.utc(2026, 11, 14, 11, 25));
    });

    test('does not revive the original alarm after a snooze expires', () {
      expect(
        TodoScheduleCalculator.alarmDateTimeFor(
          dueDate: '2026-11-14',
          dueTime: '08:30',
          timeZone: 'America/Sao_Paulo',
          alertMinutes: 20,
          snoozedUntil: '2026-11-14T11:20:00.000Z',
          now: DateTime.utc(2026, 11, 14, 11, 21),
        ),
        isNull,
      );
    });

    test('ignores malformed snooze data and keeps the original alarm', () {
      final alarm = TodoScheduleCalculator.alarmDateTimeFor(
        dueDate: '2026-11-14',
        dueTime: '08:30',
        timeZone: 'America/Sao_Paulo',
        alertMinutes: 20,
        snoozedUntil: 'not-a-date',
        now: DateTime.utc(2026, 11, 14, 11, 9),
      );

      expect(alarm, isNotNull);
      expect(alarm!.hour, 8);
      expect(alarm.minute, 10);
    });
  });
}
