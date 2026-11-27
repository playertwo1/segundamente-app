import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/secret_storage.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kEsp32BleChannelName = 'com.memexlab.memex/esp32_ble';
const String kEsp32BleKeySecret = 'esp32_ble_key_v1';
const String kEsp32PendingSyncPrefsKey = 'esp32_pending_sync_tasks';
const String kEsp32AllowedAppsPrefsKey = 'esp32_ble_allowed_apps';
const Set<String> kEsp32DefaultAllowedApps = {
  'whatsapp',
  'call',
  'ligacao',
  'calendar',
};
const Set<String> kEsp32SupportedApps = {
  'whatsapp',
  'call',
  'ligacao',
  'msg',
  'alert',
  'calendar',
};
const int kEsp32MaxCommandBytes = 950;
const int kEsp32MaxTitleBytes = 63;
const int kEsp32MaxBodyBytes = 159;

/// Task envelope exchanged with the ESP32-S3 AMOLED board over BLE GATT.
class Esp32SyncTask {
  const Esp32SyncTask({
    required this.entityId,
    required this.text,
    this.done = false,
    this.dueTs = 0,
  });

  final String entityId;
  final String text;
  final bool done;
  final int dueTs;

  Map<String, dynamic> toEnvelopeJson() => <String, dynamic>{
        'entity_id': entityId,
        'payload': <String, dynamic>{
          'text': text,
          'done': done,
          'due_ts': dueTs,
        },
      };

  static Esp32SyncTask? fromEnvelopeJson(Map<String, dynamic> json) {
    final entityId = json['entity_id']?.toString().trim() ?? '';
    final payload = json['payload'];
    if (entityId.isEmpty || payload is! Map) return null;
    final text = payload['text']?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final due = payload['due_ts'];
    return Esp32SyncTask(
      entityId: entityId,
      text: text,
      done: payload['done'] == true,
      dueTs: due is num ? due.toInt() : 0,
    );
  }
}

/// Abstract secret store seam so tests do not require platform secure storage.
abstract class Esp32SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureEsp32SecretStore implements Esp32SecretStore {
  const SecureEsp32SecretStore();

  @override
  Future<String?> read(String key) => SecretStorage.read(key);

  @override
  Future<void> write(String key, String value) => SecretStorage.write(key, value);

  @override
  Future<void> delete(String key) => SecretStorage.delete(key);
}

/// Abstract BLE transport seam backed by Android MethodChannel in production.
abstract class Esp32BleTransport {
  Future<bool> scanAndConnect({int timeoutMs = 10000});
  Future<void> disconnect();
  Future<bool> isConnected();
  Future<String?> readStatus();
  Future<bool> writeJson(String payload);
  Future<bool> hasBlePermissions();
  Future<bool> requestBlePermissions();
  Future<bool> hasNotificationAccess();
  Future<void> openNotificationAccessSettings();
  void setCallbacks({
    void Function(String line)? onBleLine,
    void Function(bool connected)? onConnectionChanged,
    void Function(Map<String, String> notification)? onNotification,
  });
}

