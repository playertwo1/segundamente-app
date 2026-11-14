import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';

const todoSchemaVersion = 2;
const todoTimeZone = 'America/Sao_Paulo';
const todoAlarmSnoozeMinutes = 10;

enum TodoPriority { low, normal, high, urgent }

enum TodoRepeatFrequency { daily, weekly, monthly }

class TodoSubtask {
  const TodoSubtask({
    required this.id,
    required this.text,
    this.done = false,
  });

  final String id;
  final String text;
  final bool done;

  TodoSubtask copyWith({String? text, bool? done}) => TodoSubtask(
        id: id,
        text: text ?? this.text,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};

  static TodoSubtask fromJson(Map<String, dynamic> json) => TodoSubtask(
        id: _text(json['id']),
        text: _text(json['text']),
        done: json['done'] == true,
      );
}

class TodoRecurrence {
  TodoRecurrence.daily()
      : frequency = TodoRepeatFrequency.daily,
        weekdays = const [],
        dayOfMonth = null;

  TodoRecurrence.weekly(Iterable<int> selectedDays)
      : frequency = TodoRepeatFrequency.weekly,
        weekdays = List.unmodifiable(selectedDays.toSet().toList()..sort()),
        dayOfMonth = null {
    if (weekdays.isEmpty || weekdays.any((day) => day < 1 || day > 7)) {
      throw ArgumentError.value(selectedDays, 'selectedDays');
    }
  }

  TodoRecurrence.monthly(int day)
      : frequency = TodoRepeatFrequency.monthly,
        weekdays = const [],
        dayOfMonth = day {
    if (day < 1 || day > 31) {
      throw ArgumentError.value(day, 'dayOfMonth');
    }
  }

  final TodoRepeatFrequency frequency;
  final List<int> weekdays;
  final int? dayOfMonth;

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        if (weekdays.isNotEmpty) 'weekdays': weekdays,
        if (dayOfMonth != null) 'day_of_month': dayOfMonth,
      };

  static TodoRecurrence fromJson(Map<String, dynamic> json) {
    final frequency = TodoRepeatFrequency.values.firstWhere(
      (value) => value.name == json['frequency'],
      orElse: () => throw const FormatException('unknown Todo recurrence'),
    );
    switch (frequency) {
      case TodoRepeatFrequency.daily:
        return TodoRecurrence.daily();
      case TodoRepeatFrequency.weekly:
        final days = json['weekdays'];
        if (days is! List) {
          throw const FormatException('weekly Todo recurrence has no days');
        }
        return TodoRecurrence.weekly(days.map((day) => (day as num).toInt()));
      case TodoRepeatFrequency.monthly:
        final day = json['day_of_month'];
        if (day is! num) {
          throw const FormatException('monthly Todo recurrence has no day');
        }
        return TodoRecurrence.monthly(day.toInt());
    }
  }
}

/// Where a Todo item came from; null for an item typed by hand.
class TodoSource {
  const TodoSource({
    required this.sessionId,
    required this.itemId,
    required this.excerpt,
    this.clock,
  });

  final String sessionId;
  final String itemId;
  final String excerpt;
  final String? clock;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'item_id': itemId,
        'excerpt': excerpt,
        'clock': clock,
      };

  static TodoSource fromJson(Map<String, dynamic> json) => TodoSource(
        sessionId: _text(json['session_id']),
        itemId: _text(json['item_id']),
        excerpt: _text(json['excerpt']),
        clock: json['clock']?.toString(),
      );
}

