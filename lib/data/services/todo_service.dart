import 'dart:convert';
import 'dart:io';

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_alarm_service.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/utils/logger.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

/// Local Todo storage and the compatibility bridge used by session reports.
class TodoService {
  TodoService({FileSystemService? fileService}) : _fileService = fileService;

  static final Lock _storageLock = Lock();

  final FileSystemService? _fileService;
  FileSystemService get _files => _fileService ?? FileSystemService.instance;
  final _logger = getLogger('TodoService');
  final _uuid = const Uuid();

  Future<List<TodoItem>> load(
    String userId, {
    bool includeDeleted = false,
  }) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        return [
          for (final item in items)
            if (includeDeleted || !item.isTombstoned) item,
        ];
      });

  Future<TodoItem> add({
    required String userId,
    required String text,
    String? id,
    String? due,
    String? dueDate,
    String? dueTime,
    String timeZone = todoTimeZone,
    int alertMinutes = 20,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    TodoRecurrence? recurrence,
    TodoSource? source,
    DateTime? now,
  }) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        if (id != null) {
          final existing = items.where((item) => item.id == id);
          if (existing.isNotEmpty) return existing.first;
        }
        return _addUnlocked(
          userId: userId,
          items: items,
          id: id,
          text: text,
          due: due,
          dueDate: dueDate,
          dueTime: dueTime,
          timeZone: timeZone,
          alertMinutes: alertMinutes,
          priority: priority,
          subtasks: subtasks,
          recurrence: recurrence,
          source: source,
          now: now,
        );
      });

  /// Copies an approved report task once, keeping its source link intact.
  Future<TodoItem> addFromReport({
    required String userId,
    required String sessionId,
    required ReportItem item,
    DateTime? now,
  }) =>
      _storageLock.synchronized(() async {
        if (item.kind != ReportItemKind.task ||
            item.status != ReportItemStatus.approved) {
          throw StateError('only an approved task can go to the Todo list');
        }
        final items = await _readAll(userId);
        final existingIndex = items.indexWhere((todo) =>
            todo.source?.sessionId == sessionId &&
            todo.source?.itemId == item.id);
        if (existingIndex >= 0) {
          final existing = items[existingIndex];
          if (!existing.isTombstoned) return existing;
          final restored = existing.copyWith(
            clearDeletedAt: true,
            version: existing.version + 1,
          );
          items[existingIndex] = restored;
          await _write(userId, items);
          return restored;
        }
        return _addUnlocked(
          userId: userId,
          items: items,
          text: item.text,
          due: item.due,
          now: now,
          source: TodoSource(
            sessionId: sessionId,
            itemId: item.id,
            excerpt: item.source.excerpt,
            clock: item.source.clock,
          ),
        );
      });

  Future<void> edit({
    required String userId,
    required String id,
    required String text,
    required String due,
    String? dueDate,
    String? dueTime,
    String? timeZone,
    int? alertMinutes,
    TodoPriority? priority,
    List<TodoSubtask>? subtasks,
    TodoRecurrence? recurrence,
    bool clearRecurrence = false,
  }) async {
    if (text.trim().isEmpty) throw ArgumentError('todo text is empty');
    final schedule = _schedule(due, dueDate: dueDate, dueTime: dueTime);
    if (alertMinutes != null && alertMinutes < 0) {
      throw ArgumentError.value(alertMinutes, 'alertMinutes');
    }
    await _change(userId, id, (item) {
      final nextRecurrence =
          clearRecurrence ? null : recurrence ?? item.recurrence;
      if (nextRecurrence != null && schedule.date == null) {
        throw ArgumentError('a recurring Todo needs a due date');
      }
      return item.copyWith(
        text: text.trim(),
        due: schedule.label,
        dueDate: schedule.date,
        dueTime: schedule.time,
        clearDueDate: schedule.date == null,
        clearDueTime: schedule.time == null,
        timeZone: timeZone,
        alertMinutes: alertMinutes,
        priority: priority,
        subtasks: subtasks,
        recurrence: nextRecurrence,
        clearRecurrence: clearRecurrence,
        clearSnoozedUntil: true,
        seriesId: item.seriesId ?? (nextRecurrence == null ? null : item.id),
        version: item.version + 1,
      );
    });
  }

  Future<void> setDone({
    required String userId,
    required String id,
    required bool done,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    await _storageLock.synchronized(() async {
      final items = await _readAll(userId);
      final index = items.indexWhere(
        (item) => item.id == id && !item.isTombstoned,
      );
      if (index < 0) throw StateError('todo item not found: $id');
      final item = items[index];
      if (item.done == done) return;
      items[index] = item.copyWith(
        done: done,
        doneAt: done ? moment.toIso8601String() : null,
        clearDoneAt: !done,
        clearSnoozedUntil: true,
        version: item.version + 1,
      );
      if (done && item.recurrence != null) {
        final dueDate = item.dueDate;
        if (dueDate == null) {
          throw StateError('a recurring Todo has no due date: $id');
        }
        final seriesId = item.seriesId ?? item.id;
        final hasActiveSuccessor = items.any((candidate) =>
            candidate.id != item.id &&
            candidate.seriesId == seriesId &&
            !candidate.done &&
            !candidate.isTombstoned);
        if (!hasActiveSuccessor) {
          final nextDate = TodoScheduleCalculator.nextUpcomingOccurrenceDate(
            recurrence: item.recurrence!,
            afterDate: DateTime.parse(dueDate),
            now: moment,
            timeZone: item.timeZone,
            dueTime: item.dueTime,
          );
          final schedule = _schedule(
            item.due,
            dueDate: _dateOnly(nextDate),
            dueTime: item.dueTime,
          );
          items.add(TodoItem(
            id: _uuid.v4(),
            text: item.text,
            due: schedule.label,
            dueDate: schedule.date,
            dueTime: schedule.time,
            timeZone: item.timeZone,
            alertMinutes: item.alertMinutes,
            priority: item.priority,
            subtasks: [
              for (final subtask in item.subtasks)
                TodoSubtask(id: _uuid.v4(), text: subtask.text),
            ],
            recurrence: item.recurrence,
            seriesId: seriesId,
            done: false,
            createdAt: moment.toIso8601String(),
            source: item.source,
            sourceStale: item.sourceStale,
          ));
        }
      }
      await _write(userId, items);
    });
  }

  Future<void> remove({required String userId, required String id}) async {
    final moment = DateTime.now().toIso8601String();
    await _change(
        userId,
        id,
        (item) => item.copyWith(
              deletedAt: moment,
              version: item.version + 1,
            ));
  }

  Future<void> snooze({
    required String userId,
    required String id,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    await _change(userId, id, (item) {
      if (!item.hasAlarmTime) {
        throw StateError('only a timed Todo alarm can be snoozed: $id');
      }
      return item.copyWith(
        snoozedUntil: moment
            .toUtc()
            .add(const Duration(minutes: todoAlarmSnoozeMinutes))
            .toIso8601String(),
        version: item.version + 1,
      );
    });
  }

  Future<void> restore({required String userId, required String id}) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        final index = items.indexWhere((item) => item.id == id);
        if (index < 0) throw StateError('todo item not found: $id');
        final item = items[index];
        if (!item.isTombstoned) return;
        items[index] = item.copyWith(
          clearDeletedAt: true,
          clearSnoozedUntil: true,
          version: item.version + 1,
        );
        await _write(userId, items);
      });

  /// Deleting a session tombstones its open copies and detaches completed ones.
  Future<void> deleteForSession({
    required String userId,
    required String sessionId,
  }) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        var changed = false;
        final now = DateTime.now().toIso8601String();
        final kept = [
          for (final item in items)
            if (item.source?.sessionId != sessionId || item.isTombstoned)
              item
            else if (item.done)
              item.copyWith(clearSource: true, version: item.version + 1)
            else
              item.copyWith(deletedAt: now, version: item.version + 1),
        ];
        changed = kept
            .asMap()
            .entries
            .any((entry) => !identical(entry.value, items[entry.key]));
        if (changed) await _write(userId, kept);
      });

  Future<void> markReportItemStale({
    required String userId,
    required String sessionId,
    required String itemId,
  }) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        var changed = false;
        final updated = [
          for (final item in items)
            if (item.source?.sessionId == sessionId &&
                item.source?.itemId == itemId &&
                !item.sourceStale &&
                !item.isTombstoned)
              item.copyWith(sourceStale: true, version: item.version + 1)
            else
              item,
        ];
        changed = updated
            .asMap()
            .entries
            .any((entry) => !identical(entry.value, items[entry.key]));
        if (changed) await _write(userId, updated);
      });

  Future<void> _change(
    String userId,
    String id,
    TodoItem Function(TodoItem) change,
  ) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        final index =
            items.indexWhere((item) => item.id == id && !item.isTombstoned);
        if (index < 0) throw StateError('todo item not found: $id');
        items[index] = change(items[index]);
        await _write(userId, items);
      });

  Future<TodoItem> _addUnlocked({
    required String userId,
    required List<TodoItem> items,
    String? id,
    required String text,
    String? due,
    String? dueDate,
    String? dueTime,
    String timeZone = todoTimeZone,
    int alertMinutes = 20,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    TodoRecurrence? recurrence,
    TodoSource? source,
    DateTime? now,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('todo text is empty');
    final schedule = _schedule(due ?? '', dueDate: dueDate, dueTime: dueTime);
    if (recurrence != null && schedule.date == null) {
      throw ArgumentError('a recurring Todo needs a due date');
    }
    if (alertMinutes < 0) {
      throw ArgumentError.value(alertMinutes, 'alertMinutes');
    }
    final taskId = id ?? _uuid.v4();
    final item = TodoItem(
      id: taskId,
      text: clean,
      due: schedule.label,
      dueDate: schedule.date,
      dueTime: schedule.time,
      timeZone: timeZone,
      alertMinutes: alertMinutes,
      priority: priority,
      subtasks: subtasks,
      recurrence: recurrence,
      seriesId: recurrence == null ? null : taskId,
      done: false,
      createdAt: (now ?? DateTime.now()).toIso8601String(),
      source: source,
    );
    await _write(userId, [...items, item]);
    return item;
  }

  Future<List<TodoItem>> _readAll(String userId) async {
    final file = File(_files.getTodoV2FilePath(userId));
    if (!await file.exists()) await _migrateLegacy(userId);
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map ||
          raw['schema_version'] != todoSchemaVersion ||
          raw['items'] is! List) {
        throw const FormatException('Todo v2 file is malformed');
      }
      return [
        for (final item in raw['items'] as List)
          TodoItem.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } on FormatException catch (error, stackTrace) {
      _logger.warning('Todo storage could not be read', error, stackTrace);
      rethrow;
    } on TypeError catch (error, stackTrace) {
      _logger.warning('Todo storage could not be read', error, stackTrace);
      throw const FormatException('Todo storage could not be read');
    }
  }

  Future<void> _migrateLegacy(String userId) async {
    final legacy = File(_files.getLegacyTodoFilePath(userId));
    final current = File(_files.getTodoV2FilePath(userId));
    await current.parent.create(recursive: true);
    if (!await legacy.exists()) {
      await _write(userId, const []);
      return;
    }

    final backup = File(_files.getLegacyTodoBackupPath(userId));
    if (!await backup.exists()) await legacy.copy(backup.path);
    try {
      final raw = jsonDecode(await legacy.readAsString());
      if (raw is! Map || raw['items'] is! List) {
        throw const FormatException('legacy Todo file is malformed');
      }
      final items = [
        for (final item in raw['items'] as List)
          TodoItem.fromJson((item as Map).cast<String, dynamic>()),
      ];
      await _write(userId, items);
    } on FormatException catch (error, stackTrace) {
      _logger.warning(
        'Legacy Todo migration stopped; original and backup were retained',
        error,
        stackTrace,
      );
      throw const FormatException(
        'Legacy Todo migration failed; the original and its backup were retained',
      );
    } on TypeError catch (error, stackTrace) {
      _logger.warning(
        'Legacy Todo migration stopped; original and backup were retained',
        error,
        stackTrace,
      );
      throw const FormatException(
        'Legacy Todo migration failed; the original and its backup were retained',
      );
    }
  }

  Future<void> _write(String userId, List<TodoItem> items) async {
    final file = File(_files.getTodoV2FilePath(userId));
    await file.parent.create(recursive: true);
    final temp =
        File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schema_version': todoSchemaVersion,
          'items': [for (final item in items) item.toJson()],
        }),
        flush: true,
      );
      await temp.rename(file.path);
      await TodoAlarmService.instance.synchronize(items);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  _TodoSchedule _schedule(
    String due, {
    String? dueDate,
    String? dueTime,
  }) {
    final explicit = parseExplicitDue(due);
    final date = _validDate(dueDate) ??
        (dueDate == null && explicit != null ? _dateOnly(explicit.date) : null);
    final time = _validTime(dueTime) ??
        (dueTime == null && explicit?.hasTime == true
            ? _timeOnly(explicit!.date)
            : null);
    if (dueDate != null && date == null) {
      throw ArgumentError.value(dueDate, 'dueDate', 'invalid calendar date');
    }
    if (dueTime != null && time == null) {
      throw ArgumentError.value(dueTime, 'dueTime', 'invalid wall-clock time');
    }
    if (time != null && date == null) {
      throw ArgumentError('todo time requires a calendar date');
    }
    final label = date == null
        ? (due.trim().isEmpty ? reportDueUnknown : due.trim())
        : '$date${time == null ? '' : ' $time'}';
    return _TodoSchedule(date: date, time: time, label: label);
  }

  String? _validDate(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? value
        : null;
  }

  String? _validTime(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    return hour < 24 && minute < 60 ? value : null;
  }

  String _dateOnly(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _timeOnly(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

class _TodoSchedule {
  const _TodoSchedule(
      {required this.date, required this.time, required this.label});

  final String? date;
  final String? time;
  final String label;
}