class MethodChannelEsp32BleTransport implements Esp32BleTransport {
  MethodChannelEsp32BleTransport({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(kEsp32BleChannelName);

  final MethodChannel _channel;
  void Function(String line)? _onBleLine;
  void Function(bool connected)? _onConnectionChanged;
  void Function(Map<String, String> notification)? _onNotification;

  @override
  void setCallbacks({
    void Function(String line)? onBleLine,
    void Function(bool connected)? onConnectionChanged,
    void Function(Map<String, String> notification)? onNotification,
  }) {
    _onBleLine = onBleLine;
    _onConnectionChanged = onConnectionChanged;
    _onNotification = onNotification;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onBleLine':
        final line = call.arguments;
        if (line is String) _onBleLine?.call(line);
        break;
      case 'onConnectionChanged':
        final connected = call.arguments;
        if (connected is bool) _onConnectionChanged?.call(connected);
        break;
      case 'onNotification':
        final raw = call.arguments;
        if (raw is Map) {
          _onNotification?.call(<String, String>{
            'app': raw['app']?.toString() ?? '',
            'title': raw['title']?.toString() ?? '',
            'body': raw['body']?.toString() ?? '',
          });
        }
        break;
    }
    return null;
  }

  @override
  Future<bool> scanAndConnect({int timeoutMs = 10000}) async =>
      await _channel.invokeMethod<bool>(
        'scanAndConnect',
        <String, dynamic>{'timeoutMs': timeoutMs},
      ) ??
      false;

  @override
  Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');

  @override
  Future<bool> isConnected() async =>
      await _channel.invokeMethod<bool>('isConnected') ?? false;

  @override
  Future<String?> readStatus() => _channel.invokeMethod<String>('readStatus');

  @override
  Future<bool> writeJson(String payload) async =>
      await _channel.invokeMethod<bool>(
        'writeJson',
        <String, dynamic>{'payload': payload},
      ) ??
      false;

  @override
  Future<bool> hasBlePermissions() async =>
      await _channel.invokeMethod<bool>('hasBlePermissions') ?? false;

  @override
  Future<bool> requestBlePermissions() async =>
      await _channel.invokeMethod<bool>('requestBlePermissions') ?? false;

  @override
  Future<bool> hasNotificationAccess() async =>
      await _channel.invokeMethod<bool>('hasNotificationAccess') ?? false;

  @override
  Future<void> openNotificationAccessSettings() =>
      _channel.invokeMethod<void>('openNotificationAccessSettings');
}

class _PendingReply {
  _PendingReply(this.expectedType, this.completer);
  final String expectedType;
  final Completer<Map<String, dynamic>> completer;
}

/// BLE GATT client bridge (F16) connecting Segundamente to the ESP32-S3 board.
class Esp32BleBridgeService {
  Esp32BleBridgeService({
    Esp32BleTransport? transport,
    Esp32SecretStore? secretStore,
    Future<SharedPreferences> Function()? prefsProvider,
    Duration replyTimeout = const Duration(seconds: 5),
    TodoService? todoService,
    Future<String?> Function()? userIdProvider,
  })  : _transport = transport ?? MethodChannelEsp32BleTransport(),
        _secretStore = secretStore ?? const SecureEsp32SecretStore(),
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _replyTimeout = replyTimeout,
        _todoService = todoService,
        _userIdProvider = userIdProvider ?? UserStorage.getUserId {
    _transport.setCallbacks(
      onBleLine: _handleIncomingLine,
      onConnectionChanged: _handleConnectionChanged,
      onNotification: _handleIncomingNotification,
    );
  }

  static final _logger = getLogger('Esp32BleBridgeService');

  final Esp32BleTransport _transport;
  final Esp32SecretStore _secretStore;
  final Future<SharedPreferences> Function() _prefsProvider;
  final Duration _replyTimeout;
  final TodoService? _todoService;
  final Future<String?> Function() _userIdProvider;

  final List<_PendingReply> _pendingReplies = <_PendingReply>[];
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Set<String> _allowedApps = Set<String>.from(kEsp32DefaultAllowedApps);
  Future<void> _writeQueue = Future<void>.value();

  Stream<bool> get connectionStream => _connectionController.stream;

  /// Computes lowercase HMAC-SHA256 hex over [type] using [keyHex].
  static String signType(String keyHex, String type) {
    final hmac = Hmac(sha256, utf8.encode(keyHex));
    return hmac.convert(utf8.encode(type)).toString();
  }

  /// Truncates [input] so its UTF-8 encoding fits within [maxBytes] cleanly.
  static String utf8Truncate(String input, int maxBytes) {
    if (maxBytes <= 0 || input.isEmpty) return '';
    if (utf8.encode(input).length <= maxBytes) return input;
    final out = StringBuffer();
    var used = 0;
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final len = utf8.encode(ch).length;
      if (used + len > maxBytes) break;
      out.write(ch);
      used += len;
    }
    return out.toString();
  }

