import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/lumen_mailbox_client.dart';
import 'package:memex/data/services/lumen_pairing_service.dart';
import 'package:memex/data/services/lumen_relay_crypto.dart';
import 'package:memex/data/services/todo_alarm_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/data/services/todo_sync_service.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

class _InMemorySecretStore implements LumenSecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _FakeMessage {
  final int seq;
  final String? msgId;
  final int createdAtMs;
  final Uint8List bodyBytes;

  const _FakeMessage({
    required this.seq,
    this.msgId,
    required this.createdAtMs,
    required this.bodyBytes,
  });
}

/// Stateful in-memory relay mailbox server backing [MockClient] HTTP calls.
class _FakeRelayMailbox {
  final LumenPairing pairing;
  final String expectedJoinProof;
  final List<_FakeMessage> toPcQueue = [];
  final List<_FakeMessage> toPhoneQueue = [];
  final Set<String> seenPcMsgIds = {};
  final Set<String> seenPhoneMsgIds = {};

  int _nextPcSeq = 0;
  int _nextPhoneSeq = 0;
  bool revoked = false;
  int? overridePendingPc;
  int postCount = 0;
  int listCount = 0;
  int ackCount = 0;
  int statsCount = 0;

  _FakeRelayMailbox(this.pairing)
      : expectedJoinProof =
            LumenRelayCrypto.deriveFromBase64Url(pairing.key).joinProof;

  Uint8List get kMailbox =>
      LumenRelayCrypto.deriveFromBase64Url(pairing.key).kMailbox;

  /// Enqueues an envelope from the simulated PC into the phone's inbox.
  int enqueueFromPcMap(Map<String, dynamic> envelope) {
    final sealed = LumenRelayCrypto.sealMailboxEnvelope(
      kMailbox: kMailbox,
      room: pairing.room,
      to: LumenMailboxRole.phone,
      envelope: envelope,
    );
    return enqueueRawBytesToPhone(
      sealed,
      msgId: envelope['mutation_id']?.toString(),
    );
  }

  int enqueueRawBytesToPhone(Uint8List bytes, {String? msgId}) {
    _nextPhoneSeq++;
    toPhoneQueue.add(
      _FakeMessage(
        seq: _nextPhoneSeq,
        msgId: msgId,
        createdAtMs: 1730000000000 + _nextPhoneSeq,
        bodyBytes: bytes,
      ),
    );
    return _nextPhoneSeq;
  }

  /// Drains & decrypts the latest PC-bound envelopes from [toPcQueue].
  List<Map<String, dynamic>> consumePcQueue() {
    final decoded = <Map<String, dynamic>>[];
    for (final msg in toPcQueue) {
      decoded.add(
        LumenRelayCrypto.openMailboxMap(
          kMailbox: kMailbox,
          room: pairing.room,
          to: LumenMailboxRole.pc,
          body: msg.bodyBytes,
        ),
      );
    }
    toPcQueue.clear();
    return decoded;
  }

  MockClient createHttpClient() => MockClient((request) async {
        final auth = request.headers['Authorization'];
        final join = request.headers['X-Lumen-Join'];
        if (auth != 'Bearer ${pairing.access}' || join != expectedJoinProof) {
          return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
        }
        if (revoked) {
          return http.Response(jsonEncode({'error': 'revoked'}), 410);
        }

        final segments = request.url.pathSegments;
        if (segments.length != 4 ||
            segments[0] != 'v1' ||
            segments[1] != 'mailbox' ||
            segments[2] != pairing.room) {
          return http.Response(jsonEncode({'error': 'not_found'}), 404);
        }

        final action = segments[3];
        if (request.method == 'POST' && action == 'messages') {
          postCount++;
          final to = request.url.queryParameters['to'];
          final msgId = request.headers['X-Lumen-Msg-Id'] ?? '';
          if (to != 'pc') {
            return http.Response(jsonEncode({'error': 'bad_role'}), 400);
          }
          if (seenPcMsgIds.contains(msgId)) {
            return http.Response(
              jsonEncode({'seq': _nextPcSeq, 'duplicate': true, 'id': msgId}),
              200,
            );
          }
          seenPcMsgIds.add(msgId);
          _nextPcSeq++;
          toPcQueue.add(
            _FakeMessage(
              seq: _nextPcSeq,
              msgId: msgId,
              createdAtMs: 1730000000000 + _nextPcSeq,
              bodyBytes: request.bodyBytes,
            ),
          );
          return http.Response(
            jsonEncode({'seq': _nextPcSeq, 'duplicate': false, 'id': msgId}),
            201,
          );
        }

        if (request.method == 'GET' && action == 'messages') {
          listCount++;
          final recipient = request.url.queryParameters['for'];
          final after = int.tryParse(request.url.queryParameters['after'] ?? '0') ?? 0;
          final limit = int.tryParse(request.url.queryParameters['limit'] ?? '100') ?? 100;
          if (recipient != 'phone') {
            return http.Response(jsonEncode({'error': 'bad_role'}), 400);
          }
          final matching =
              toPhoneQueue.where((m) => m.seq > after).take(limit).toList();
          return http.Response(
            jsonEncode({
              'messages': [
                for (final m in matching)
                  {
                    'seq': m.seq,
                    'id': m.msgId,
                    'createdAt': m.createdAtMs,
                    'sizeBytes': m.bodyBytes.length,
                    'payloadB64': base64Encode(m.bodyBytes),
                  },
              ],
              'latestSeq': _nextPhoneSeq,
              'pendingCount': toPhoneQueue.where((m) => m.seq > after).length,
            }),
            200,
          );
        }

        if (request.method == 'POST' && action == 'ack') {
          ackCount++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final upto = body['uptoSeq'] as int;
          final beforeLen = toPhoneQueue.length;
          toPhoneQueue.removeWhere((m) => m.seq <= upto);
          return http.Response(
            jsonEncode({
              'ackedUpto': upto,
              'deleted': beforeLen - toPhoneQueue.length,
              'remaining': toPhoneQueue.length,
            }),
            200,
          );
        }

        if (request.method == 'GET' && action == 'stats') {
          statsCount++;
          return http.Response(
            jsonEncode({
              'pendingPc': overridePendingPc ?? toPcQueue.length,
              'pendingPhone': toPhoneQueue.length,
              'storedBytes': 0,
              'revoked': false,
            }),
            200,
          );
        }

        return http.Response(jsonEncode({'error': 'unsupported'}), 404);
      });
}

