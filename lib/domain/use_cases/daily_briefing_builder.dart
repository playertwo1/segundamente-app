import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

enum DailyBriefingPeriod { morning, afternoon }

class DailyBriefing {
  const DailyBriefing({
    required this.period,
    required this.dateKey,
    this.overdueItems = const [],
    this.todayCommitments = const [],
    this.priorityItems = const [],
    this.calendarCommitments = const [],
  });

  final DailyBriefingPeriod period;
  final String dateKey;
  final List<TodoItem> overdueItems;
  List<TodoItem> get overdueTasks => overdueItems;
  final List<TodoItem> todayCommitments;
  final List<TodoItem> priorityItems;
  List<TodoItem> get priorityTasks => priorityItems;
  final List<CalendarSlot> calendarCommitments;

  bool get isEmpty =>
      overdueItems.isEmpty &&
      todayCommitments.isEmpty &&
      priorityItems.isEmpty &&
      calendarCommitments.isEmpty;
}

class DailyBriefingBuilder {
  DailyBriefingBuilder._();

  static bool _timeZonesInitialized = false;

  static tz.Location _location(String name) {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      return tz.getLocation(todoTimeZone);
    }
  }

  static DailyBriefing build({
    required List<TodoItem> items,
    required DateTime now,
    required DailyBriefingPeriod period,
    String timeZone = todoTimeZone,
    List<CalendarSlot> calendarCommitments = const [],
  }) {
    final location = _location(timeZone);
    final localNow = tz.TZDateTime.from(now, location);
    final dateKey = '${localNow.year.toString().padLeft(4, '0')}-'
        '${localNow.month.toString().padLeft(2, '0')}-'
        '${localNow.day.toString().padLeft(2, '0')}';

    final activeItems = items.where((item) => !item.done && !item.isTombstoned);

    final overdue = <TodoItem>[];
    final today = <TodoItem>[];
    final priority = <TodoItem>[];

    for (final item in activeItems) {
      final status = TodoScheduleCalculator.statusFor(
        dueDate: item.dueDate,
        now: now,
        timeZone: timeZone,
        dueTime: item.dueTime,
      );

      if (status == TodoDateStatus.overdue) {
        overdue.add(item);
      } else if (status == TodoDateStatus.today && item.dueTime != null) {
        today.add(item);
      } else if ((status == TodoDateStatus.today && item.dueTime == null) ||
          status == TodoDateStatus.noDate) {
        priority.add(item);
      }
    }

    overdue.sort((a, b) {
      final aDue = a.dueDate ?? '9999-99-99';
      final bDue = b.dueDate ?? '9999-99-99';
      final dateCmp = aDue.compareTo(bDue);
      if (dateCmp != 0) return dateCmp;

      final aTime = a.dueTime ?? '99:99';
      final bTime = b.dueTime ?? '99:99';
      final timeCmp = aTime.compareTo(bTime);
      if (timeCmp != 0) return timeCmp;

      final priorityCmp = b.priority.index.compareTo(a.priority.index);
      if (priorityCmp != 0) return priorityCmp;

      return a.createdAt.compareTo(b.createdAt);
    });

    today.sort((a, b) {
      final aTime = a.dueTime ?? '99:99';
      final bTime = b.dueTime ?? '99:99';
      final timeCmp = aTime.compareTo(bTime);
      if (timeCmp != 0) return timeCmp;

      final priorityCmp = b.priority.index.compareTo(a.priority.index);
      if (priorityCmp != 0) return priorityCmp;

      return a.createdAt.compareTo(b.createdAt);
    });

    priority.sort((a, b) {
      final priorityCmp = b.priority.index.compareTo(a.priority.index);
      if (priorityCmp != 0) return priorityCmp;

      final aDue = a.dueDate ?? '9999-99-99';
      final bDue = b.dueDate ?? '9999-99-99';
      final dateCmp = aDue.compareTo(bDue);
      if (dateCmp != 0) return dateCmp;

      return a.createdAt.compareTo(b.createdAt);
    });

    return DailyBriefing(
      period: period,
      dateKey: dateKey,
      overdueItems: List.unmodifiable(overdue),
      todayCommitments: List.unmodifiable(today),
      priorityItems: List.unmodifiable(priority),
      calendarCommitments: List.unmodifiable(calendarCommitments),
    );
  }

  static DailyBriefingPeriod? activePeriodFor({
    required DateTime now,
    required ActiveAssistantSettings settings,
    String timeZone = todoTimeZone,
  }) {
    if (settings.isSilencedAt(now, timeZone: timeZone)) {
      return null;
    }

    final local = tz.TZDateTime.from(now, _location(timeZone));
    final localMinutes = local.hour * 60 + local.minute;

    if (settings.morningBriefingEnabled &&
        settings.afternoonBriefingEnabled &&
        settings.morningBriefingMinutes <= settings.afternoonBriefingMinutes) {
      if (localMinutes >= settings.afternoonBriefingMinutes) {
        return DailyBriefingPeriod.afternoon;
      }
      if (localMinutes >= settings.morningBriefingMinutes) {
        return DailyBriefingPeriod.morning;
      }
      return null;
    }

    final candidates = <({DailyBriefingPeriod period, int minutes})>[];
    if (settings.morningBriefingEnabled) {
      candidates.add((
        period: DailyBriefingPeriod.morning,
        minutes: settings.morningBriefingMinutes,
      ));
    }
    if (settings.afternoonBriefingEnabled) {
      candidates.add((
        period: DailyBriefingPeriod.afternoon,
        minutes: settings.afternoonBriefingMinutes,
      ));
    }

    candidates.sort((a, b) => a.minutes.compareTo(b.minutes));
    final arrived = candidates.where((c) => c.minutes <= localMinutes);
    if (arrived.isEmpty) return null;
    return arrived.last.period;
  }

  static tz.TZDateTime? nextScheduledBriefingTime({
    required DateTime now,
    required ActiveAssistantSettings settings,
    String timeZone = todoTimeZone,
  }) {
    final location = _location(timeZone);
    final localNow = tz.TZDateTime.from(now, location);
    final candidates = <tz.TZDateTime>[];

    for (var dayOffset = 0; dayOffset <= 7; dayOffset++) {
      if (settings.morningBriefingEnabled) {
        final hour = settings.morningBriefingMinutes ~/ 60;
        final minute = settings.morningBriefingMinutes % 60;
        candidates.add(tz.TZDateTime(
          location,
          localNow.year,
          localNow.month,
          localNow.day + dayOffset,
          hour,
          minute,
        ));
      }
      if (settings.afternoonBriefingEnabled) {
        final hour = settings.afternoonBriefingMinutes ~/ 60;
        final minute = settings.afternoonBriefingMinutes % 60;
        candidates.add(tz.TZDateTime(
          location,
          localNow.year,
          localNow.month,
          localNow.day + dayOffset,
          hour,
          minute,
        ));
      }
    }

    candidates.sort((a, b) => a.compareTo(b));

    for (final candidate in candidates) {
      if (candidate.isAfter(now) &&
          !settings.isSilencedAt(candidate, timeZone: timeZone)) {
        return candidate;
      }
    }
    return null;
  }
}