  Future<bool> hasBlePermissions() => _transport.hasBlePermissions();
  Future<bool> requestBlePermissions() => _transport.requestBlePermissions();
  Future<bool> hasNotificationAccess() => _transport.hasNotificationAccess();
  Future<void> openNotificationAccessSettings() =>
      _transport.openNotificationAccessSettings();
  Future<bool> isConnected() => _transport.isConnected();
  Future<String?> readBoardStatus() => _transport.readStatus();

  Future<bool> connect({int timeoutMs = 10000}) async {
    await loadAllowedApps();
    final ok = await _transport.scanAndConnect(timeoutMs: timeoutMs);
    if (ok && await isPaired()) {
      await _replayPendingOnReconnect();
    }
    return ok;
  }

  Future<void> disconnect() => _transport.disconnect();

  Future<String?> _readKey() async {
    final key = await _secretStore.read(kEsp32BleKeySecret);
    if (key == null || key.trim().length != 64) return null;
    return key.trim();
  }

  Future<bool> isPaired() async => await _readKey() != null;

  Future<bool> startPairing() async {
    final reply = await _sendCommand(
      const <String, dynamic>{'type': 'pair_start'},
      expectedType: 'pair_code',
    );
    return reply?['ok'] == true;
  }

  Future<bool> confirmPairing(String code) async {
    final clean = code.trim();
    if (clean.length != 6 || int.tryParse(clean) == null) return false;
    final reply = await _sendCommand(
      <String, dynamic>{'type': 'pair_confirm', 'code': clean},
      expectedType: 'pair_ok',
    );
    if (reply == null || reply['ok'] != true) return false;
    final key = reply['key']?.toString().trim() ?? '';
    if (key.length != 64) return false;
    await _secretStore.write(kEsp32BleKeySecret, key);
    return true;
  }

  Future<void> revokePairing() async {
    await _secretStore.delete(kEsp32BleKeySecret);
    if (await _transport.isConnected()) {
      await _sendCommand(
        const <String, dynamic>{'type': 'revoke'},
        expectedType: 'revoke',
      );
    }
  }

  Future<Set<String>> loadAllowedApps() async {
    final prefs = await _prefsProvider();
    final saved = prefs.getStringList(kEsp32AllowedAppsPrefsKey);
    if (saved == null) {
      _allowedApps = Set<String>.from(kEsp32DefaultAllowedApps);
    } else {
      _allowedApps = saved
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return Set<String>.from(_allowedApps);
  }

  Future<void> saveAllowedApps(Set<String> apps) async {
    final normalized = apps
        .map((e) => e.trim().toLowerCase())
        .where(kEsp32SupportedApps.contains)
        .toSet();
    _allowedApps = normalized;
    final prefs = await _prefsProvider();
    await prefs.setStringList(
      kEsp32AllowedAppsPrefsKey,
      normalized.toList()..sort(),
    );
  }

  Future<bool> forwardNotification({
    required String app,
    required String title,
    required String body,
    bool silent = false,
  }) async {
    final normApp = app.trim().toLowerCase();
    if (!kEsp32SupportedApps.contains(normApp) || !_allowedApps.contains(normApp)) {
      return false;
    }
    final key = await _readKey();
    if (key == null || !(await _transport.isConnected())) return false;

    final payload = <String, dynamic>{
      'type': 'notif',
      'hmac': signType(key, 'notif'),
      'app': normApp,
      'title': utf8Truncate(title.trim(), kEsp32MaxTitleBytes),
      'body': utf8Truncate(body.trim(), kEsp32MaxBodyBytes),
      'silent': silent,
    };
    final reply = await _sendCommand(payload, expectedType: 'notif');
    return reply?['ok'] == true;
  }

  Future<void> queuePendingTask(Esp32SyncTask task) async {
    final current = await loadPendingTasks();
    final merged = _dedupTasks(<Esp32SyncTask>[...current, task]);
    await _savePendingTasks(merged);
  }

  Future<List<Esp32SyncTask>> loadPendingTasks() async {
    final prefs = await _prefsProvider();
    final raw = prefs.getString(kEsp32PendingSyncPrefsKey);
    if (raw == null || raw.isEmpty) return const <Esp32SyncTask>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Esp32SyncTask>[];
      final out = <Esp32SyncTask>[];
      for (final item in decoded) {
        if (item is Map) {
          final task = Esp32SyncTask.fromEnvelopeJson(item.cast<String, dynamic>());
          if (task != null) out.add(task);
        }
      }
      return out;
    } catch (_) {
      return const <Esp32SyncTask>[];
    }
  }