class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    required this.due,
    required this.done,
    required this.createdAt,
    this.dueDate,
    this.dueTime,
    this.timeZone = todoTimeZone,
    this.alertMinutes = 20,
    this.priority = TodoPriority.normal,
    this.subtasks = const [],
    this.recurrence,
    this.seriesId,
    this.doneAt,
    this.snoozedUntil,
    this.source,
    this.sourceStale = false,
    this.version = 1,
    this.deletedAt,
  });

  final String id;
  final String text;

  /// Original text is retained when a legacy deadline is ambiguous.
  final String due;
  final String? dueDate;
  final String? dueTime;
  final String timeZone;
  final int alertMinutes;
  final TodoPriority priority;
  final List<TodoSubtask> subtasks;
  final TodoRecurrence? recurrence;
  final String? seriesId;
  final bool done;
  final String createdAt;
  final String? doneAt;
  final String? snoozedUntil;
  final TodoSource? source;
  final bool sourceStale;
  final int version;
  final String? deletedAt;

  bool get isTombstoned => deletedAt != null;
  bool get hasAlarmTime => dueDate != null && dueTime != null;

  TodoItem copyWith({
    String? text,
    String? due,
    String? dueDate,
    String? dueTime,
    String? timeZone,
    int? alertMinutes,
    TodoPriority? priority,
    List<TodoSubtask>? subtasks,
    TodoRecurrence? recurrence,
    bool clearRecurrence = false,
    String? seriesId,
    bool? done,
    String? doneAt,
    String? snoozedUntil,
    bool clearDoneAt = false,
    bool clearSnoozedUntil = false,
    bool? sourceStale,
    bool clearSource = false,
    int? version,
    String? deletedAt,
    bool clearDeletedAt = false,
    bool clearDueDate = false,
    bool clearDueTime = false,
  }) {
    final nextDone = done ?? this.done;
    final nextSource = clearSource ? null : source;
    return TodoItem(
      id: id,
      text: text ?? this.text,
      due: due ?? this.due,
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      dueTime: clearDueTime ? null : dueTime ?? this.dueTime,
      timeZone: timeZone ?? this.timeZone,
      alertMinutes: alertMinutes ?? this.alertMinutes,
      priority: priority ?? this.priority,
      subtasks: subtasks ?? this.subtasks,
      recurrence: clearRecurrence ? null : recurrence ?? this.recurrence,
      seriesId: seriesId ?? this.seriesId,
      done: nextDone,
      createdAt: createdAt,
      doneAt: clearDoneAt || !nextDone ? null : doneAt ?? this.doneAt,
      snoozedUntil:
          clearSnoozedUntil ? null : snoozedUntil ?? this.snoozedUntil,
      source: nextSource,
      sourceStale: nextSource == null ? false : sourceStale ?? this.sourceStale,
      version: version ?? this.version,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'due': due,
        'due_date': dueDate,
        'due_time': dueTime,
        'time_zone': timeZone,
        'alert_minutes': alertMinutes,
        'priority': priority.name,
        'subtasks': [for (final subtask in subtasks) subtask.toJson()],
        'recurrence': recurrence?.toJson(),
        'series_id': seriesId,
        'done': done,
        'created_at': createdAt,
        'done_at': doneAt,
        'snoozed_until': snoozedUntil,
        if (source != null) 'source': source!.toJson(),
        if (sourceStale) 'source_stale': true,
        'version': version,
        'deleted_at': deletedAt,
      };

  static TodoItem fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    final rawDue = json['due']?.toString().trim() ?? '';
    final due = rawDue.isEmpty ? reportDueUnknown : rawDue;
    final explicit = parseExplicitDue(due);
    final rawSubtasks = json['subtasks'];
    final rawRecurrence = json['recurrence'];
    final rawPriority = json['priority']?.toString();
    return TodoItem(
      id: _text(json['id']),
      text: _text(json['text']),
      due: due,
      dueDate: _optionalText(json['due_date']) ??
          (explicit == null ? null : _dateOnly(explicit.date)),
      dueTime: _optionalText(json['due_time']) ??
          (explicit?.hasTime == true ? _timeOnly(explicit!.date) : null),
      timeZone: _optionalText(json['time_zone']) ?? todoTimeZone,
      alertMinutes: (json['alert_minutes'] as num?)?.toInt() ?? 20,
      priority: TodoPriority.values.firstWhere(
        (value) => value.name == rawPriority,
        orElse: () => TodoPriority.normal,
      ),
      subtasks: rawSubtasks is List
          ? [
              for (final item in rawSubtasks)
                TodoSubtask.fromJson((item as Map).cast<String, dynamic>()),
            ]
          : const [],
      recurrence: rawRecurrence is Map
          ? TodoRecurrence.fromJson(rawRecurrence.cast<String, dynamic>())
          : null,
      seriesId: _optionalText(json['series_id']),
      done: json['done'] == true,
      createdAt: _text(json['created_at']),
      doneAt: _optionalText(json['done_at']),
      snoozedUntil: _optionalText(json['snoozed_until']),
      source: source is Map ? TodoSource.fromJson(source.cast()) : null,
      sourceStale: source is Map && json['source_stale'] == true,
      version: (json['version'] as num?)?.toInt() ?? 1,
      deletedAt: _optionalText(json['deleted_at']),
    );
  }
}

String _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) throw const FormatException('todo field is empty');
  return text;
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _dateOnly(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _timeOnly(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

/// Open items first, then done ones; each group keeps creation order.
List<TodoItem> sortTodos(List<TodoItem> items) {
  final sorted = [...items];
  sorted.sort((a, b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    return a.createdAt.compareTo(b.createdAt);
  });
  return sorted;
}

// shortcut: plain accent-blind substring match over text, due and quote;
// no ranking. Add it to the semantic index only if the list gets long.
List<TodoItem> searchTodos(List<TodoItem> items, String query) {
  final needle = _fold(query);
  if (needle.isEmpty) return items;
  return [
    for (final item in items)
      if (_fold(
        '${item.text} ${item.due} ${item.source?.excerpt ?? ''} '
        '${item.subtasks.map((subtask) => subtask.text).join(' ')}',
      ).contains(needle))
        item,
  ];
}

String _fold(String value) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final buffer = StringBuffer();
  for (final ch in value.toLowerCase().trim().split('')) {
    final at = from.indexOf(ch);
    buffer.write(at >= 0 ? to[at] : ch);
  }
  return buffer.toString();
}
