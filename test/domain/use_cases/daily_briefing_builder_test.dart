import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/daily_briefing_builder.dart';

void main() {
  group('DailyBriefingBuilder.build', () {
    // 2026-11-16 13:30 UTC = 2026-11-16 10:30 local in America/Sao_Paulo (UTC-3)
    final fixedNow = DateTime.utc(2026, 11, 16, 13, 30);

    TodoItem makeTodo({
      required String id,
      required String text,
      String? dueDate,
      String? dueTime,
      TodoPriority priority = TodoPriority.normal,
      bool done = false,
      String? deletedAt,
      String createdAt = '2026-11-01T10:00:00.000Z',
    }) {
      return TodoItem(
        id: id,
        text: text,
        due: dueDate ?? '',
        dueDate: dueDate,
        dueTime: dueTime,
        priority: priority,
        done: done,
        deletedAt: deletedAt,
        createdAt: createdAt,
      );
    }

    test('partitions and sorts overdue, today commitments, and priority items',
        () {
      final overdue1 = makeTodo(
        id: 'o1',
        text: 'Overdue yesterday normal',
        dueDate: '2026-11-15',
        dueTime: '10:00',
        priority: TodoPriority.normal,
        createdAt: '2026-11-01T10:00:00.000Z',
      );
      final overdue2 = makeTodo(
        id: 'o2',
        text: 'Overdue today earlier urgent',
        dueDate: '2026-11-16',
        dueTime: '08:00',
        priority: TodoPriority.urgent,
        createdAt: '2026-11-01T10:00:00.000Z',
      );
      final overdue3 = makeTodo(
        id: 'o3',
        text: 'Overdue yesterday high',
        dueDate: '2026-11-15',
        dueTime: '10:00',
        priority: TodoPriority.high,
        createdAt: '2026-11-01T10:00:00.000Z',
      );
      final todayTimed1 = makeTodo(
        id: 't1',
        text: 'Today 16:00 low',
        dueDate: '2026-11-16',
        dueTime: '16:00',
        priority: TodoPriority.low,
      );
      final todayTimed2 = makeTodo(
        id: 't2',
        text: 'Today 11:00 high',
        dueDate: '2026-11-16',
        dueTime: '11:00',
        priority: TodoPriority.high,
      );
      final todayUntimed = makeTodo(
        id: 'tu',
        text: 'Today untimed urgent',
        dueDate: '2026-11-16',
        dueTime: null,
        priority: TodoPriority.urgent,
      );
      final noDate1 = makeTodo(
        id: 'nd1',
        text: 'No date urgent',
        dueDate: null,
        dueTime: null,
        priority: TodoPriority.urgent,
      );
      final noDate2 = makeTodo(
        id: 'nd2',
        text: 'No date normal',
        dueDate: null,
        dueTime: null,
        priority: TodoPriority.normal,
      );
      final completed = makeTodo(
        id: 'done',
        text: 'Done task',
        dueDate: '2026-11-15',
        done: true,
      );
      final tombstoned = makeTodo(
        id: 'tomb',
        text: 'Deleted task',
        dueDate: '2026-11-15',
        deletedAt: '2026-11-15T12:00:00.000Z',
      );
      final upcoming = makeTodo(
        id: 'up',
        text: 'Tomorrow task',
        dueDate: '2026-11-17',
        priority: TodoPriority.urgent,
      );

      final items = [
        todayTimed1,
        overdue1,
        completed,
        noDate1,
        overdue2,
        upcoming,
        tombstoned,
        todayUntimed,
        overdue3,
        todayTimed2,
        noDate2,
      ];

      final briefing = DailyBriefingBuilder.build(
        items: items,
        now: fixedNow,
        period: DailyBriefingPeriod.morning,
      );

      expect(briefing.period, DailyBriefingPeriod.morning);
      expect(briefing.dateKey, '2026-11-16');
      expect(briefing.isEmpty, isFalse);

      // Overdue sorted:
      // 1. dueDate 2026-11-15, time 10:00, priority high (o3)
      // 2. dueDate 2026-11-15, time 10:00, priority normal (o1)
      // 3. dueDate 2026-11-16, time 08:00, priority urgent (o2)
      expect(briefing.overdueItems.map((e) => e.id), ['o3', 'o1', 'o2']);

      // Today commitments sorted by dueTime:
      // 1. 11:00 (t2)
      // 2. 16:00 (t1)
      expect(briefing.todayCommitments.map((e) => e.id), ['t2', 't1']);

      // Priority items sorted by priority (urgent > normal), then dueDate nulls last:
      // 1. tu (urgent, dueDate 2026-11-16)
      // 2. nd1 (urgent, dueDate null)
      // 3. nd2 (normal, dueDate null)
      expect(briefing.priorityItems.map((e) => e.id), ['tu', 'nd1', 'nd2']);

      // Excludes completed, tombstoned, and upcoming
      final allBriefingIds = [
        ...briefing.overdueItems.map((e) => e.id),
        ...briefing.todayCommitments.map((e) => e.id),
        ...briefing.priorityItems.map((e) => e.id),
      ];
      expect(allBriefingIds.contains('done'), isFalse);
      expect(allBriefingIds.contains('tomb'), isFalse);
      expect(allBriefingIds.contains('up'), isFalse);
    });

    test('strict fidelity: never omits confirmed tasks, never invents tasks',
        () {
      final task1 = makeTodo(id: '1', text: 'Task 1', dueDate: '2026-11-16');
      final task2 = makeTodo(id: '2', text: 'Task 2', dueDate: '2026-11-16');

      final briefing = DailyBriefingBuilder.build(
        items: [task1, task2],
        now: fixedNow,
        period: DailyBriefingPeriod.morning,
      );

      expect(briefing.priorityItems.length, 2);
      expect(briefing.priorityItems[0].id, '1');
      expect(briefing.priorityItems[1].id, '2');
      expect(briefing.overdueItems, isEmpty);
      expect(briefing.todayCommitments, isEmpty);
      expect(briefing.calendarCommitments, isEmpty);
    });

    test('isEmpty is true when all lists are empty', () {
      final briefing = DailyBriefingBuilder.build(
        items: const [],
        now: fixedNow,
        period: DailyBriefingPeriod.morning,
      );
      expect(briefing.isEmpty, isTrue);

      final withCalendar = DailyBriefingBuilder.build(
        items: const [],
        now: fixedNow,
        period: DailyBriefingPeriod.morning,
        calendarCommitments: [
          CalendarSlot(
            start: DateTime.utc(2026, 11, 16, 14, 0),
            end: DateTime.utc(2026, 11, 16, 15, 0),
            allDay: false,
          ),
        ],
      );
      expect(withCalendar.isEmpty, isFalse);
    });
  });

  group('DailyBriefingBuilder.activePeriodFor', () {
    final settings = ActiveAssistantSettings(
      morningBriefingMinutes: 540, // 09:00
      afternoonBriefingMinutes: 840, // 14:00
      quietHoursStartMinutes: 1320, // 22:00
      quietHoursEndMinutes: 480, // 08:00
    );

    test('returns null during quiet hours or before morning trigger', () {
      // 07:00 local = 10:00 UTC (quiet hours)
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 10, 0),
          settings: settings,
        ),
        isNull,
      );

      // 08:30 local = 11:30 UTC (outside quiet hours, before 09:00)
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 11, 30),
          settings: settings,
        ),
        isNull,
      );
    });

    test('returns morning after morning trigger and before afternoon trigger',
        () {
      // 09:00 local = 12:00 UTC
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 12, 0),
          settings: settings,
        ),
        DailyBriefingPeriod.morning,
      );

      // 13:59 local = 16:59 UTC
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 16, 59),
          settings: settings,
        ),
        DailyBriefingPeriod.morning,
      );
    });

    test('returns afternoon after afternoon trigger', () {
      // 14:00 local = 17:00 UTC
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 17, 0),
          settings: settings,
        ),
        DailyBriefingPeriod.afternoon,
      );

      // 21:59 local = 2026-11-17 00:59 UTC (before quiet hours)
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 17, 0, 59),
          settings: settings,
        ),
        DailyBriefingPeriod.afternoon,
      );

      // 22:00 local = 2026-11-17 01:00 UTC (enters quiet hours)
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 17, 1, 0),
          settings: settings,
        ),
        isNull,
      );
    });

    test('returns null when silencedUntilIso is active', () {
      final silencedSettings = settings.copyWith(
        silencedUntilIso: DateTime.utc(2026, 11, 16, 15, 0).toIso8601String(),
      );

      // 10:00 local = 13:00 UTC (silenced until 15:00 UTC)
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 13, 0),
          settings: silencedSettings,
        ),
        isNull,
      );
    });

    test('handles single enabled period', () {
      final afternoonOnly = settings.copyWith(
        morningBriefingEnabled: false,
        afternoonBriefingEnabled: true,
      );

      // 10:00 local (after morning, before afternoon) -> null because morning is disabled
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 13, 0),
          settings: afternoonOnly,
        ),
        isNull,
      );

      // 15:00 local -> afternoon
      expect(
        DailyBriefingBuilder.activePeriodFor(
          now: DateTime.utc(2026, 11, 16, 18, 0),
          settings: afternoonOnly,
        ),
        DailyBriefingPeriod.afternoon,
      );
    });
  });

  group('DailyBriefingBuilder.nextScheduledBriefingTime', () {
    final settings = ActiveAssistantSettings(
      morningBriefingMinutes: 540, // 09:00
      afternoonBriefingMinutes: 840, // 14:00
      quietHoursStartMinutes: 1320, // 22:00
      quietHoursEndMinutes: 480, // 08:00
    );

    test('picks next trigger today when available', () {
      // 08:00 local = 11:00 UTC
      final nextMorning = DailyBriefingBuilder.nextScheduledBriefingTime(
        now: DateTime.utc(2026, 11, 16, 11, 0),
        settings: settings,
      );
      expect(nextMorning, isNotNull);
      // Sao Paulo 09:00 = 12:00 UTC
      expect(nextMorning!.toUtc(), DateTime.utc(2026, 11, 16, 12, 0));

      // 10:00 local = 13:00 UTC
      final nextAfternoon = DailyBriefingBuilder.nextScheduledBriefingTime(
        now: DateTime.utc(2026, 11, 16, 13, 0),
        settings: settings,
      );
      expect(nextAfternoon, isNotNull);
      // Sao Paulo 14:00 = 17:00 UTC
      expect(nextAfternoon!.toUtc(), DateTime.utc(2026, 11, 16, 17, 0));
    });

    test('rolls over to next day when all triggers today have passed', () {
      // 15:00 local = 18:00 UTC
      final next = DailyBriefingBuilder.nextScheduledBriefingTime(
        now: DateTime.utc(2026, 11, 16, 18, 0),
        settings: settings,
      );
      expect(next, isNotNull);
      // Next is tomorrow 09:00 local = 12:00 UTC on 2026-11-17
      expect(next!.toUtc(), DateTime.utc(2026, 11, 17, 12, 0));
    });

    test('skips triggers that fall within quiet hours', () {
      // morning briefing at 07:00 (420), but quiet hours end at 08:00 (480)
      final earlyMorningSettings = settings.copyWith(
        morningBriefingMinutes: 420, // 07:00 (inside quiet hours)
      );

      // At 06:00 local = 09:00 UTC
      final next = DailyBriefingBuilder.nextScheduledBriefingTime(
        now: DateTime.utc(2026, 11, 16, 9, 0),
        settings: earlyMorningSettings,
      );
      expect(next, isNotNull);
      // 07:00 was skipped because of quiet hours, so next is 14:00 (17:00 UTC)
      expect(next!.toUtc(), DateTime.utc(2026, 11, 16, 17, 0));
    });

    test('returns null when both periods are disabled', () {
      final disabled = settings.copyWith(
        morningBriefingEnabled: false,
        afternoonBriefingEnabled: false,
      );

      final next = DailyBriefingBuilder.nextScheduledBriefingTime(
        now: DateTime.utc(2026, 11, 16, 11, 0),
        settings: disabled,
      );
      expect(next, isNull);
    });
  });
}