  Future<void> _savePendingTasks(List<Esp32SyncTask> tasks) async {
    final prefs = await _prefsProvider();
    if (tasks.isEmpty) {
      await prefs.remove(kEsp32PendingSyncPrefsKey);
      return;
    }
    final encoded = jsonEncode(tasks.map((t) => t.toEnvelopeJson()).toList());
    await prefs.setString(kEsp32PendingSyncPrefsKey, encoded);
  }

  /// Synchronizes tasks over BLE GATT in <950-byte JSON batches.
  /// Queues outgoing tasks locally if not connected or if a send fails.
  Future<List<Esp32SyncTask>> syncTasks({
    List<Esp32SyncTask> outgoing = const <Esp32SyncTask>[],
  }) async {
    final key = await _readKey();
    if (key == null) {
      throw StateError('not_paired');
    }
    final queued = await loadPendingTasks();
    final combined = _dedupTasks(<Esp32SyncTask>[...queued, ...outgoing]);

    if (!(await _transport.isConnected())) {
      if (combined.isNotEmpty) await _savePendingTasks(combined);
      return const <Esp32SyncTask>[];
    }

    final batches = _buildSyncBatches(key, combined);
    final remoteMap = <String, Esp32SyncTask>{};
    var sentCount = 0;

    for (final batch in batches) {
      final hmac = signType(key, 'task_sync');
      final cmd = <String, dynamic>{
        'type': 'task_sync',
        'hmac': hmac,
        'envelopes': batch.map((t) => t.toEnvelopeJson()).toList(),
      };
      final reply = await _sendCommand(cmd, expectedType: 'task_sync');
      if (reply == null || reply['ok'] != true) {
        final remaining = combined.skip(sentCount).toList();
        await _savePendingTasks(remaining);
        throw StateError(reply?['erro']?.toString() ?? 'task_sync_failed');
      }
      sentCount += batch.length;
      final envs = reply['envelopes'];
      if (envs is List) {
        for (final item in envs) {
          if (item is Map) {
            final parsed =
                Esp32SyncTask.fromEnvelopeJson(item.cast<String, dynamic>());
            if (parsed != null) remoteMap[parsed.entityId] = parsed;
          }
        }
      }
    }

    await _savePendingTasks(const <Esp32SyncTask>[]);
    return remoteMap.values.toList();
  }

