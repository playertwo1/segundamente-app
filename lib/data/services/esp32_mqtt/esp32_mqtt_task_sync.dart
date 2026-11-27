import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

const String _kMetaPrefsKey = 'esp32_mqtt_task_meta_v1';
const int _kContractVersion = 1;
const String _kTopicPrefix = 'tarefas/';
const Duration _kDoneWindow = Duration(days: 14);
const int _kHashLength = 16;

/// Sync bookkeeping for one task. Not secret: it holds only ids, times and
/// a content hash. JSON keys are short: u, h, s, p, d.
class Esp32TaskMeta {
  const Esp32TaskMeta({
    required this.updatedAt,
    required this.hash,
    this.synced = false,
    this.pending = false,
    this.deleted = false,
  });

  /// Seconds since the Unix epoch, as sent in `updated_at`.
  final int updatedAt;
  final String hash;

  /// Published by this phone or received from the board.
  final bool synced;

  /// Local change not yet published.
  final bool pending;
  final bool deleted;

  Esp32TaskMeta copyWith({
    int? updatedAt,
    String? hash,
    bool? synced,
    bool? pending,
    bool? deleted,
  }) {
    return Esp32TaskMeta(
      updatedAt: updatedAt ?? this.updatedAt,
      hash: hash ?? this.hash,
      synced: synced ?? this.synced,
      pending: pending ?? this.pending,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'u': updatedAt,
        'h': hash,
        's': synced,
        'p': pending,
        'd': deleted,
      };

  static Esp32TaskMeta fromJson(Map<String, dynamic> json) {
    final updatedAt = json['u'];
    final hash = json['h'];
    if (updatedAt is! int || hash is! String) {
      throw const FormatException('task meta is malformed');
    }
    return Esp32TaskMeta(
      updatedAt: updatedAt,
      hash: hash,
      synced: json['s'] == true,
      pending: json['p'] == true,
      deleted: json['d'] == true,
    );
  }
}

abstract class Esp32TaskMetaStore {
  Future<Map<String, Esp32TaskMeta>> load();
  Future<void> save(Map<String, Esp32TaskMeta> metas);
}

/// SharedPreferences store. An unreadable value reads as empty, so every
/// local task is treated as untracked and republished, never deleted.
class SharedPrefsEsp32TaskMetaStore implements Esp32TaskMetaStore {
  const SharedPrefsEsp32TaskMetaStore();

  static final _logger = getLogger('Esp32MqttTaskSync');

