import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_alarm_service.dart';
import 'package:memex/data/services/todo_sync_service.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

/// Local Todo storage and the compatibility bridge used by session reports.
class TodoService {
  TodoService({FileSystemService? fileService, TodoSyncService? syncService})
      : _fileService = fileService,
        _syncService = syncService;

  static final Lock _storageLock = Lock();

  /// Test seam: production always uses [TodoAlarmService.instance].
  static Future<TodoAlarmStatus> Function(List<TodoItem> items)
      alarmSynchronizer =
      (items) => TodoAlarmService.instance.synchronize(items);

  // Alarm sync runs outside [_storageLock]. At most one run is active; a
  // request made meanwhile only sets [_alarmDirty], so exactly one more run
  // re-reads the newest list.
  static Future<TodoAlarmStatus>? _alarmRun;
  static bool _alarmDirty = false;

  /// Test hook: completes once no alarm sync run is in progress.
  static Future<void> waitForAlarmSync() async {
    while (_alarmRun != null) {
      await _alarmRun;
    }
  }

  Future<TodoAlarmStatus> synchronizeAlarms(String userId) =>
      _requestAlarmSync(userId);

  /// Name of the newest legacy file kept aside as damaged, or null.
  Future<String?> damagedLegacyFileName(String userId) async {
    final folder = Directory(_files.getTodoPath(userId));
    if (!await folder.exists()) return null;
    String? newest;
    await for (final entity in folder.list()) {
      final name = p.basename(entity.path);
      if (name.startsWith(FileSystemService.legacyTodoQuarantinePrefix) &&
          (newest == null || name.compareTo(newest) > 0)) {
        newest = name;
      }
    }
    return newest;
  }

  final FileSystemService? _fileService;
  final TodoSyncService? _syncService;
  FileSystemService get _files => _fileService ?? FileSystemService.instance;
  final _logger = getLogger('TodoService');
  final _uuid = const Uuid();