  /// Convenience bridge with local [TodoService] for the active user.
  Future<int> syncWithTodoService() async {
    final service = _todoService ?? TodoService();
    final userId = await _userIdProvider();
    if (userId == null || userId.isEmpty) return 0;

    final localItems = await service.load(userId);
    final outgoing = <Esp32SyncTask>[
      for (final item in localItems)
        Esp32SyncTask(
          entityId: item.id,
          text: item.text,
          done: item.done,
          dueTs: _parseDueTs(item),
        ),
    ];
    final remoteTasks = await syncTasks(outgoing: outgoing);
    if (remoteTasks.isEmpty) return 0;

    await service.applyRemoteMutationBatch(userId, (current) {
      final next = List<TodoItem>.from(current);
      final byId = <String, int>{
        for (var i = 0; i < next.length; i++) next[i].id: i,
      };
      final nowIso = DateTime.now().toUtc().toIso8601String();
      var changed = false;
      for (final task in remoteTasks) {
        final idx = byId[task.entityId];
        if (idx != null) {
          final existing = next[idx];
          if (existing.done != task.done || existing.text != task.text) {
            next[idx] = existing.copyWith(
              text: task.text,
              done: task.done,
              doneAt: task.done ? (existing.doneAt ?? nowIso) : null,
              clearDoneAt: !task.done,
              version: existing.version + 1,
            );
            changed = true;
          }
        } else {
          final dueDate = task.dueTs > 0
              ? DateTime.fromMillisecondsSinceEpoch(task.dueTs * 1000)
              : null;
          final dueStr = dueDate == null
              ? reportDueUnknown
              : '${dueDate.year.toString().padLeft(4, '0')}-'
                  '${dueDate.month.toString().padLeft(2, '0')}-'
                  '${dueDate.day.toString().padLeft(2, '0')} '
                  '${dueDate.hour.toString().padLeft(2, '0')}:'
                  '${dueDate.minute.toString().padLeft(2, '0')}';
          next.add(
            TodoItem(
              id: task.entityId,
              text: task.text,
              due: dueStr,
              done: task.done,
              createdAt: nowIso,
              doneAt: task.done ? nowIso : null,
            ),
          );
          changed = true;
        }
      }
      return changed ? next : null;
    });
    return remoteTasks.length;
  }

  /// Sends board Wi-Fi, weather city and character (`0..3`) configuration.
  Future<bool> configureBoard({
    String? ssid,
    String? pass,
    String? city,
    int? charIdx,
  }) async {
    if (charIdx != null && (charIdx < 0 || charIdx > 3)) {
      throw RangeError.range(charIdx, 0, 3, 'charIdx');
    }
    final key = await _readKey();
    if (key == null || !(await _transport.isConnected())) return false;

    final payload = <String, dynamic>{
      'type': 'config',
      'hmac': signType(key, 'config'),
    };
    final cleanSsid = ssid?.trim() ?? '';
    final cleanCity = city?.trim() ?? '';
    if (cleanSsid.isNotEmpty) {
      payload['ssid'] = utf8Truncate(cleanSsid, 64);
      if (pass != null) payload['pass'] = utf8Truncate(pass, 128);
    }
    if (cleanCity.isNotEmpty) {
      payload['city'] = utf8Truncate(cleanCity, 64);
    }
    if (charIdx != null) {
      payload['char_idx'] = charIdx;
    }
    final reply = await _sendCommand(payload, expectedType: 'config');
    return reply?['ok'] == true;
  }

  void dispose() {
    _transport.setCallbacks();
    for (final p in List<_PendingReply>.from(_pendingReplies)) {
      if (!p.completer.isCompleted) p.completer.completeError(StateError('disposed'));
    }
    _pendingReplies.clear();
    _connectionController.close();
  }

