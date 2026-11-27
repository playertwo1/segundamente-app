import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_task_sync.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';

import 'fake_esp32_mqtt_transport.dart';

const String _userId = 'sync-user';
final Esp32RoomCrypto _crypto = Esp32RoomCrypto(kFakeRoomKey);
const String _taskPrefix = 'sm/$kFakeRoom/tarefas/';

class MemoryEsp32TaskMetaStore implements Esp32TaskMetaStore {
  final Map<String, Esp32TaskMeta> data = <String, Esp32TaskMeta>{};

  @override
  Future<Map<String, Esp32TaskMeta>> load() async => Map.of(data);

  @override
  Future<void> save(Map<String, Esp32TaskMeta> metas) async {
    data
      ..clear()
      ..addAll(metas);
  }
}

int sec(DateTime moment) => moment.millisecondsSinceEpoch ~/ 1000;

int dueSec(int y, int m, int d, int h, int min) =>
    DateTime(y, m, d, h, min).millisecondsSinceEpoch ~/ 1000;

/// Envelope text as the board would seal it (`from: placa`).
Uint8List boardPayload(String plaintext) => Uint8List.fromList(
      utf8.encode(_crypto.seal(from: kEsp32FromBoard, plaintext: plaintext)),
    );

String remoteJson({
  required String id,
  required int updatedAt,
  required String text,
  bool done = false,
  int dueTs = 0,
}) =>
    jsonEncode({
      'contract_version': 1,
      'entity_type': 'todo',
      'entity_id': id,
      'origin_role': 'esp32',
      'updated_at': updatedAt,
      'new_version': 1,
      'payload': {'id': id, 'text': text, 'done': done, 'due_ts': dueTs},
    });

/// Reads a phone publish as the board would (the board is "self" here).
String openPlain(FakePublishCall call) =>
    _crypto.open(call.text, self: kEsp32FromBoard).plaintext!;