  @override
  Future<Map<String, Esp32TaskMeta>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMetaPrefsKey);
    if (raw == null) return <String, Esp32TaskMeta>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      return <String, Esp32TaskMeta>{
        for (final entry in decoded.entries)
          if (entry.value is Map)
            entry.key as String: Esp32TaskMeta.fromJson(
              (entry.value as Map).cast<String, dynamic>(),
            ),
      };
    } catch (_) {
      _logger.warning('Task metadata unreadable; starting empty');
      return <String, Esp32TaskMeta>{};
    }
  }

  @override
  Future<void> save(Map<String, Esp32TaskMeta> metas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kMetaPrefsKey,
      jsonEncode({
        for (final entry in metas.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}

/// Keeps the Todo list of the phone in sync with the board's tasks over MQTT
/// (see docs/roadmap/mqtt/PROTOCOLO.md, "Formato da tarefa").
class Esp32MqttTaskSync {
  Esp32MqttTaskSync({
    required Esp32MqttService service,
    TodoService? todoService,
    Future<String?> Function()? userIdProvider,
    Esp32TaskMetaStore? metaStore,
    DateTime Function()? now,
    Duration retainedQuiet = const Duration(milliseconds: 1500),
    Duration retainedMax = const Duration(seconds: 5),
    Timer Function(Duration, void Function())? timerFactory,
  })  : _service = service,
        _todo = todoService ?? TodoService(),
        _userIdProvider = userIdProvider ?? UserStorage.getUserId,
        _metaStore = metaStore ?? const SharedPrefsEsp32TaskMetaStore(),
        _now = now ?? DateTime.now,
        _retainedQuiet = retainedQuiet,
        _retainedMax = retainedMax,
        _timerFactory = timerFactory ?? _defaultTimer;

  static final Esp32MqttTaskSync instance =
      Esp32MqttTaskSync(service: Esp32MqttService.instance);

  static final _logger = getLogger('Esp32MqttTaskSync');

  final Esp32MqttService _service;
  final TodoService _todo;
  final Future<String?> Function() _userIdProvider;
  final Esp32TaskMetaStore _metaStore;
  final DateTime Function() _now;
  final Duration _retainedQuiet;
  final Duration _retainedMax;
  final Timer Function(Duration, void Function()) _timerFactory;

  /// Serializes every metadata and Todo change of this class.
  final Lock _lock = Lock();

  bool _started = false;
  StreamSubscription<Esp32MqttMessage>? _messageSub;
  StreamSubscription<void>? _connectedSub;

  /// Bumped on every connection and on stop, so late timers do nothing.
  int _session = 0;
  bool _collecting = false;
  final List<_RemoteTask> _buffer = <_RemoteTask>[];
  Timer? _quietTimer;
  Timer? _maxTimer;

  /// Subscribes to task topics and listens to the Todo changes.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _messageSub = _service.messages.listen(_onMessage);
    _connectedSub = _service.onConnected.listen((_) => _onConnected());
    TodoService.localMutationObserver = _onLocalMutation;
    if (_service.status.value.link == Esp32MqttLinkState.connected) {
      _onConnected();
    }
  }

  Future<void> stop() async {
    _started = false;
    _session++;
    _cancelWindow();
    _collecting = false;
    _buffer.clear();
    await _messageSub?.cancel();
    _messageSub = null;
    await _connectedSub?.cancel();
    _connectedSub = null;
    TodoService.localMutationObserver = null;
  }

  /// Forgets all sync bookkeeping (used by "Esquecer placa").
  Future<void> clearMeta() => _serialized(
        'clearMeta',
        () => _metaStore.save(<String, Esp32TaskMeta>{}),
      );

  /// Publishes pending changes now. When not connected, connects instead; the
  /// reconciliation then runs on connection.
  Future<void> syncNow() async {
    if (_service.status.value.link != Esp32MqttLinkState.connected) {
      await _service.connect();
      return;
    }
    await _withUser('syncNow', (userId) async {
      final metas = await _metaStore.load();
      final items = await _todo.load(userId, includeDeleted: true);
      await _publishStep(items, metas, full: false);
      await _metaStore.save(metas);
    });
  }

  /// Local change from [TodoService]. [userId] is accepted for the observer
  /// contract; the metadata is per board, not per user.
  Future<void> recordLocal(String userId, List<TodoItem> changed) =>
      _serialized('recordLocal', () => _recordLocalBody(changed));

  /// Completes after every operation queued before this call.
  @visibleForTesting
  Future<void> waitForIdle() => _lock.synchronized(() async {});

  void _onLocalMutation(String userId, List<TodoItem> changed) {
    // Runs inside the Todo storage lock: only queue the work here.
    unawaited(recordLocal(userId, changed));
  }

  void _onConnected() {
    final session = ++_session;
    _cancelWindow();
    _collecting = true;
    _buffer.clear();
    unawaited(_service.subscribe('tarefas/+'));
    _armQuiet(session);
    _maxTimer = _timerFactory(_retainedMax, () => _endWindow(session));
  }

  void _armQuiet(int session) {
    _quietTimer?.cancel();
    _quietTimer = _timerFactory(_retainedQuiet, () => _endWindow(session));
  }

  void _cancelWindow() {
    _quietTimer?.cancel();
    _quietTimer = null;
    _maxTimer?.cancel();
    _maxTimer = null;
  }

  /// Ends the retained-message window and reconciles with what arrived.
  void _endWindow(int session) {
    if (!_collecting || session != _session) return;
    _collecting = false;
    _cancelWindow();
    final tasks = List<_RemoteTask>.of(_buffer);
    _buffer.clear();
    if (_service.status.value.link != Esp32MqttLinkState.connected) {
      _logger.warning('Link dropped during the retained window; skipped');
      return;
    }
    unawaited(
      _withUser('reconcile', (userId) => _reconcileBody(userId, tasks)),
    );
  }

  void _onMessage(Esp32MqttMessage message) {
    if (!message.suffix.startsWith(_kTopicPrefix)) return;
    final id = message.suffix.substring(_kTopicPrefix.length);
    if (!_isValidId(id)) {
      _logger.warning('Task message ignored: invalid id');
      return;
    }

    final plaintext = message.plaintext;
    if (plaintext == null) {
      unawaited(
        _withUser(
          'deletion',
          (userId) => _liveBody(userId, const [], deletions: [id]),
        ),
      );
      return;
    }

    final task = _tryParse(id, plaintext);
    if (task == null) return;

    if (_collecting) {
      _buffer.add(task);
      _armQuiet(_session);
      return;
    }
    unawaited(_withUser('live', (userId) => _liveBody(userId, [task])));
  }

  Future<void> _recordLocalBody(List<TodoItem> changed) async {
    final metas = await _metaStore.load();
    final nowSec = _nowSeconds();
    for (final item in changed) {
      if (!_isValidId(item.id)) continue;
      final meta = metas[item.id];

      if (item.isTombstoned) {
        final tombstone = Esp32TaskMeta(
          updatedAt: nowSec,
          hash: meta?.hash ?? _hashItem(item),
          synced: meta?.synced ?? false,
          pending: true,
          deleted: true,
        );
        metas[item.id] = tombstone;
        if (await _service.publishEmptyRetained(_topic(item.id))) {
          metas[item.id] = tombstone.copyWith(pending: false);
        }
        continue;
      }

      final stamped = _stamp(item, meta, nowSec);
      if (stamped == null) continue;
      metas[item.id] = stamped;
      if (_syncable(item, stamped)) {
        if (await _publish(item, stamped)) {
          metas[item.id] = stamped.copyWith(synced: true, pending: false);
        }
      }
    }
    await _metaStore.save(metas);
  }

  Future<void> _reconcileBody(String userId, List<_RemoteTask> tasks) async {
    final metas = await _metaStore.load();
    final remoteIds = {for (final task in tasks) task.id};
    await _mergeBatch(
      userId,
      metas,
      tasks: tasks,
      cleanupAgainst: remoteIds,
    );
    final items = await _todo.load(userId, includeDeleted: true);
    await _publishStep(items, metas, full: true, remoteIds: remoteIds);
    await _metaStore.save(metas);
    _logger.info('Task reconciliation: ${tasks.length} retained received');
  }

  Future<void> _liveBody(
    String userId,
    List<_RemoteTask> tasks, {
    List<String> deletions = const [],
  }) async {
    final metas = await _metaStore.load();
    await _mergeBatch(
      userId,
      metas,
      tasks: tasks,
      deletions: deletions,
    );
    final items = await _todo.load(userId, includeDeleted: true);
    await _publishStep(items, metas, full: false);
    await _metaStore.save(metas);
  }

  /// One Todo write for the whole batch.
  Future<void> _mergeBatch(
    String userId,
    Map<String, Esp32TaskMeta> metas, {
    required List<_RemoteTask> tasks,
    List<String> deletions = const [],
    Set<String>? cleanupAgainst,
  }) async {
    final nowSec = _nowSeconds();
    final nowIso = _now().toIso8601String();
    await _todo.applyRemoteMutationBatch(userId, (current) {
      final work = _Working(current, metas, nowSec, nowIso);
      for (final task in tasks) {
        _mergeRemote(work, task);
      }
      for (final id in deletions) {
        _applyDeletion(work, id);
      }
      if (cleanupAgainst != null) _cleanup(work, cleanupAgainst);
      return work.changed ? work.items : null;
    });
  }

  /// Merges one retained or live task against the local copy and its meta.
  void _mergeRemote(_Working work, _RemoteTask remote) {
    final index = work.indexOf(remote.id);
    final item = index < 0 ? null : work.items[index];
    final meta = work.metas[remote.id];

    if (item != null && !item.isTombstoned) {
      _mergeActive(work, remote, index, item, meta);
      return;
    }

    if (item == null && meta?.deleted != true) {
      work.append(_newFromRemote(work, remote));
      work.metas[remote.id] = _remoteMeta(remote);
      return;
    }

    // Deleted here, or meta says deleted: the remote copy only comes back when
    // it is newer than the deletion.
    final localU = meta?.updatedAt ?? _secondsOf(item?.deletedAt) ?? 0;
    if (remote.updatedAt <= localU) {
      work.metas[remote.id] = Esp32TaskMeta(
        updatedAt: localU,
        hash: meta?.hash ?? remote.hash,
        synced: meta?.synced ?? true,
        pending: true,
        deleted: true,
      );
      return;
    }
    if (item == null) {
      work.append(_newFromRemote(work, remote));
    } else {
      work.replace(
        index,
        _applyContent(work, item, remote, clearDeleted: true),
      );
    }
    work.metas[remote.id] = _remoteMeta(remote);
  }

  TodoItem _newFromRemote(_Working work, _RemoteTask remote) {
    final due = _dueFields(remote.dueTs);
    return TodoItem(
      id: remote.id,
      text: remote.text,
      due: due.due,
      dueDate: due.dueDate,
      dueTime: due.dueTime,
      done: remote.done,
      createdAt: work.nowIso,
      doneAt: remote.done ? work.nowIso : null,
    );
  }

  void _mergeActive(
    _Working work,
    _RemoteTask remote,
    int index,
    TodoItem item,
    Esp32TaskMeta? meta,
  ) {
    final hash = _hashItem(item);
    final trusted = meta != null && !meta.deleted && meta.hash == hash;
    // A change that did not pass the Todo hook counts as made now.
    final localU = trusted ? meta.updatedAt : work.nowSec;
    if (!trusted) {
      work.metas[remote.id] = Esp32TaskMeta(
        updatedAt: localU,
        hash: hash,
        synced: meta?.synced ?? false,
        pending: true,
      );
    }

    if (remote.updatedAt > localU) {
      final next = _applyContent(work, item, remote, clearDeleted: false);
      // The version moves only when content changed, so no change is written.
      if (next.version != item.version) work.replace(index, next);
      work.metas[remote.id] = _remoteMeta(remote);
    } else if (remote.updatedAt == localU) {
      work.metas[remote.id] = Esp32TaskMeta(
        updatedAt: localU,
        hash: hash,
        synced: true,
      );
    } else {
      work.metas[remote.id] = Esp32TaskMeta(
        updatedAt: localU,
        hash: hash,
        synced: true,
        pending: true,
      );
    }
  }

  /// Applies the remote content. The version moves only when content changes.
  TodoItem _applyContent(
    _Working work,
    TodoItem item,
    _RemoteTask remote, {
    required bool clearDeleted,
  }) {
    final dueChanged = _dueTs(item) != remote.dueTs;
    final due = _dueFields(remote.dueTs);
    final contentChanged = item.text != remote.text ||
        item.done != remote.done ||
        dueChanged ||
        clearDeleted;
    return item.copyWith(
      text: remote.text,
      done: remote.done,
      doneAt: remote.done ? (item.doneAt ?? work.nowIso) : null,
      clearDoneAt: !remote.done,
      due: dueChanged ? due.due : null,
      dueDate: dueChanged ? due.dueDate : null,
      dueTime: dueChanged ? due.dueTime : null,
      clearDueDate: dueChanged && due.dueDate == null,
      clearDueTime: dueChanged && due.dueTime == null,
      clearDeletedAt: clearDeleted,
      version: contentChanged ? item.version + 1 : item.version,
    );
  }

  /// Empty payload from the board: deletes the task when it is known here.
  void _applyDeletion(_Working work, String id) {
    final index = work.indexOf(id);
    final meta = work.metas[id];
    if (index < 0 || meta == null) return;
    final item = work.items[index];
    if (item.isTombstoned) return;
    work.replace(
      index,
      item.copyWith(deletedAt: work.nowIso, version: item.version + 1),
    );
    work.metas[id] = meta.copyWith(
      updatedAt: work.nowSec,
      deleted: true,
      pending: false,
    );
  }

  /// After a full retained set: deletes synced tasks the board no longer
  /// holds, unless that looks like a lost broker state.
  void _cleanup(_Working work, Set<String> remoteIds) {
    final active = [
      for (final item in work.items)
        if (!item.isTombstoned) item,
    ];
    final kept = [
      for (final item in active)
        if (work.metas[item.id]?.synced == true &&
            work.metas[item.id]?.deleted != true)
          item.id,
    ];
    final missing = [
      for (final id in kept)
        if (!remoteIds.contains(id)) id,
    ];
    final untrusted = (remoteIds.isEmpty && kept.isNotEmpty) ||
        (missing.length * 2 > active.length && missing.length > 3);

    if (untrusted) {
      _logger.warning(
        'Retained set not trusted (remote=${remoteIds.length}, '
        'missing=${missing.length}, active=${active.length}); not deleting',
      );
      for (final item in active) {
        final meta = work.metas[item.id];
        if (!_syncable(item, meta)) continue;
        final stamped = _stamp(item, meta, work.nowSec);
        work.metas[item.id] = stamped ?? meta!.copyWith(pending: true);
      }
      return;
    }

    for (final id in missing) {
      final meta = work.metas[id]!;
      if (meta.pending) continue; // republished in the publish step
      final index = work.indexOf(id);
      work.replace(
        index,
        work.items[index].copyWith(
          deletedAt: work.nowIso,
          version: work.items[index].version + 1,
        ),
      );
      work.metas[id] = meta.copyWith(
        updatedAt: work.nowSec,
        deleted: true,
        pending: false,
      );
    }
  }

  /// Publishes what is pending, plus (on a full reconcile) every syncable
  /// task the board did not send back, then clears pending deletions.
  Future<void> _publishStep(
    List<TodoItem> items,
    Map<String, Esp32TaskMeta> metas, {
    required bool full,
    Set<String> remoteIds = const {},
  }) async {
    final nowSec = _nowSeconds();
    for (final item in items) {
      if (item.isTombstoned) continue;
      final meta = metas[item.id];
      if (!_syncable(item, meta)) continue;
      final current = _stamp(item, meta, nowSec) ?? meta;
      if (current == null) continue;
      final wanted = current.pending || (full && !remoteIds.contains(item.id));
      if (!wanted) continue;
      metas[item.id] = current;
      if (await _publish(item, current)) {
        metas[item.id] = current.copyWith(synced: true, pending: false);
      }
    }
    for (final entry in metas.entries.toList()) {
      final meta = entry.value;
      if (meta.deleted && meta.pending) {
        if (await _service.publishEmptyRetained(_topic(entry.key))) {
          metas[entry.key] = meta.copyWith(pending: false);
        }
      }
    }
  }

  Future<bool> _publish(TodoItem item, Esp32TaskMeta meta) {
    final envelope = <String, dynamic>{
      'contract_version': _kContractVersion,
      'entity_type': 'todo',
      'entity_id': item.id,
      'origin_role': 'mobile',
      'updated_at': meta.updatedAt,
      'new_version': item.version,
      'payload': <String, dynamic>{
        'id': item.id,
        'text': item.text,
        'done': item.done,
        'due_ts': _dueTs(item),
      },
    };
    return _service.publishEncrypted(
      _topic(item.id),
      jsonEncode(envelope),
      retain: true,
    );
  }

  /// Returns the meta for a local change, or null when the content hash has
  /// not changed (for example, only priority or snooze changed).
  Esp32TaskMeta? _stamp(TodoItem item, Esp32TaskMeta? meta, int nowSec) {
    final hash = _hashItem(item);
    if (meta != null && !meta.deleted && meta.hash == hash) return null;
    return Esp32TaskMeta(
      updatedAt: nowSec,
      hash: hash,
      synced: meta?.synced ?? false,
      pending: true,
    );
  }

  /// Done tasks stay syncable for 14 days after completion, unless synced.
  bool _syncable(TodoItem item, Esp32TaskMeta? meta) {
    if (item.isTombstoned) return false;
    if (!item.done) return true;
    if (meta?.synced == true) return true;
    final doneAt = item.doneAt == null ? null : DateTime.tryParse(item.doneAt!);
    return doneAt != null && _now().difference(doneAt) <= _kDoneWindow;
  }

  Esp32TaskMeta _remoteMeta(_RemoteTask remote) => Esp32TaskMeta(
        updatedAt: remote.updatedAt,
        hash: remote.hash,
        synced: true,
      );

  String _hashItem(TodoItem item) =>
      _contentHash(item.text, item.done, _dueTs(item));

  String _topic(String id) => '$_kTopicPrefix$id';

  int _nowSeconds() => _now().millisecondsSinceEpoch ~/ 1000;

  Future<void> _serialized(String label, Future<void> Function() body) {
    return _lock.synchronized(() async {
      try {
        await body();
      } catch (error) {
        _logger.warning('$label skipped (${error.runtimeType})');
      }
    });
  }

  Future<void> _withUser(
    String label,
    Future<void> Function(String userId) body,
  ) {
    return _serialized(label, () async {
      final userId = await _userIdProvider();
      if (userId == null || userId.isEmpty) return;
      await body(userId);
    });
  }

  static Timer _defaultTimer(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

/// Mutable view of one Todo batch while it is merged inside the storage lock.
class _Working {
  _Working(List<TodoItem> current, this.metas, this.nowSec, this.nowIso)
      : items = List<TodoItem>.of(current);

  final List<TodoItem> items;
  final Map<String, Esp32TaskMeta> metas;
  final int nowSec;
  final String nowIso;
  bool changed = false;

  int indexOf(String id) => items.indexWhere((item) => item.id == id);

  void replace(int index, TodoItem item) {
    items[index] = item;
    changed = true;
  }

  void append(TodoItem item) {
    items.add(item);
    changed = true;
  }
}

/// A task received from the board, already validated.
class _RemoteTask {
  const _RemoteTask({
    required this.id,
    required this.text,
    required this.done,
    required this.dueTs,
    required this.updatedAt,
  });

  final String id;
  final String text;
  final bool done;
  final int dueTs;
  final int updatedAt;

  String get hash => _contentHash(text, done, dueTs);
}

/// Logs only the reason a message was dropped, never its content.
_RemoteTask? _tryParse(String topicId, String plaintext) {
  try {
    return _parseRemote(topicId, plaintext);
  } on FormatException catch (error) {
    getLogger('Esp32MqttTaskSync')
        .warning('Task message dropped: ${error.message}');
    return null;
  }
}

_RemoteTask _parseRemote(String topicId, String plaintext) {
  final Object? decoded;
  try {
    decoded = jsonDecode(plaintext);
  } on FormatException {
    throw const FormatException('not_json');
  }
  if (decoded is! Map) throw const FormatException('not_object');

  final entityType = decoded['entity_type'];
  if (entityType != null && entityType != 'todo') {
    throw const FormatException('entity_type');
  }
  final entityId = decoded['entity_id'];
  if (entityId is! String || entityId.isEmpty || entityId != topicId) {
    throw const FormatException('entity_id');
  }
  final updatedAt = _integer(decoded['updated_at']);
  if (updatedAt == null) throw const FormatException('updated_at');

  final payload = decoded['payload'];
  if (payload is! Map) throw const FormatException('payload');
  final text = payload['text'];
  if (text is! String || text.trim().isEmpty) {
    throw const FormatException('text');
  }
  final done = payload['done'];
  if (done != null && done is! bool) throw const FormatException('done');
  final dueRaw = payload['due_ts'];
  int dueTs = 0;
  if (dueRaw != null) {
    if (dueRaw is! num || !dueRaw.toDouble().isFinite) {
      throw const FormatException('due_ts');
    }
    final raw = dueRaw.toInt();
    // Whole minutes only: the app stores due times to the minute.
    dueTs = raw > 0 ? raw - raw % 60 : 0;
  }

  return _RemoteTask(
    id: topicId,
    text: text.trim(),
    done: done == true,
    dueTs: dueTs,
    updatedAt: updatedAt,
  );
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is double) {
    return value.isFinite && value == value.truncateToDouble()
        ? value.toInt()
        : null;
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _isValidId(String id) =>
    id.isNotEmpty &&
    !id.contains('/') &&
    !id.contains('+') &&
    !id.contains('#');

String _contentHash(String text, bool done, int dueTs) {
  final digest = sha256.convert(utf8.encode(jsonEncode([text, done, dueTs])));
  return digest.toString().substring(0, _kHashLength);
}

/// Due time in seconds since the epoch, read as local time.
int _dueTs(TodoItem item) {
  final date = item.dueDate;
  if (date != null) {
    final day = _parseDay(date);
    if (day != null) {
      final clock = item.dueTime == null ? null : _parseClock(item.dueTime!);
      final dt = DateTime(
        day.$1,
        day.$2,
        day.$3,
        clock?.$1 ?? 0,
        clock?.$2 ?? 0,
      );
      return dt.millisecondsSinceEpoch ~/ 1000;
    }
  }
  final explicit = parseExplicitDue(item.due);
  if (explicit != null) {
    return explicit.date.millisecondsSinceEpoch ~/ 1000;
  }
  return 0;
}

({String due, String? dueDate, String? dueTime}) _dueFields(int dueTs) {
  if (dueTs <= 0) {
    return (due: reportDueUnknown, dueDate: null, dueTime: null);
  }
  final dt = DateTime.fromMillisecondsSinceEpoch(dueTs * 1000);
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${dt.year.toString().padLeft(4, '0')}-'
      '${two(dt.month)}-${two(dt.day)}';
  final time = '${two(dt.hour)}:${two(dt.minute)}';
  return (due: '$date $time', dueDate: date, dueTime: time);
}

(int, int, int)? _parseDay(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  return (
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

(int, int)? _parseClock(String text) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text);
  if (match == null) return null;
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

int? _secondsOf(String? iso) {
  if (iso == null) return null;
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? null : parsed.millisecondsSinceEpoch ~/ 1000;
}