LumenPairing _makeTestPairing({
  String roomSeed = 'room-alpha-123456',
  String keySeed = 'key-secret-0123456789abcdefghijk',
}) {
  String b64Bytes(String seed, int len) {
    final hash = sha256.convert(utf8.encode(seed)).bytes;
    return encodeBase64UrlNoPad(hash.take(len).toList());
  }

  final room = b64Bytes(roomSeed, LumenPairing.roomBytes);
  final key = b64Bytes(keySeed, LumenPairing.keyBytes);
  final access = b64Bytes('access-$roomSeed', LumenPairing.accessBytes);
  final fp = sha256.convert(utf8.encode(roomSeed)).toString();
  final uri = 'coucou://pair?v=1&host=192.168.1.42&port=4433&fp=$fp'
      '&token=pairingtoken123456&name=PC-Teste'
      '&relay=${Uri.encodeComponent('wss://relay.example.com')}'
      '&room=$room&key=$key&access=$access';
  return LumenPairing.parseUri(
    uri,
    now: DateTime.utc(2026, 11, 15, 10, 0),
  );
}

Map<String, dynamic> _pcEnvelope({
  required String mutationId,
  required String entityId,
  required int baseVersion,
  required int newVersion,
  required String updatedAt,
  required Map<String, dynamic> payload,
  String deviceId = 'dev-pc-01',
  int contractVersion = 1,
  String entityType = 'task',
}) =>
    {
      'contract_version': contractVersion,
      'mutation_id': mutationId,
      'device_id': deviceId,
      'origin_role': 'pc',
      'entity_type': entityType,
      'entity_id': entityId,
      'base_version': baseVersion,
      'new_version': newVersion,
      'updated_at': updatedAt,
      'payload': payload,
    };

Map<String, dynamic> _taskPayload({
  required String id,
  required String text,
  int version = 1,
  String due = '',
  String? dueDate,
  String? dueTime,
  int alertMinutes = 20,
  bool done = false,
  String? doneAt,
  String? deletedAt,
  String? snoozedUntil,
  String createdAt = '2026-11-15T08:00:00Z',
  List<Map<String, dynamic>> subtasks = const [],
  Map<String, dynamic>? recurrence,
  String? seriesId,
  Map<String, dynamic> extras = const {},
}) =>
    {
      'id': id,
      'text': text,
      'due': due,
      'due_date': dueDate,
      'due_time': dueTime,
      'time_zone': todoTimeZone,
      'alert_minutes': alertMinutes,
      'priority': 'normal',
      'subtasks': subtasks,
      'recurrence': recurrence,
      'series_id': seriesId,
      'done': done,
      'created_at': createdAt,
      'done_at': doneAt,
      'snoozed_until': snoozedUntil,
      'source': null,
      'source_stale': false,
      'version': version,
      'deleted_at': deletedAt,
      ...extras,
    };

class _FakeSyncAlarmBackend implements TodoAlarmBackend {
  final List<String> operations = [];
  final List<int> cancelledIds = [];
  final List<({int id, tz.TZDateTime scheduledDate, String payload})>
      scheduledCalls = [];
  final Map<int, PendingNotificationRequest> pending = {};
  final Map<int, ActiveNotification> active = {};

  @override
  bool get isSupported => true;

  @override
  Future<bool?> initialize({required TodoAlarmActionHandler onAction}) async =>
      true;

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async =>
          const NotificationAppLaunchDetails(false);

  @override
  Future<TodoAlarmStatus> readStatus({required String channelId}) async =>
      TodoAlarmStatus.ready;

  @override
  Future<bool?> areNotificationsEnabled() async => true;

  @override
  Future<bool?> openAppNotificationSettings() async => true;

  @override
  Future<bool?> requestNotificationsPermission() async => true;

  @override
  Future<bool?> requestExactAlarmsPermission() async => true;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      pending.values.toList(growable: false);

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async =>
      active.values.toList(growable: false);