void main() {
  final originalAlarmSync = TodoService.alarmSynchronizer;
  final originalWidgetSync = TodoService.widgetSnapshotSynchronizer;
  late Directory tempDir;
  late TodoService todos;
  late FakeEsp32MqttTransport transport;
  late MemoryEsp32MqttSecretStore secrets;
  late Esp32MqttService service;
  late FakeEsp32MqttTimers syncTimers;
  late MemoryEsp32TaskMetaStore metaStore;
  late Esp32MqttTaskSync sync;
  late DateTime clock;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memex_mqtt_sync_');
    await FileSystemService.init(tempDir.path);
    todos = TodoService();
    TodoService.alarmSynchronizer = (_) async => TodoAlarmStatus.unavailable;
    TodoService.widgetSnapshotSynchronizer = (_) async {};

    transport = FakeEsp32MqttTransport();
    secrets = MemoryEsp32MqttSecretStore();
    service = Esp32MqttService(
      transportFactory: () => transport,
      secretStore: secrets,
      random: Random(7),
      timerFactory: FakeEsp32MqttTimers().create,
    );
    syncTimers = FakeEsp32MqttTimers();
    metaStore = MemoryEsp32TaskMetaStore();
    clock = DateTime(2026, 11, 20, 10, 0);
    sync = Esp32MqttTaskSync(
      service: service,
      todoService: todos,
      userIdProvider: () async => _userId,
      metaStore: metaStore,
      now: () => clock,
      timerFactory: syncTimers.create,
    );
    await sync.start();
  });

  tearDown(() async {
    await sync.stop();
    service.dispose();
    await transport.close();
    TodoService.localMutationObserver = null;
    TodoService.alarmSynchronizer = originalAlarmSync;
    TodoService.widgetSnapshotSynchronizer = originalWidgetSync;
    await TodoService.waitForAlarmSync();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> deliverRetained(Map<String, String> retained) async {
    for (final entry in retained.entries) {
      await transport.inject(
        '$_taskPrefix${entry.key}',
        boardPayload(entry.value),
        retained: true,
      );
    }
    for (final timer in List.of(syncTimers.active)) {
      timer.fire();
    }
    await sync.waitForIdle();
  }

  Future<TodoItem> addTask(
    String text, {
    String? dueDate,
    String? dueTime,
  }) async {
    final item = await todos.add(
      userId: _userId,
      text: text,
      dueDate: dueDate,
      dueTime: dueTime,
    );
    await sync.waitForIdle();
    return item;
  }

  List<FakePublishCall> taskPublishes(String id) => [
        for (final call in transport.publishes)
          if (call.topic == '$_taskPrefix$id') call,
      ];

  FakePublishCall lastTaskPublish(String id) => taskPublishes(id).last;

  Map<String, dynamic> lastEnvelope(String id) =>
      jsonDecode(openPlain(lastTaskPublish(id))) as Map<String, dynamic>;

  /// What the broker would hold: the last retained publish per task topic.
  Map<String, String> brokerState() {
    final last = <String, FakePublishCall>{};
    for (final call in transport.publishes) {
      if (call.topic.startsWith(_taskPrefix)) last[call.topic] = call;
    }
    return {
      for (final entry in last.entries)
        if (entry.value.payload.isNotEmpty)
          entry.key.substring(_taskPrefix.length): openPlain(entry.value),
    };
  }

  /// Pairs the first time, reconnects afterwards; then delivers the retained
  /// set and closes the retained window.
  Future<void> connectBoard({Map<String, String> retained = const {}}) async {
    if (!service.status.value.paired) {
      expect(await service.pairFromCode(kFakeQrJson), isNull);
    } else {
      await service.connect();
    }
    await flushEvents();
    await deliverRetained(retained);
  }

  Future<void> reconnect({Map<String, String>? retained}) async {
    await service.disconnect();
    await service.connect();
    await flushEvents();
    await deliverRetained(retained ?? brokerState());
  }

  Future<List<TodoItem>> visible() => todos.load(_userId);

  Future<List<TodoItem>> everything() =>
      todos.load(_userId, includeDeleted: true);

  test(
      'a new local task is published retained with an envelope the board reads',
      () async {
    await connectBoard();

    final item = await addTask(
      'Comprar leite',
      dueDate: '2026-11-21',
      dueTime: '14:30',
    );

    final call = lastTaskPublish(item.id);
    expect(call.retain, isTrue);
    final envelope = lastEnvelope(item.id);
    expect(envelope['contract_version'], 1);
    expect(envelope['entity_type'], 'todo');
    expect(envelope['entity_id'], item.id);
    expect(envelope['origin_role'], 'mobile');
    expect(envelope['updated_at'], sec(clock));
    expect(envelope['new_version'], 1);
    expect(envelope['payload'], {
      'id': item.id,
      'text': 'Comprar leite',
      'done': false,
      'due_ts': dueSec(2026, 11, 21, 14, 30),
    });
  });

  test('a new remote task is created in the Todo list', () async {
    await connectBoard(
      retained: {
        'esp-1a2b3c': remoteJson(
          id: 'esp-1a2b3c',
          updatedAt: sec(clock) - 600,
          text: 'Pagar conta',
          dueTs: dueSec(2026, 11, 22, 9, 15),
        ),
      },
    );

    final created = (await visible()).singleWhere(
      (item) => item.id == 'esp-1a2b3c',
    );
    expect(created.text, 'Pagar conta');
    expect(created.done, isFalse);
    expect(created.dueDate, '2026-11-22');
    expect(created.dueTime, '09:15');
    expect(created.due, '2026-11-22 09:15');
  });

  group('conflicts with a local task', () {
    late String id;

    setUp(() async {
      await connectBoard();
      id = (await addTask('Ligar')).id;
    });

    test('a remote copy older than the local one is overridden and republished',
        () async {
      final before = taskPublishes(id).length;

      await reconnect(
        retained: {
          id: remoteJson(
            id: id,
            updatedAt: sec(clock) - 60,
            text: 'Versão antiga',
          ),
        },
      );

      final item = (await visible()).singleWhere((todo) => todo.id == id);
      expect(item.text, 'Ligar');
      expect(taskPublishes(id).length, before + 1);
      expect(lastEnvelope(id)['payload']['text'], 'Ligar');
      expect(lastEnvelope(id)['updated_at'], sec(clock));
    });

    test('an equal timestamp keeps the local copy without republishing',
        () async {
      final before = taskPublishes(id).length;

      await reconnect(
        retained: {
          id: remoteJson(id: id, updatedAt: sec(clock), text: 'Outra'),
        },
      );

      final item = (await visible()).singleWhere((todo) => todo.id == id);
      expect(item.text, 'Ligar');
      expect(taskPublishes(id).length, before);
    });

    test('a newer remote copy overwrites the local one without republishing',
        () async {
      final before = taskPublishes(id).length;

      await reconnect(
        retained: {
          id: remoteJson(
            id: id,
            updatedAt: sec(clock) + 60,
            text: 'Versão nova',
          ),
        },
      );

      final item = (await visible()).singleWhere((todo) => todo.id == id);
      expect(item.text, 'Versão nova');
      expect(item.version, 2);
      expect(taskPublishes(id).length, before);
      expect(metaStore.data[id]!.updatedAt, sec(clock) + 60);
    });
  });

  test(
      'deleting publishes an empty retained payload; an empty payload from the board deletes',
      () async {
    await connectBoard();
    final removed = await addTask('Apagar isto');
    final kept = await addTask('Manter isto');

    clock = clock.add(const Duration(minutes: 1));
    await todos.remove(userId: _userId, id: removed.id);
    await sync.waitForIdle();

    final cleared = lastTaskPublish(removed.id);
    expect(cleared.payload, isEmpty);
    expect(cleared.retain, isTrue);

    await transport.inject(
      '$_taskPrefix${kept.id}',
      Uint8List(0),
      retained: false,
    );
    await sync.waitForIdle();

    expect((await visible()).map((todo) => todo.id), isNot(contains(kept.id)));
    expect(
      (await everything())
          .singleWhere((todo) => todo.id == kept.id)
          .isTombstoned,
      isTrue,
    );
  });

  test('updated_at changes with the text, not with a priority change',
      () async {
    await connectBoard();
    final item = await addTask('Revisar contrato');
    final firstUpdatedAt = metaStore.data[item.id]!.updatedAt;
    expect(firstUpdatedAt, sec(clock));

    clock = clock.add(const Duration(minutes: 3));
    await todos.edit(
      userId: _userId,
      id: item.id,
      text: 'Revisar contrato',
      due: item.due,
      priority: TodoPriority.high,
    );
    await sync.waitForIdle();

    expect(metaStore.data[item.id]!.updatedAt, firstUpdatedAt);
    expect(lastEnvelope(item.id)['updated_at'], firstUpdatedAt);

    clock = clock.add(const Duration(minutes: 3));
    await todos.edit(
      userId: _userId,
      id: item.id,
      text: 'Revisar o contrato',
      due: item.due,
      priority: TodoPriority.high,
    );
    await sync.waitForIdle();

    expect(metaStore.data[item.id]!.updatedAt, sec(clock));
    expect(lastEnvelope(item.id)['updated_at'], sec(clock));
    expect(lastEnvelope(item.id)['payload']['text'], 'Revisar o contrato');
  });

  test(
      'reconnecting deletes a synced task the board no longer holds when few are missing',
      () async {
    await connectBoard();
    final ids = [
      for (var i = 0; i < 5; i++) (await addTask('Tarefa $i')).id,
    ];
    final state = brokerState();
    expect(state.keys, unorderedEquals(ids));
    state.remove(ids[2]);

    await reconnect(retained: state);

    expect((await visible()).map((todo) => todo.id), isNot(contains(ids[2])));
    expect((await visible()).length, 4);
    expect(
      (await everything())
          .singleWhere((todo) => todo.id == ids[2])
          .isTombstoned,
      isTrue,
    );
  });

  group('trust guard', () {
    test('no retained task at all deletes nothing and republishes everything',
        () async {
      await connectBoard();
      final ids = [
        for (var i = 0; i < 3; i++) (await addTask('Tarefa $i')).id,
      ];
      final before = {for (final id in ids) id: taskPublishes(id).length};

      await reconnect(retained: const {});

      expect(await visible(), hasLength(3));
      for (final id in ids) {
        expect(taskPublishes(id).length, before[id]! + 1);
      }
    });

    test(
        'more than half and more than three missing deletes nothing and republishes',
        () async {
      await connectBoard();
      final ids = [
        for (var i = 0; i < 8; i++) (await addTask('Tarefa $i')).id,
      ];
      final state = brokerState();
      final kept = <String, String>{
        for (final id in ids.take(3)) id: state[id]!,
      };
      final before = {for (final id in ids) id: taskPublishes(id).length};

      await reconnect(retained: kept);

      expect(await visible(), hasLength(8));
      for (final id in ids) {
        expect(taskPublishes(id).length, before[id]! + 1);
      }
    });
  });

  test('a missing task with a pending local edit is republished, not deleted',
      () async {
    await connectBoard();
    final a = await addTask('Tarefa A');
    final b = await addTask('Tarefa B');

    await service.disconnect();
    await flushEvents();
    await todos.edit(
      userId: _userId,
      id: a.id,
      text: 'Tarefa A editada',
      due: a.due,
    );
    await sync.waitForIdle();

    await reconnect(retained: {b.id: brokerState()[b.id]!});

    final active = (await visible()).singleWhere((todo) => todo.id == a.id);
    expect(active.text, 'Tarefa A editada');
    expect(lastEnvelope(a.id)['payload']['text'], 'Tarefa A editada');
  });

  test('a task deleted locally is not revived by an older retained copy',
      () async {
    await connectBoard();
    final item = await addTask('Antiga');
    clock = clock.add(const Duration(minutes: 5));
    await todos.remove(userId: _userId, id: item.id);
    await sync.waitForIdle();

    await reconnect(
      retained: {
        item.id: remoteJson(
          id: item.id,
          updatedAt: sec(clock) - 300,
          text: 'Antiga',
        ),
      },
    );

    expect((await visible()).map((todo) => todo.id), isNot(contains(item.id)));
    expect(
      (await everything())
          .singleWhere((todo) => todo.id == item.id)
          .isTombstoned,
      isTrue,
    );
    expect(lastTaskPublish(item.id).payload, isEmpty);
  });
}
