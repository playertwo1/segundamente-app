import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/stalled_task_detector.dart';

void main() {
  group('StalledTaskDetector', () {
    // 2026-11-16 13:00 UTC = 2026-11-16 10:00 in America/Sao_Paulo (UTC-3)
    final fixedNow = DateTime.utc(2026, 11, 16, 13, 0);

    TodoItem buildItem({
      required String id,
      String? dueDate,
      String? dueTime,
      bool done = false,
      String? deletedAt,
      TodoPriority priority = TodoPriority.normal,
      String createdAt = '2026-11-10T12:00:00.000Z',
      String timeZone = todoTimeZone,
    }) {
      return TodoItem(
        id: id,
        text: 'Task $id',
        due: dueDate ?? 'sem data',
        dueDate: dueDate,
        dueTime: dueTime,
        done: done,
        deletedAt: deletedAt,
        priority: priority,
        createdAt: createdAt,
        timeZone: timeZone,
      );
    }

    test('detects dated overdue tasks with configurable threshold', () {
      final items = [
        buildItem(id: '3days_overdue', dueDate: '2026-11-13'),
        buildItem(id: '2days_overdue', dueDate: '2026-11-14'),
        buildItem(id: '5days_overdue', dueDate: '2026-11-11'),
        buildItem(id: 'future', dueDate: '2026-11-17'),
        buildItem(id: 'today', dueDate: '2026-11-16'),
      ];

      // Threshold = 3 days (default)
      final settings3 = ActiveAssistantSettings(stalledThresholdDays: 3);
      final nudges3 = StalledTaskDetector.detect(
        items: items,
        now: fixedNow,
        settings: settings3,
      );

      expect(nudges3.map((n) => n.item.id).toList(), [
        '5days_overdue',
        '3days_overdue',
      ]);
      expect(nudges3[0].stalledDays, 5);
      expect(nudges3[0].isOverdueStalled, isTrue);
      expect(nudges3[1].stalledDays, 3);
      expect(nudges3[1].isOverdueStalled, isTrue);

      // Threshold = 5 days
      final settings5 = ActiveAssistantSettings(stalledThresholdDays: 5);
      final nudges5 = StalledTaskDetector.detect(
        items: items,
        now: fixedNow,
        settings: settings5,
      );

      expect(nudges5.map((n) => n.item.id).toList(), ['5days_overdue']);
      expect(nudges5[0].stalledDays, 5);
      expect(nudges5[0].isOverdueStalled, isTrue);
    });

    test('detects undated tasks stalled since createdAt', () {
      final items = [
        // Created 2026-11-13 10:00 local -> 3 days stalled on 2026-11-16
        buildItem(
          id: 'undated_3days',
          createdAt: '2026-11-13T13:00:00.000Z',
        ),
        // Created 2026-11-14 10:00 local -> 2 days stalled
        buildItem(
          id: 'undated_2days',
          createdAt: '2026-11-14T13:00:00.000Z',
        ),
      ];

      final settings = ActiveAssistantSettings(stalledThresholdDays: 3);
      final nudges = StalledTaskDetector.detect(
        items: items,
        now: fixedNow,
        settings: settings,
      );

      expect(nudges.length, 1);
      expect(nudges.first.item.id, 'undated_3days');
      expect(nudges.first.stalledDays, 3);
      expect(nudges.first.isOverdueStalled, isFalse);
    });

    test('respects local timezone boundary for undated task createdAt', () {
      // 2026-11-13 01:30 UTC:
      // In UTC, date is 2026-11-13 (difference to 2026-11-16 is 3 days).
      // In America/Sao_Paulo (UTC-3), local time is 2026-11-12 22:30 (date is 2026-11-12).
      // Difference to local today (2026-11-16) is 4 days!
      final item = buildItem(
        id: 'tz_task',
        createdAt: '2026-11-13T01:30:00.000Z',
        timeZone: 'America/Sao_Paulo',
      );

      final settings = ActiveAssistantSettings(stalledThresholdDays: 4);
      final nudges = StalledTaskDetector.detect(
        items: [item],
        now: fixedNow,
        settings: settings,
      );

      expect(nudges.length, 1);
      expect(nudges.first.stalledDays, 4);
      expect(nudges.first.isOverdueStalled, isFalse);
    });

    test('ignores done and isTombstoned items', () {
      final items = [
        buildItem(
          id: 'done_item',
          dueDate: '2026-11-01',
          done: true,
        ),
        buildItem(
          id: 'tombstoned_item',
          dueDate: '2026-11-01',
          deletedAt: '2026-11-10T12:00:00.000Z',
        ),
        buildItem(
          id: 'active_item',
          dueDate: '2026-11-01',
        ),
      ];

      final nudges = StalledTaskDetector.detect(
        items: items,
        now: fixedNow,
        settings: ActiveAssistantSettings.defaults,
      );

      expect(nudges.map((n) => n.item.id).toList(), ['active_item']);
    });

    test('returns empty when stalled reminders disabled or silenced', () {
      final items = [
        buildItem(id: 'stalled_1', dueDate: '2026-11-01'),
      ];

      // 1. Feature disabled
      final disabledSettings =
          ActiveAssistantSettings.defaults.copyWith(stalledReminderEnabled: false);
      expect(
        StalledTaskDetector.detect(
          items: items,
          now: fixedNow,
          settings: disabledSettings,
        ),
        isEmpty,
      );

      // 2. Silenced until future
      final silencedSettings = ActiveAssistantSettings.defaults.copyWith(
        silencedUntilIso: '2026-11-16T15:00:00.000Z',
      );
      expect(
        StalledTaskDetector.detect(
          items: items,
          now: fixedNow,
          settings: silencedSettings,
        ),
        isEmpty,
      );

      // 3. During quiet hours (clock is 10:00 local = 600 minutes)
      final quietSettings = ActiveAssistantSettings(
        quietHoursEnabled: true,
        quietHoursStartMinutes: 540, // 09:00
        quietHoursEndMinutes: 660, // 11:00
      );
      expect(
        StalledTaskDetector.detect(
          items: items,
          now: fixedNow,
          settings: quietSettings,
        ),
        isEmpty,
      );
    });

    test('respects per-task snooze and leaves items list intact', () {
      final itemA = buildItem(id: 'task_a', dueDate: '2026-11-10');
      final itemB = buildItem(id: 'task_b', dueDate: '2026-11-10');
      final items = [itemA, itemB];

      final snoozeMap = {
        'task_a': '2026-11-17T10:00:00.000Z', // Active future snooze
        'task_b': '2026-11-15T10:00:00.000Z', // Expired snooze
      };

      final nudges = StalledTaskDetector.detect(
        items: items,
        now: fixedNow,
        settings: ActiveAssistantSettings.defaults,
        snoozedUntilByTaskId: snoozeMap,
      );

      expect(nudges.length, 1);
      expect(nudges.first.item.id, 'task_b');

      // Verify original items list and objects remain completely unchanged
      expect(items.length, 2);
      expect(items[0], same(itemA));
      expect(items[1], same(itemB));
      expect(items[0].done, isFalse);
    });

    test('sorts by highest stalledDays, then priority, then oldest createdAt', () {
      final items = [
        // 3 days stalled, normal priority, older createdAt
        buildItem(
          id: 'item_3d_normal_older',
          dueDate: '2026-11-13',
          priority: TodoPriority.normal,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
        // 5 days stalled, low priority
        buildItem(
          id: 'item_5d_low',
          dueDate: '2026-11-11',
          priority: TodoPriority.low,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
        // 3 days stalled, urgent priority
        buildItem(
          id: 'item_3d_urgent',
          dueDate: '2026-11-13',
          priority: TodoPriority.urgent,
          createdAt: '2026-11-02T10:00:00.000Z',
        ),
        // 3 days stalled, normal priority, newer createdAt
        buildItem(
          id: 'item_3d_normal_newer',
          dueDate: '2026-11-13',
          priority: TodoPriority.normal,
          createdAt: '2026-11-03T10:00:00.000Z',
        ),
        // 5 days stalled, high priority
        buildItem(
          id: 'item_5d_high',
          dueDate: '2026-11-11',
          priority: TodoPriority.high,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];

      final nudges = StalledTaskDetector.detect(
        items: items,
        now: fixedNow,
        settings: ActiveAssistantSettings.defaults,
      );

      final ids = nudges.map((n) => n.item.id).toList();
      expect(ids, [
        'item_5d_high', // 5 days, priority high
        'item_5d_low', // 5 days, priority low
        'item_3d_urgent', // 3 days, priority urgent
        'item_3d_normal_older', // 3 days, priority normal, createdAt Nov 01
        'item_3d_normal_newer', // 3 days, priority normal, createdAt Nov 03
      ]);
    });
  });
}