  @override
  Future<void> cancel({required int id}) async {
    operations.add('cancel:$id');
    cancelledIds.add(id);
    pending.remove(id);
    active.remove(id);
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    required String payload,
  }) async {
    final utcIso = scheduledDate.toUtc().toIso8601String();
    operations.add('schedule:$id@$utcIso');
    scheduledCalls.add(
      (id: id, scheduledDate: scheduledDate, payload: payload),
    );
    pending[id] = PendingNotificationRequest(id, title, body, payload);
  }

  void simulateFiredNotification(int id, {bool keepInTray = true}) {
    final prior = pending.remove(id);
    if (keepInTray) {
      active[id] = ActiveNotification(
        id: id,
        channelId: 'todo_reminders',
        title: prior?.title ?? 'Lembrete',
        body: prior?.body ?? 'Tarefa',
      );
    }
  }

  void clearRecordedCalls() {
    operations.clear();
    cancelledIds.clear();
    scheduledCalls.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = 'u1';
  late Directory tempDir;
  late FileSystemService files;
  late _InMemorySecretStore secretStore;
  late LumenPairingService pairingService;
  late Future<TodoAlarmStatus> Function(List<TodoItem>) originalAlarmSync;
  late List<List<TodoItem>> recordedAlarmSyncs;
  late DateTime fakeNow;
  late int idCounter;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('todo_sync_test_');
    files = FileSystemService.detached(dataRoot: tempDir.path);
    secretStore = _InMemorySecretStore();
    fakeNow = DateTime.utc(2026, 11, 15, 12, 0, 0);
    idCounter = 0;
    pairingService = LumenPairingService(
      secretStore: secretStore,
      deviceIdGenerator: () => '11111111-1111-4111-8111-111111111111',
      now: () => fakeNow,
    );

    recordedAlarmSyncs = [];
    originalAlarmSync = TodoService.alarmSynchronizer;
    TodoService.alarmSynchronizer = (items) async {
      recordedAlarmSyncs.add(items);
      return TodoAlarmStatus.ready;
    };
  });

  tearDown(() async {
    await TodoService.waitForAlarmSync();
    TodoService.alarmSynchronizer = originalAlarmSync;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TodoSyncService createSync({
    LumenMailboxClient? mailboxClient,
    bool autoSyncEnabled = false,
  }) =>
      TodoSyncService(
        pairingService: pairingService,
        mailboxClient: mailboxClient,
        fileService: files,
        now: () {
          fakeNow = fakeNow.add(const Duration(seconds: 1));
          return fakeNow;
        },
        uuidGenerator: () {
          idCounter++;
          return 'mut-test-${idCounter.toString().padLeft(4, '0')}';
        },
        userIdResolver: () async => userId,
        autoSyncEnabled: autoSyncEnabled,
      );

  Future<void> savePairing(LumenPairing pairing) => secretStore.write(
        LumenPairingService.pairingStorageKey,
        jsonEncode(pairing.toJson()),
      );

  test('1. unpaired returns localOnly without making any network calls',
      () async {
    var networkCalls = 0;
    final mockClient = MockClient((request) async {
      networkCalls++;
      return http.Response('{}', 500);
    });
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: mockClient),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final created = await todos.add(userId: userId, text: 'Comprar café');
    final loaded = await sync.loadStatus(userId: userId);
    expect(loaded.state, TodoSyncBadgeState.localOnly);
    expect(loaded.paired, isFalse);
    expect(loaded.pendingOutbox, 0);
    expect(loaded.isItemSynced(created.id), isFalse);

    final synced = await sync.syncNow(userId: userId);
    expect(synced.state, TodoSyncBadgeState.localOnly);
    expect(synced.paired, isFalse);
    expect(networkCalls, 0);
  });

  test('2. paired offline mutations queue outbox and coalesce preserving base_version',
      () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
      autoSyncEnabled: false,
    );
    final todos = TodoService(fileService: files, syncService: sync);

    // Sync initial baseline task at version 1.
    final task = await todos.add(
      userId: userId,
      id: 'task-coalesce',
      text: 'Texto v1',
      due: '2026-11-16 09:00',
    );
    final firstSync = await sync.syncNow(userId: userId);
    expect(firstSync.state, TodoSyncBadgeState.waitingPc);
    relay.consumePcQueue();
    final afterPcRead = await sync.syncNow(userId: userId);
    expect(afterPcRead.state, TodoSyncBadgeState.synced);

    // Edit twice offline without pushing: outbox coalesces preserving base_version=1.
    await todos.edit(
      userId: userId,
      id: task.id,
      text: 'Texto v2',
      due: '2026-11-16 09:00',
    );
    await todos.edit(
      userId: userId,
      id: task.id,
      text: 'Texto v3',
      due: '2026-11-16 10:00',
    );

    // Also test recurring setDone, remove, restore, snooze offline.
    final recurring = await todos.add(
      userId: userId,
      id: 'task-rec',
      text: 'Água diária',
      due: '2026-11-15 09:00',
      recurrence: TodoRecurrence.daily(),
    );
    await todos.setDone(
      userId: userId,
      id: recurring.id,
      done: true,
      now: DateTime(2026, 11, 15, 9, 5),
    );
    await todos.snooze(
      userId: userId,
      id: task.id,
      now: DateTime(2026, 11, 16, 9, 50),
    );
    await todos.remove(userId: userId, id: task.id);
    await todos.restore(userId: userId, id: task.id);

    final statusOffline = await sync.loadStatus(userId: userId);
    expect(statusOffline.state, TodoSyncBadgeState.savedOnDevice);
    expect(statusOffline.pendingOutbox, 3); // task-coalesce, task-rec, nextOccurrence
    expect(statusOffline.isItemSynced(task.id), isFalse);

    final syncFile = File(p.join(files.getTodoPath(userId), todoSyncFileName));
    final syncFileRaw = await syncFile.readAsString();
    // Never persists raw room or pairing secrets on disk.
    expect(syncFileRaw.contains(pairing.room), isFalse);
    expect(syncFileRaw.contains(pairing.key), isFalse);
    expect(syncFileRaw.contains(pairing.access), isFalse);

    final syncJson = jsonDecode(syncFileRaw) as Map<String, dynamic>;
    final outboxList = (syncJson['outbox'] as List).cast<Map<String, dynamic>>();
    final coalEntry = outboxList.firstWhere(
      (e) => (e['envelope'] as Map)['entity_id'] == task.id,
    );
    final coalEnv = coalEntry['envelope'] as Map<String, dynamic>;
    expect(coalEnv['base_version'], 1);
    expect(coalEnv['new_version'], 6); // v1 -> v2 -> v3 -> snooze v4 -> remove v5 -> restore v6
    expect((coalEnv['payload'] as Map)['text'], 'Texto v3');
    expect((coalEnv['payload'] as Map)['deleted_at'], isNull);

    // Wire payload checks: reportDueUnknown -> due: ""
    final wireEmptyDue = SyncEnvelope.itemToWirePayload(
      const TodoItem(
        id: 't-due',
        text: 'Sem prazo',
        due: reportDueUnknown,
        done: false,
        createdAt: '2026-11-15T08:00:00Z',
      ),
      extraFields: {'custom_pc_tag': 'foco'},
    );
    expect(wireEmptyDue['due'], '');
    expect(wireEmptyDue['custom_pc_tag'], 'foco');
    expect(TodoItem.fromJson(wireEmptyDue).due, reportDueUnknown);
  });

  test('3. push -> pull -> ack -> stats pendingPc=0 before synced state', () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final localTask = await todos.add(userId: userId, text: 'Enviar contrato');
    // Remote sends another task simultaneously.
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-mut-001',
        entityId: 'pc-task-1',
        baseVersion: 0,
        newVersion: 1,
        updatedAt: '2026-11-15T12:05:00Z',
        payload: _taskPayload(
          id: 'pc-task-1',
          text: 'Revisar notas',
          due: '',
          extras: {'lumen_bucket': 'inbox'},
        ),
      ),
    );

    // Cycle 1: relay still has phone's pushed message queued for PC -> never synced!
    final firstStatus = await sync.syncNow(userId: userId);
    expect(firstStatus.pendingOutbox, 0);
    expect(firstStatus.pendingPc, 1);
    expect(firstStatus.state, isNot(TodoSyncBadgeState.synced));
    expect(firstStatus.state, TodoSyncBadgeState.waitingPc);
    expect(firstStatus.isItemSynced(localTask.id), isFalse);
    expect(relay.ackCount, 1);
    expect(relay.toPhoneQueue, isEmpty);

    // Verify remote task and unknown due/extra fields applied locally.
    final loadedTodos = await todos.load(userId);
    final pcTask = loadedTodos.firstWhere((t) => t.id == 'pc-task-1');
    expect(pcTask.due, reportDueUnknown);

    // Cycle 2: PC drained mailbox (pendingPc == 0) -> now truly synced!
    final sentToPc = relay.consumePcQueue();
    expect(sentToPc, hasLength(1));
    final secondStatus = await sync.syncNow(userId: userId);
    expect(secondStatus.state, TodoSyncBadgeState.synced);
    expect(secondStatus.pendingOutbox, 0);
    expect(secondStatus.pendingPc, 0);
    expect(secondStatus.isItemSynced(localTask.id), isTrue);
    expect(secondStatus.isItemSynced('pc-task-1'), isTrue);
  });

  test('4. T06 replay & remote recurring completion are idempotent without extra nextOccurrence',
      () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final rec = await todos.add(
      userId: userId,
      id: 'rec-parent',
      text: 'Backup diário',
      due: '2026-11-15 08:00',
      recurrence: TodoRecurrence.daily(),
    );
    await sync.syncNow(userId: userId);
    relay.consumePcQueue();

    // PC completes the recurring task (done: true) and delivers mutation twice.
    final pcComplete = _pcEnvelope(
      mutationId: 'pc-mut-rec-done',
      entityId: rec.id,
      baseVersion: 1,
      newVersion: 2,
      updatedAt: '2026-11-15T12:10:00Z',
      payload: _taskPayload(
        id: rec.id,
        text: 'Backup diário',
        due: '2026-11-15 08:00',
        dueDate: '2026-11-15',
        dueTime: '08:00',
        version: 2,
        done: true,
        doneAt: '2026-11-15T12:10:00Z',
        recurrence: TodoRecurrence.daily().toJson(),
        seriesId: rec.id,
      ),
    );
    relay.enqueueFromPcMap(pcComplete);
    await sync.syncNow(userId: userId);

    // Re-deliver same mutation_id as replay -> must not duplicate or synthesize nextOccurrence.
    relay.enqueueFromPcMap(pcComplete);
    await sync.syncNow(userId: userId);

    final items = await todos.load(userId);
    expect(items.where((t) => t.seriesId == rec.id), hasLength(1));
    expect(items.single.done, isTrue);
    expect(items.single.version, 2);
  });

  test('5. T08 offline tombstone beats concurrent remote edit', () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final task = await todos.add(
      userId: userId,
      id: 'task-tombstone',
      text: 'Inicial',
    );
    await sync.syncNow(userId: userId);
    relay.consumePcQueue();

    // Phone deletes locally offline (creates tombstone, queued as base=1 -> v=2).
    // Wait: prevent push first by simulating PC already sent an edit at base=1 -> v=2
    // BEFORE phone synced, OR edit relay offline flag:
    // Here we queue PC edit BEFORE sync while offline phone also deletes.
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-edit-before-tombstone-push',
        entityId: task.id,
        baseVersion: 1,
        newVersion: 2,
        updatedAt: '2026-11-15T12:30:00Z', // later timestamp than phone delete!
        payload: _taskPayload(
          id: task.id,
          text: 'Editado no PC',
          version: 2,
        ),
      ),
    );
    await todos.remove(userId: userId, id: task.id);

    await sync.syncNow(userId: userId);
    final allItems = await todos.load(userId, includeDeleted: true);
    final merged = allItems.singleWhere((t) => t.id == task.id);
    expect(merged.isTombstoned, isTrue);
    expect(merged.deletedAt, isNotNull);
    expect(await todos.load(userId), isEmpty);

    // Converged tombstone was also pushed back to PC.
    final pcMessages = relay.consumePcQueue();
    expect(pcMessages.last['payload']['deleted_at'], isNotNull);
  });

  test('6. concurrent text edits create pending_review conflict and resolveConflict resolves it',
      () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final task = await todos.add(
      userId: userId,
      id: 'task-conflict',
      text: 'Base original',
      subtasks: const [TodoSubtask(id: 'sub-1', text: 'Passo base')],
    );
    await sync.syncNow(userId: userId);
    relay.consumePcQueue();

    // Concurrent edit on phone and PC (PC timestamp newer -> provisional winner is remote).
    await todos.edit(
      userId: userId,
      id: task.id,
      text: 'Edição do celular',
      due: reportDueUnknown,
      subtasks: const [TodoSubtask(id: 'sub-1', text: 'Passo celular')],
    );
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-text-conflict-1',
        entityId: task.id,
        baseVersion: 1,
        newVersion: 2,
        updatedAt: '2026-11-15T13:00:00Z',
        payload: _taskPayload(
          id: task.id,
          text: 'Edição do PC',
          version: 2,
          subtasks: [
            {'id': 'sub-1', 'text': 'Passo PC', 'done': false},
          ],
        ),
      ),
    );

    final afterConflict = await sync.syncNow(userId: userId);
    expect(afterConflict.conflicts, hasLength(2));
    final textConflict =
        afterConflict.conflicts.firstWhere((c) => c.field == 'text');
    expect(textConflict.id, 'task-conflict:text');
    expect(textConflict.localText, 'Edição do celular');
    expect(textConflict.remoteText, 'Edição do PC');
    expect(textConflict.winnerSide, 'remote');
    expect(textConflict.conflictState, 'pending_review');

    final subConflict = afterConflict.conflicts
        .firstWhere((c) => c.field == 'subtasks.sub-1.text');
    expect(subConflict.id, 'task-conflict:subtasks.sub-1.text');

    relay.consumePcQueue();

    // User resolves main text keeping local, and subtask keeping remote.
    final resolved1 = await sync.resolveConflict(
      userId: userId,
      conflictId: 'task-conflict:text',
      keepLocal: true,
    );
    expect(resolved1.conflicts, hasLength(1));

    final resolved2 = await sync.resolveConflict(
      userId: userId,
      conflictId: 'task-conflict:subtasks.sub-1.text',
      keepLocal: false,
    );
    expect(resolved2.conflicts, isEmpty);

    final finalTask = (await todos.load(userId)).single;
    expect(finalTask.text, 'Edição do celular');
    expect(finalTask.subtasks.single.text, 'Passo PC');

    final pushed = relay.consumePcQueue();
    expect(pushed, isNotEmpty);
    expect(pushed.last['payload']['text'], 'Edição do celular');
    expect(pushed.last['payload']['subtasks'][0]['text'], 'Passo PC');
  });

  test('7. quarantines unknown entities/versions and drops poison after 3 failed pulls',
      () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    // 1) Unknown entity_type -> quarantined + acked.
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-note-1',
        entityId: 'note-1',
        baseVersion: 0,
        newVersion: 1,
        updatedAt: '2026-11-15T12:00:00Z',
        entityType: 'note',
        payload: {'id': 'note-1', 'title': 'Nota do PC'},
      ),
    );
    // 2) Future contract version -> quarantined + acked.
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-v2-task',
        entityId: 'future-1',
        baseVersion: 0,
        newVersion: 1,
        updatedAt: '2026-11-15T12:00:01Z',
        contractVersion: 2,
        payload: {'id': 'future-1', 'text': 'Futuro'},
      ),
    );
    // 3) Unreadable corrupted ciphertext -> retried 3 times, then poisonCount=1 + acked.
    final poisonSeq = relay.enqueueRawBytesToPhone(
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]),
      msgId: 'bad-cipher',
    );
    // 4) Valid task behind the poison seq -> delivered cleanly once poison is acked on try 3!
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-after-poison',
        entityId: 'valid-after-poison',
        baseVersion: 0,
        newVersion: 1,
        updatedAt: '2026-11-15T12:00:02Z',
        payload: _taskPayload(id: 'valid-after-poison', text: 'Destravada'),
      ),
    );

    // Attempt 1: seq 1 & 2 quarantined and acked; stops before seq 3; seq 4 still waiting.
    final attempt1 = await sync.syncNow(userId: userId);
    expect(attempt1.quarantinedCount, 2);
    expect(attempt1.poisonCount, 0);
    expect(attempt1.state, TodoSyncBadgeState.error);
    expect(await todos.load(userId), isEmpty);
    expect(relay.toPhoneQueue.first.seq, poisonSeq);

    // Attempt 2: still retrying poison.
    final attempt2 = await sync.syncNow(userId: userId);
    expect(attempt2.poisonCount, 0);
    expect(await todos.load(userId), isEmpty);

    // Attempt 3: 3rd attempt quarantines/drops poison, acks poisonSeq, and applies seq 4!
    final attempt3 = await sync.syncNow(userId: userId);
    expect(attempt3.poisonCount, 1);
    expect(attempt3.quarantinedCount, 2);
    expect(attempt3.state, TodoSyncBadgeState.synced);
    expect(relay.toPhoneQueue, isEmpty);
    final items = await todos.load(userId);
    expect(items.map((t) => t.id), ['valid-after-poison']);
  });

  test('8. HTTP 410 sets revoked without losing local tasks or pending outbox',
      () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final keptTask = await todos.add(userId: userId, text: 'Não perder');
    relay.revoked = true;

    final status = await sync.syncNow(userId: userId);
    expect(status.revoked, isTrue);
    expect(status.state, TodoSyncBadgeState.revoked);
    expect(status.pendingOutbox, 1);
    expect(status.isItemSynced(keptTask.id), isFalse);

    final localTasks = await todos.load(userId);
    expect(localTasks.map((t) => t.id), [keptTask.id]);
  });

  test('8b. network failure (status 0) is offline and keeps local tasks pending',
      () async {
    final pairing = _makeTestPairing(roomSeed: 'room-offline');
    await savePairing(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(
        httpClient: MockClient((request) async {
          throw const SocketException('offline');
        }),
      ),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final task = await todos.add(userId: userId, text: 'Sem rede');
    final before = await sync.loadStatus(userId: userId);
    expect(before.pendingOutbox, greaterThan(0));

    final status = await sync.syncNow(userId: userId);
    expect(status.state, TodoSyncBadgeState.offline);
    expect(status.lastError, 'http_0');
    expect(status.pendingOutbox, before.pendingOutbox);
    expect(status.isItemSynced(task.id), isFalse);
    expect((await todos.load(userId)).map((t) => t.id), [task.id]);
  });

  test('8c. HTTP 500 stays error, not offline', () async {
    final pairing = _makeTestPairing(roomSeed: 'room-http-500');
    await savePairing(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(
        httpClient: MockClient((request) async => http.Response('{}', 500)),
      ),
    );
    final todos = TodoService(fileService: files, syncService: sync);
    await todos.add(userId: userId, text: 'Erro do servidor');

    final status = await sync.syncNow(userId: userId);
    expect(status.state, TodoSyncBadgeState.error);
    expect(status.lastError, 'http_500');
  });

  test('8d. syncNow logs one info line with reason and state, never task text',
      () async {
    final pairing = _makeTestPairing(roomSeed: 'room-sync-log');
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);
    await todos.add(userId: userId, text: 'Título secreto do log');

    final records = <LogRecord>[];
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    final TodoSyncStatus status;
    try {
      status = await sync.syncNow(userId: userId, reason: 'manual');
    } finally {
      await subscription.cancel();
      Logger.root.level = previousLevel;
    }

    final syncLines = records
        .where((r) => r.loggerName == 'TodoSyncService' && r.level == Level.INFO)
        .map((r) => r.message)
        .toList();
    expect(syncLines, [
      'Todo sync (manual) -> ${status.state.name}, '
          'outbox=${status.pendingOutbox}, error=${status.lastError}',
    ]);
    expect(
      records.any((r) =>
          r.message.contains('Título secreto do log') ||
          (r.error?.toString().contains('Título secreto do log') ?? false)),
      isFalse,
    );
  });

  test('9. remote done, remove, and snooze trigger TodoService.alarmSynchronizer',
      () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);

    final t1 = await todos.add(
      userId: userId,
      id: 'alarm-task-1',
      text: 'Tomar remédio',
      due: '2026-11-16 09:00',
    );
    await sync.syncNow(userId: userId);
    relay.consumePcQueue();
    await TodoService.waitForAlarmSync();
    recordedAlarmSyncs.clear();

    // Remote snooze
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-snooze-1',
        entityId: t1.id,
        baseVersion: 1,
        newVersion: 2,
        updatedAt: '2026-11-15T12:10:00Z',
        payload: _taskPayload(
          id: t1.id,
          text: t1.text,
          due: t1.due,
          dueDate: t1.dueDate,
          dueTime: t1.dueTime,
          version: 2,
          snoozedUntil: '2026-11-16T09:10:00Z',
        ),
      ),
    );
    await sync.syncNow(userId: userId);
    await TodoService.waitForAlarmSync();
    expect(recordedAlarmSyncs, hasLength(1));
    expect(
      recordedAlarmSyncs.single.single.snoozedUntil,
      '2026-11-16T09:10:00Z',
    );

    // Remote complete
    recordedAlarmSyncs.clear();
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-done-1',
        entityId: t1.id,
        baseVersion: 2,
        newVersion: 3,
        updatedAt: '2026-11-15T12:15:00Z',
        payload: _taskPayload(
          id: t1.id,
          text: t1.text,
          due: t1.due,
          dueDate: t1.dueDate,
          dueTime: t1.dueTime,
          version: 3,
          done: true,
          doneAt: '2026-11-15T12:15:00Z',
        ),
      ),
    );
    await sync.syncNow(userId: userId);
    await TodoService.waitForAlarmSync();
    expect(recordedAlarmSyncs, hasLength(1));
    expect(recordedAlarmSyncs.single.single.done, isTrue);

    // Remote remove (tombstone)
    recordedAlarmSyncs.clear();
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-remove-1',
        entityId: t1.id,
        baseVersion: 3,
        newVersion: 4,
        updatedAt: '2026-11-15T12:20:00Z',
        payload: _taskPayload(
          id: t1.id,
          text: t1.text,
          due: t1.due,
          dueDate: t1.dueDate,
          dueTime: t1.dueTime,
          version: 4,
          done: true,
          doneAt: '2026-11-15T12:15:00Z',
          deletedAt: '2026-11-15T12:20:00Z',
        ),
      ),
    );
    await sync.syncNow(userId: userId);
    await TodoService.waitForAlarmSync();
    expect(recordedAlarmSyncs, hasLength(1));
    expect(recordedAlarmSyncs.single.single.isTombstoned, isTrue);
  });

  test('photos stay on this phone: the wire payload has no attachments', () {
    final item = const TodoItem(
      id: 'photo-task-0',
      text: 'Conferir o recibo',
      due: reportDueUnknown,
      done: false,
      createdAt: '2026-11-15T09:00:00.000',
      attachments: const ['fs://recibo_20261115.jpg'],
    );

    final payload = SyncEnvelope.itemToWirePayload(item);

    expect(payload.containsKey('attachments'), isFalse);
    expect(payload['text'], 'Conferir o recibo');
    expect(item.toJson()['attachments'], ['fs://recibo_20261115.jpg']);
  });

  test('a remote update keeps the photos this phone already has', () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);
    final task = await todos.add(
      userId: userId,
      id: 'photo-task-1',
      text: 'Recibo do almoço',
      due: '2026-11-16 09:00',
      attachments: const ['fs://almoco_20261116.jpg'],
    );
    await sync.syncNow(userId: userId);
    relay.consumePcQueue();

    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-snooze-photo-1',
        entityId: task.id,
        baseVersion: 1,
        newVersion: 2,
        updatedAt: '2026-11-15T12:10:00Z',
        payload: _taskPayload(
          id: task.id,
          text: task.text,
          due: task.due,
          dueDate: task.dueDate,
          dueTime: task.dueTime,
          version: 2,
          snoozedUntil: '2026-11-16T09:10:00Z',
        ),
      ),
    );
    await sync.syncNow(userId: userId);

    final stored = (await todos.load(userId)).single;
    expect(stored.snoozedUntil, '2026-11-16T09:10:00Z');
    expect(stored.attachments, ['fs://almoco_20261116.jpg']);
  });

  test('a remote update racing a local photo change keeps both photo sets',
      () async {
    final pairing = _makeTestPairing();
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);
    final task = await todos.add(
      userId: userId,
      id: 'photo-task-2',
      text: 'Fotos da obra',
      due: '2026-11-16 09:00',
      attachments: const ['fs://obra_1.jpg'],
    );
    await sync.syncNow(userId: userId);
    relay.consumePcQueue();

    // Local photo added and not synced yet: version 2 waits in the outbox.
    await todos.edit(
      userId: userId,
      id: task.id,
      text: task.text,
      due: task.due,
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      attachments: const ['fs://obra_1.jpg', 'fs://obra_2.jpg'],
    );
    relay.enqueueFromPcMap(
      _pcEnvelope(
        mutationId: 'pc-snooze-photo-2',
        entityId: task.id,
        baseVersion: 1,
        newVersion: 2,
        updatedAt: '2026-11-15T12:10:00Z',
        payload: _taskPayload(
          id: task.id,
          text: task.text,
          due: task.due,
          dueDate: task.dueDate,
          dueTime: task.dueTime,
          version: 2,
          snoozedUntil: '2026-11-16T09:10:00Z',
        ),
      ),
    );
    await sync.syncNow(userId: userId);

    final stored = (await todos.load(userId)).single;
    expect(stored.attachments, ['fs://obra_1.jpg', 'fs://obra_2.jpg']);
  });

  test('10. reconcileThreeWay symmetric rules & pagination over 100 messages',
      () async {
    // Direct reconcileThreeWay checks: tie-break by deviceId, done earlier, snooze later.
    const base = TodoItem(
      id: 't-3way',
      text: 'Base',
      due: reportDueUnknown,
      done: false,
      createdAt: '2026-11-15T08:00:00Z',
      snoozedUntil: '2026-11-15T10:00:00Z',
    );
    final local = base.copyWith(
      text: 'Local edit',
      snoozedUntil: '2026-11-15T10:30:00Z',
      version: 2,
    );
    final remote = base.copyWith(
      text: 'Remote edit',
      done: true,
      doneAt: '2026-11-15T09:45:00Z',
      snoozedUntil: '2026-11-15T11:00:00Z',
      version: 2,
    );

    final merged = TodoSyncService.reconcileThreeWay(
      base: base,
      local: local,
      localExtras: const {'pc_only_a': 1},
      localUpdatedAt: '2026-11-15T12:00:00Z',
      localDeviceId: 'dev-a',
      remote: remote,
      remoteExtras: const {'pc_only_b': 2},
      remoteUpdatedAt: '2026-11-15T12:00:00Z',
      remoteDeviceId: 'dev-z', // ties timestamp; 'dev-z' > 'dev-a' -> remote wins
      remoteNewVersion: 2,
    );

    expect(merged.item.text, 'Remote edit');
    expect(merged.item.done, isTrue);
    expect(merged.item.doneAt, '2026-11-15T09:45:00Z');
    expect(merged.item.snoozedUntil, '2026-11-15T11:00:00Z');
    expect(merged.item.version, 3);
    expect(merged.conflicts.single.winnerSide, 'remote');
    expect(merged.extraFields, {'pc_only_a': 1, 'pc_only_b': 2});
    expect(merged.divergesFromRemote, isTrue);

    // Pagination (> 100 messages) in one syncNow.
    final pairing = _makeTestPairing(roomSeed: 'room-pagination-123');
    await savePairing(pairing);
    final relay = _FakeRelayMailbox(pairing);
    for (var i = 1; i <= 105; i++) {
      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-page-mut-$i',
          entityId: 'page-task-$i',
          baseVersion: 0,
          newVersion: 1,
          updatedAt: '2026-11-15T12:00:00Z',
          payload: _taskPayload(id: 'page-task-$i', text: 'Item $i'),
        ),
      );
    }
    final sync = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: sync);
    final result = await sync.syncNow(userId: userId);
    expect(result.state, TodoSyncBadgeState.synced);
    expect(relay.listCount, greaterThanOrEqualTo(2));
    expect(relay.toPhoneQueue, isEmpty);
    expect(await todos.load(userId), hasLength(105));
  });

  test('11. switching room resets cursor and snapshots active tasks + <90d tombstones',
      () async {
    final pairingA = _makeTestPairing(roomSeed: 'room-switch-A');
    await savePairing(pairingA);
    final relayA = _FakeRelayMailbox(pairingA);
    final syncA = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relayA.createHttpClient()),
    );
    final todos = TodoService(fileService: files, syncService: syncA);

    await todos.add(userId: userId, id: 'keep-me', text: 'Ativa');
    final recentDel =
        await todos.add(userId: userId, id: 'del-recent', text: 'Recent delete');
    await todos.remove(userId: userId, id: recentDel.id);

    // Sync on room A first.
    await syncA.syncNow(userId: userId);
    relayA.consumePcQueue();
    await syncA.syncNow(userId: userId);

    // Inject an expired (>90 days) tombstone directly in storage to ensure pruning on snapshot.
    final v2File = File(files.getTodoV2FilePath(userId));
    final v2Json = jsonDecode(await v2File.readAsString()) as Map<String, dynamic>;
    final list = (v2Json['items'] as List).cast<Map<String, dynamic>>();
    list.add(
      const TodoItem(
        id: 'del-old',
        text: 'Tombstone expirada',
        due: reportDueUnknown,
        done: false,
        createdAt: '2026-01-01T00:00:00Z',
        deletedAt: '2026-01-02T00:00:00Z',
      ).toJson(),
    );
    await v2File.writeAsString(jsonEncode(v2Json));

    // Switch pairing to room B.
    final pairingB = _makeTestPairing(roomSeed: 'room-switch-B');
    await savePairing(pairingB);
    final relayB = _FakeRelayMailbox(pairingB);
    final syncB = createSync(
      mailboxClient: LumenMailboxClient(httpClient: relayB.createHttpClient()),
    );

    final statusB = await syncB.syncNow(userId: userId);
    expect(statusB.state, TodoSyncBadgeState.waitingPc);
    final pushedToB = relayB.consumePcQueue();
    final pushedIds = {for (final e in pushedToB) e['entity_id']};
    expect(pushedIds, {'keep-me', 'del-recent'});
    expect(pushedIds.contains('del-old'), isFalse);
  });

  group('F12-05 alarm sync integration (AC-08 & T05)', () {
    late _FakeSyncAlarmBackend alarmBackend;
    late TodoAlarmService alarmService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'language': 'pt'});
      await UserStorage.initL10n();
      alarmBackend = _FakeSyncAlarmBackend();
      alarmService = TodoAlarmService.forTesting(
        backend: alarmBackend,
        now: () => fakeNow,
      );
      TodoService.alarmSynchronizer = alarmService.synchronize;
    });

    test(
        '12. AC-08: task from PC schedules exact alarm at due - alertMinutes and replay is idempotent',
        () async {
      final pairing = _makeTestPairing(roomSeed: 'room-alarm-ac08');
      await savePairing(pairing);
      final relay = _FakeRelayMailbox(pairing);
      final sync = createSync(
        mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
      );
      final todos = TodoService(fileService: files, syncService: sync);

      final envelope = _pcEnvelope(
        mutationId: 'pc-alarm-create-1',
        entityId: 'pc-alarm-1',
        baseVersion: 0,
        newVersion: 1,
        updatedAt: '2026-11-15T12:05:00Z',
        payload: _taskPayload(
          id: 'pc-alarm-1',
          text: 'Entregar parecer',
          due: '2026-11-16 09:00',
          dueDate: '2026-11-16',
          dueTime: '09:00',
          alertMinutes: 20,
        ),
      );
      relay.enqueueFromPcMap(envelope);

      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      final loaded = await todos.load(userId);
      expect(loaded.map((t) => t.id), ['pc-alarm-1']);
      expect(alarmBackend.cancelledIds, isEmpty);
      expect(alarmBackend.scheduledCalls, hasLength(1));
      final scheduled = alarmBackend.scheduledCalls.single;
      expect(scheduled.payload, 'todoAlarm:pc-alarm-1');
      // 09:00 America/Sao_Paulo (UTC-3) - 20 min = 08:40 BRT = 11:40 UTC.
      expect(
        scheduled.scheduledDate.toUtc(),
        DateTime.utc(2026, 11, 16, 11, 40),
      );

      // Re-deliver the exact same mutation_id (replay): no duplicate task or reschedule.
      alarmBackend.clearRecordedCalls();
      relay.enqueueFromPcMap(envelope);
      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      expect(await todos.load(userId), hasLength(1));
      expect(alarmBackend.scheduledCalls, isEmpty);
      expect(alarmBackend.cancelledIds, isEmpty);
      expect(alarmBackend.pending.keys, [scheduled.id]);
    });

    test(
        '13. AC-08: remote done or delete cancels fired alarm even without pendingNotificationRequests',
        () async {
      final pairing = _makeTestPairing(roomSeed: 'room-alarm-cancel');
      await savePairing(pairing);
      final relay = _FakeRelayMailbox(pairing);
      final sync = createSync(
        mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
      );
      final todos = TodoService(fileService: files, syncService: sync);

      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-create-done',
          entityId: 'pc-done-task',
          baseVersion: 0,
          newVersion: 1,
          updatedAt: '2026-11-15T12:01:00Z',
          payload: _taskPayload(
            id: 'pc-done-task',
            text: 'Concluir no PC',
            due: '2026-11-16 09:00',
            dueDate: '2026-11-16',
            dueTime: '09:00',
          ),
        ),
      );
      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-create-del',
          entityId: 'pc-del-task',
          baseVersion: 0,
          newVersion: 1,
          updatedAt: '2026-11-15T12:01:05Z',
          payload: _taskPayload(
            id: 'pc-del-task',
            text: 'Excluir no PC',
            due: '2026-11-16 10:00',
            dueDate: '2026-11-16',
            dueTime: '10:00',
          ),
        ),
      );
      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      final doneAlarmId = alarmBackend.scheduledCalls
          .firstWhere((c) => c.payload == 'todoAlarm:pc-done-task')
          .id;
      final delAlarmId = alarmBackend.scheduledCalls
          .firstWhere((c) => c.payload == 'todoAlarm:pc-del-task')
          .id;

      // Both alarms already fired on Android: neither is pending anymore.
      alarmBackend.simulateFiredNotification(doneAlarmId, keepInTray: false);
      alarmBackend.simulateFiredNotification(delAlarmId, keepInTray: true);
      expect(alarmBackend.pending, isEmpty);
      alarmBackend.clearRecordedCalls();

      // PC completes one and deletes the other.
      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-complete-1',
          entityId: 'pc-done-task',
          baseVersion: 1,
          newVersion: 2,
          updatedAt: '2026-11-15T12:10:00Z',
          payload: _taskPayload(
            id: 'pc-done-task',
            text: 'Concluir no PC',
            due: '2026-11-16 09:00',
            dueDate: '2026-11-16',
            dueTime: '09:00',
            version: 2,
            done: true,
            doneAt: '2026-11-15T12:10:00Z',
          ),
        ),
      );
      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-delete-1',
          entityId: 'pc-del-task',
          baseVersion: 1,
          newVersion: 2,
          updatedAt: '2026-11-15T12:11:00Z',
          payload: _taskPayload(
            id: 'pc-del-task',
            text: 'Excluir no PC',
            due: '2026-11-16 10:00',
            dueDate: '2026-11-16',
            dueTime: '10:00',
            version: 2,
            deletedAt: '2026-11-15T12:11:00Z',
          ),
        ),
      );

      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      expect(alarmBackend.scheduledCalls, isEmpty);
      expect(alarmBackend.cancelledIds, containsAll([doneAlarmId, delAlarmId]));
      expect(alarmBackend.active, isEmpty);
      expect(alarmBackend.pending, isEmpty);

      final remaining = await todos.load(userId);
      expect(remaining.single.id, 'pc-done-task');
      expect(remaining.single.done, isTrue);
    });

    test(
        '14. T05: remote snooze from PC cancels prior notification and reschedules new instant',
        () async {
      final pairing = _makeTestPairing(roomSeed: 'room-alarm-remote-snooze');
      await savePairing(pairing);
      final relay = _FakeRelayMailbox(pairing);
      final sync = createSync(
        mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
      );
      final todos = TodoService(fileService: files, syncService: sync);

      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-create-snooze',
          entityId: 'pc-snooze-task',
          baseVersion: 0,
          newVersion: 1,
          updatedAt: '2026-11-15T12:01:00Z',
          payload: _taskPayload(
            id: 'pc-snooze-task',
            text: 'Ligar para fornecedor',
            due: '2026-11-16 09:00',
            dueDate: '2026-11-16',
            dueTime: '09:00',
          ),
        ),
      );
      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      final alarmId = alarmBackend.scheduledCalls.single.id;
      alarmBackend.simulateFiredNotification(alarmId, keepInTray: true);
      alarmBackend.clearRecordedCalls();

      const snoozeIso = '2026-11-15T12:30:00.000Z';
      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-snooze-update',
          entityId: 'pc-snooze-task',
          baseVersion: 1,
          newVersion: 2,
          updatedAt: '2026-11-15T12:05:00Z',
          payload: _taskPayload(
            id: 'pc-snooze-task',
            text: 'Ligar para fornecedor',
            due: '2026-11-16 09:00',
            dueDate: '2026-11-16',
            dueTime: '09:00',
            version: 2,
            snoozedUntil: snoozeIso,
          ),
        ),
      );

      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      expect(alarmBackend.cancelledIds, [alarmId]);
      expect(alarmBackend.active, isEmpty);
      expect(alarmBackend.scheduledCalls, hasLength(1));
      expect(
        alarmBackend.scheduledCalls.single.scheduledDate.toUtc(),
        DateTime.utc(2026, 11, 15, 12, 30),
      );
      expect(
        alarmBackend.operations,
        ['cancel:$alarmId', 'schedule:$alarmId@$snoozeIso'],
      );
      expect((await todos.load(userId)).single.snoozedUntil, snoozeIso);
    });

    test(
        '15. local snooze and completion trigger alarmSynchronizer and queue outbox envelopes for PC',
        () async {
      final pairing = _makeTestPairing(roomSeed: 'room-alarm-local-ops');
      await savePairing(pairing);
      final relay = _FakeRelayMailbox(pairing);
      final sync = createSync(
        mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
      );
      final todos = TodoService(fileService: files, syncService: sync);

      final task = await todos.add(
        userId: userId,
        id: 'phone-alarm-1',
        text: 'Enviar relatório semanal',
        due: '2026-11-16 09:00',
        now: fakeNow,
      );
      await sync.syncNow(userId: userId);
      relay.consumePcQueue();
      await TodoService.waitForAlarmSync();

      // Creating the first todo triggers legacy migration + add writes, which
      // may run alarmSynchronizer twice idempotently before settling on one alarm.
      expect(alarmBackend.pending, hasLength(1));
      final alarmId = alarmBackend.pending.values.single.id;
      expect(alarmBackend.scheduledCalls, isNotEmpty);
      expect(alarmBackend.scheduledCalls.every((c) => c.id == alarmId), isTrue);
      alarmBackend.simulateFiredNotification(alarmId, keepInTray: true);
      alarmBackend.clearRecordedCalls();

      // Local snooze cancels prior tray notification, reschedules locally, and queues outbox.
      final snoozeBase = fakeNow;
      final expectedSnoozeUtc =
          snoozeBase.toUtc().add(const Duration(minutes: todoAlarmSnoozeMinutes));
      await todos.snooze(userId: userId, id: task.id, now: snoozeBase);
      await TodoService.waitForAlarmSync();

      expect(
        alarmBackend.operations,
        [
          'cancel:$alarmId',
          'schedule:$alarmId@${expectedSnoozeUtc.toIso8601String()}',
        ],
      );
      expect((await sync.loadStatus(userId: userId)).pendingOutbox, 1);

      await sync.syncNow(userId: userId);
      final snoozePushed = relay.consumePcQueue();
      expect(snoozePushed, hasLength(1));
      expect(snoozePushed.single['entity_id'], task.id);
      expect(
        snoozePushed.single['payload']['snoozed_until'],
        expectedSnoozeUtc.toIso8601String(),
      );

      // Local completion cancels fired alarm locally even with empty pending queue and queues outbox.
      alarmBackend.simulateFiredNotification(alarmId, keepInTray: false);
      alarmBackend.clearRecordedCalls();

      await todos.setDone(
        userId: userId,
        id: task.id,
        done: true,
        now: fakeNow,
      );
      await TodoService.waitForAlarmSync();

      expect(alarmBackend.cancelledIds, [alarmId]);
      expect(alarmBackend.scheduledCalls, isEmpty);
      expect((await sync.loadStatus(userId: userId)).pendingOutbox, 1);

      await sync.syncNow(userId: userId);
      final donePushed = relay.consumePcQueue();
      expect(donePushed, hasLength(1));
      expect(donePushed.single['entity_id'], task.id);
      expect(donePushed.single['payload']['done'], isTrue);
    });

    test(
        '16. T05: remote reschedule (dueDate/dueTime/alertMinutes) from PC cancels prior notification and reschedules new alarm',
        () async {
      final pairing =
          _makeTestPairing(roomSeed: 'room-alarm-remote-reschedule');
      await savePairing(pairing);
      final relay = _FakeRelayMailbox(pairing);
      final sync = createSync(
        mailboxClient: LumenMailboxClient(httpClient: relay.createHttpClient()),
      );
      final todos = TodoService(fileService: files, syncService: sync);

      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-resched-init',
          entityId: 'pc-resched-task',
          baseVersion: 0,
          newVersion: 1,
          updatedAt: '2026-11-15T12:00:00Z',
          payload: _taskPayload(
            id: 'pc-resched-task',
            text: 'Revisar contrato',
            due: '2026-11-16 09:00',
            dueDate: '2026-11-16',
            dueTime: '09:00',
            alertMinutes: 20,
          ),
        ),
      );
      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      final alarmId = alarmBackend.scheduledCalls.single.id;
      alarmBackend.simulateFiredNotification(alarmId, keepInTray: true);
      alarmBackend.clearRecordedCalls();

      // PC updates dueTime to 15:00 and alertMinutes to 30.
      relay.enqueueFromPcMap(
        _pcEnvelope(
          mutationId: 'pc-resched-update',
          entityId: 'pc-resched-task',
          baseVersion: 1,
          newVersion: 2,
          updatedAt: '2026-11-15T12:05:00Z',
          payload: _taskPayload(
            id: 'pc-resched-task',
            text: 'Revisar contrato',
            due: '2026-11-16 15:00',
            dueDate: '2026-11-16',
            dueTime: '15:00',
            alertMinutes: 30,
            version: 2,
          ),
        ),
      );

      await sync.syncNow(userId: userId);
      await TodoService.waitForAlarmSync();

      expect(alarmBackend.cancelledIds, [alarmId]);
      expect(alarmBackend.active, isEmpty);
      expect(alarmBackend.scheduledCalls, hasLength(1));
      // 15:00 BRT - 30 min = 14:30 BRT = 17:30 UTC
      expect(
        alarmBackend.scheduledCalls.single.scheduledDate.toUtc(),
        DateTime.utc(2026, 11, 16, 17, 30),
      );
      expect(
        alarmBackend.operations,
        ['cancel:$alarmId', 'schedule:$alarmId@2026-11-16T17:30:00.000Z'],
      );
      final loaded = (await todos.load(userId)).single;
      expect(loaded.dueTime, '15:00');
      expect(loaded.alertMinutes, 30);
    });
  });
}