  List<List<Esp32SyncTask>> _buildSyncBatches(
    String keyHex,
    List<Esp32SyncTask> tasks,
  ) {
    if (tasks.isEmpty) return <List<Esp32SyncTask>>[<Esp32SyncTask>[]];
    final hmac = signType(keyHex, 'task_sync');
    final batches = <List<Esp32SyncTask>>[];
    var current = <Esp32SyncTask>[];

    for (final task in tasks) {
      final candidateTask = _fitSingleEnvelope(hmac, task);
      final candidateList = <Esp32SyncTask>[...current, candidateTask];
      final size = _encodedCommandBytes(hmac, candidateList);
      if (size < kEsp32MaxCommandBytes) {
        current = candidateList;
      } else {
        if (current.isNotEmpty) batches.add(current);
        current = <Esp32SyncTask>[candidateTask];
      }
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  Esp32SyncTask _fitSingleEnvelope(String hmac, Esp32SyncTask task) {
    if (_encodedCommandBytes(hmac, <Esp32SyncTask>[task]) < kEsp32MaxCommandBytes) {
      return task;
    }
    // Trim task text so one envelope never exceeds BLE GATT RX buffer.
    var maxChars = task.text.length;
    while (maxChars > 16) {
      maxChars = (maxChars * 0.7).floor();
      final shrunk = Esp32SyncTask(
        entityId: task.entityId,
        text: task.text.substring(0, maxChars),
        done: task.done,
        dueTs: task.dueTs,
      );
      if (_encodedCommandBytes(hmac, <Esp32SyncTask>[shrunk]) < kEsp32MaxCommandBytes) {
        return shrunk;
      }
    }
    return Esp32SyncTask(
      entityId: task.entityId,
      text: utf8Truncate(task.text, 256),
      done: task.done,
      dueTs: task.dueTs,
    );
  }

  int _encodedCommandBytes(String hmac, List<Esp32SyncTask> envelopes) {
    final json = jsonEncode(<String, dynamic>{
      'type': 'task_sync',
      'hmac': hmac,
      'envelopes': envelopes.map((t) => t.toEnvelopeJson()).toList(),
    });
    return utf8.encode(json).length;
  }

  List<Esp32SyncTask> _dedupTasks(List<Esp32SyncTask> list) {
    final map = <String, Esp32SyncTask>{};
    for (final item in list) {
      map[item.entityId] = item;
    }
    return map.values.toList();
  }

  int _parseDueTs(TodoItem item) {
    final explicit = parseExplicitDue(item.due);
    if (explicit != null) {
      return explicit.date.millisecondsSinceEpoch ~/ 1000;
    }
    return 0;
  }

  Future<Map<String, dynamic>?> _sendCommand(
    Map<String, dynamic> cmd, {
    required String expectedType,
  }) {
    final next = _writeQueue.then((_) async {
      final encoded = jsonEncode(cmd);
      if (utf8.encode(encoded).length > kEsp32MaxCommandBytes) {
        throw StateError('command_too_large');
      }
      final completer = Completer<Map<String, dynamic>>();
      final pending = _PendingReply(expectedType, completer);
      _pendingReplies.add(pending);
      try {
        final written = await _transport.writeJson(encoded);
        if (!written) {
          _pendingReplies.remove(pending);
          return null;
        }
        return await completer.future.timeout(
          _replyTimeout,
          onTimeout: () {
            _pendingReplies.remove(pending);
            return const <String, dynamic>{'ok': false, 'erro': 'timeout'};
          },
        );
      } catch (e) {
        _pendingReplies.remove(pending);
        _logger.warning('BLE write error ($expectedType): $e');
        return null;
      }
    });
    _writeQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  void _handleIncomingLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return;
      final map = decoded.cast<String, dynamic>();
      final type = map['type']?.toString();
      final idx = _pendingReplies.indexWhere(
        (p) => type == null || p.expectedType == type,
      );
      if (idx >= 0) {
        final pending = _pendingReplies.removeAt(idx);
        if (!pending.completer.isCompleted) {
          pending.completer.complete(map);
        }
      }
    } catch (_) {
      // Ignore partial or non-JSON lines from BLE stream.
    }
  }

  void _handleConnectionChanged(bool connected) {
    if (!_connectionController.isClosed) {
      _connectionController.add(connected);
    }
    if (connected) {
      unawaited(_replayPendingOnReconnect());
    }
  }

  Future<void> _replayPendingOnReconnect() async {
    try {
      if (!(await isPaired())) return;
      final pending = await loadPendingTasks();
      if (pending.isEmpty) return;
      await syncTasks();
    } catch (_) {
      // Kept in SharedPreferences until next reconnect.
    }
  }

  void _handleIncomingNotification(Map<String, String> notif) {
    unawaited(
      forwardNotification(
        app: notif['app'] ?? '',
        title: notif['title'] ?? '',
        body: notif['body'] ?? '',
      ),
    );
  }
}