  /// Applies remote sync mutations or conflict resolutions atomically under
  /// [_storageLock], refreshing local alarms without echoing back to outbox.
  Future<bool> applyRemoteMutationBatch(
    String userId,
    FutureOr<List<TodoItem>?> Function(List<TodoItem> current) transform,
  ) =>
      _storageLock.synchronized(() async {
        final current = await _readAll(userId);
        final updated = await transform(current);
        if (updated == null) return false;
        await _write(userId, updated);
        return true;
      });

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
          await _recordLocalSync(
            userId,
            [(item: restored, baseVersion: existing.version)],
            items,
          );
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
      final updated = item.copyWith(
        done: done,
        doneAt: done ? moment.toIso8601String() : null,
        clearDoneAt: !done,
        clearSnoozedUntil: true,
        version: item.version + 1,
      );
      items[index] = updated;
      TodoItem? nextOccurrence;
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
          nextOccurrence = TodoItem(
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
          );
          items.add(nextOccurrence);
        }
      }
      await _write(userId, items);
      await _recordLocalSync(
        userId,
        [
          (item: updated, baseVersion: item.version),
          if (nextOccurrence != null) (item: nextOccurrence, baseVersion: 0),
        ],
        items,
      );
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
        final restored = item.copyWith(
          clearDeletedAt: true,
          clearSnoozedUntil: true,
          version: item.version + 1,
        );
        items[index] = restored;
        await _write(userId, items);
        await _recordLocalSync(
          userId,
          [(item: restored, baseVersion: item.version)],
          items,
        );
      });

  /// Deleting a session tombstones its open copies and detaches completed ones.
  Future<void> deleteForSession({
    required String userId,
    required String sessionId,
  }) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        final now = DateTime.now().toIso8601String();
        final kept = <TodoItem>[];
        final mutations = <({TodoItem item, int baseVersion})>[];
        for (final item in items) {
          if (item.source?.sessionId != sessionId || item.isTombstoned) {
            kept.add(item);
          } else {
            final next = item.done
                ? item.copyWith(clearSource: true, version: item.version + 1)
                : item.copyWith(deletedAt: now, version: item.version + 1);
            kept.add(next);
            mutations.add((item: next, baseVersion: item.version));
          }
        }
        if (mutations.isNotEmpty) {
          await _write(userId, kept);
          await _recordLocalSync(userId, mutations, kept);
        }
      });

  Future<void> markReportItemStale({
    required String userId,
    required String sessionId,
    required String itemId,
  }) =>
      _storageLock.synchronized(() async {
        final items = await _readAll(userId);
        final updated = <TodoItem>[];
        final mutations = <({TodoItem item, int baseVersion})>[];
        for (final item in items) {
          if (item.source?.sessionId == sessionId &&
              item.source?.itemId == itemId &&
              !item.sourceStale &&
              !item.isTombstoned) {
            final next =
                item.copyWith(sourceStale: true, version: item.version + 1);
            updated.add(next);
            mutations.add((item: next, baseVersion: item.version));
          } else {
            updated.add(item);
          }
        }
        if (mutations.isNotEmpty) {
          await _write(userId, updated);
          await _recordLocalSync(userId, mutations, updated);
        }
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
        final previous = items[index];
        final next = change(previous);
        items[index] = next;
        await _write(userId, items);
        await _recordLocalSync(
          userId,
          [(item: next, baseVersion: previous.version)],
          items,
        );
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
    final updated = [...items, item];
    await _write(userId, updated);
    await _recordLocalSync(
      userId,
      [(item: item, baseVersion: 0)],
      updated,
    );
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
    final List<TodoItem> items;
    try {
      final raw = jsonDecode(await legacy.readAsString());
      if (raw is! Map || raw['items'] is! List) {
        throw const FormatException('legacy Todo file is malformed');
      }
      items = [
        for (final item in raw['items'] as List)
          TodoItem.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } on FormatException catch (_, stackTrace) {
      await _quarantineLegacy(userId, legacy, stackTrace);
      return;
    } on TypeError catch (_, stackTrace) {
      await _quarantineLegacy(userId, legacy, stackTrace);
      return;
    } on ArgumentError catch (_, stackTrace) {
      await _quarantineLegacy(userId, legacy, stackTrace);
      return;
    }
    await _write(userId, items);
  }

  /// Keeps a copy of an unreadable legacy file and starts an empty Todo.
  /// The log names the file only: its contents may be personal.
  Future<void> _quarantineLegacy(
    String userId,
    File legacy,
    StackTrace stackTrace,
  ) async {
    final quarantine = File(_files.getLegacyTodoQuarantinePath(
      userId,
      _quarantineStamp(DateTime.now()),
    ));
    await legacy.copy(quarantine.path);
    _logger.warning(
      'Damaged legacy Todo file kept as ${p.basename(quarantine.path)}',
      null,
      stackTrace,
    );
    await _write(userId, const []);
  }

  String _quarantineStamp(DateTime moment) {
    String pad(int value, [int width = 2]) =>
        value.toString().padLeft(width, '0');
    return '${pad(moment.year, 4)}${pad(moment.month)}${pad(moment.day)}'
        'T${pad(moment.hour)}${pad(moment.minute)}${pad(moment.second)}';
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
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    // Only after the rename and outside the lock: a stuck alarm channel must
    // never block Todo reads or writes.
    unawaited(_requestAlarmSync(userId));
  }

  Future<void> _recordLocalSync(
    String userId,
    List<({TodoItem item, int baseVersion})> mutations,
    List<TodoItem> allItems,
  ) async {
    if (mutations.isEmpty) return;
    try {
      final sync = _syncService ?? TodoSyncService.instance;
      final shouldPush = await sync.recordLocalMutations(
        userId: userId,
        mutations: mutations,
        allItems: allItems,
        files: _files,
      );
      if (shouldPush && sync.autoSyncEnabled) {
        unawaited(
          sync
              .syncNow(
                userId: userId,
                reason: 'local_mutation',
                files: _files,
              )
              .then((_) {}, onError: (_) {}),
        );
      }
    } catch (error, stackTrace) {
      _logger.warning(
        'Local todo sync recording skipped (${error.runtimeType})',
        null,
        stackTrace,
      );
    }
  }

  Future<TodoAlarmStatus> _requestAlarmSync(String userId) {
    _alarmDirty = true;
    return _alarmRun ??= _runAlarmSync(userId);
  }

  Future<TodoAlarmStatus> _runAlarmSync(String userId) async {
    var status = TodoAlarmStatus.unavailable;
    while (_alarmDirty) {
      _alarmDirty = false;
      try {
        final items = await _storageLock.synchronized(() => _readAll(userId));
        status = await alarmSynchronizer(items);
      } catch (error, stackTrace) {
        _logger.warning('Could not synchronize Todo alarms', error, stackTrace);
        status = TodoAlarmStatus.unavailable;
      }
    }
    // No await between the last check and this line, so a request arriving
    // now starts a fresh run instead of joining a finished one.
    _alarmRun = null;
    return status;
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
