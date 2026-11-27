import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_ble_bridge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemorySecretStore implements Esp32SecretStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

class _FakeBleTransport implements Esp32BleTransport {
  bool connected = false;
  bool blePermissions = true;
  bool notificationAccess = true;
  bool failWrite = false;
  final List<Map<String, dynamic>> sentCommands = <Map<String, dynamic>>[];

  void Function(String line)? onBleLine;
  void Function(bool connected)? onConnectionChanged;
  void Function(Map<String, String> notification)? onNotification;

  Map<String, dynamic> Function(Map<String, dynamic> cmd)? onCommandReply;

  @override
  void setCallbacks({
    void Function(String line)? onBleLine,
    void Function(bool connected)? onConnectionChanged,
    void Function(Map<String, String> notification)? onNotification,
  }) {
    this.onBleLine = onBleLine;
    this.onConnectionChanged = onConnectionChanged;
    this.onNotification = onNotification;
  }

  @override
  Future<bool> hasBlePermissions() async => blePermissions;

  @override
  Future<bool> requestBlePermissions() async {
    blePermissions = true;
    return true;
  }

  @override
  Future<bool> hasNotificationAccess() async => notificationAccess;

  @override
  Future<void> openNotificationAccessSettings() async {}

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<String?> readStatus() async =>
      '{"ok":true,"paired":${connected ? "true" : "false"}}';

  @override
  Future<bool> scanAndConnect({int timeoutMs = 10000}) async {
    connected = true;
    onConnectionChanged?.call(true);
    return true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    onConnectionChanged?.call(false);
  }

  @override
  Future<bool> writeJson(String payload) async {
    if (failWrite) return false;
    expect(utf8.encode(payload).length, lessThan(kEsp32MaxCommandBytes));
    final decoded = (jsonDecode(payload) as Map).cast<String, dynamic>();
    sentCommands.add(decoded);
    final reply = onCommandReply?.call(decoded);
    if (reply != null) {
      Future<void>.microtask(() => onBleLine?.call(jsonEncode(reply)));
    }
    return true;
  }

  void simulateConnectionChange(bool value) {
    connected = value;
    onConnectionChanged?.call(value);
  }

  void simulateNotification(String app, String title, String body) {
    onNotification?.call(<String, String>{
      'app': app,
      'title': title,
      'body': body,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validKey =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  late _FakeBleTransport transport;
  late _InMemorySecretStore secretStore;
  late Esp32BleBridgeService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    transport = _FakeBleTransport()..connected = true;
    secretStore = _InMemorySecretStore();
    service = Esp32BleBridgeService(
      transport: transport,
      secretStore: secretStore,
      replyTimeout: const Duration(milliseconds: 500),
    );
  });

  tearDown(() => service.dispose());

  test('computes deterministic HMAC-SHA256 hex matching firmware spec', () {
    final mac = Esp32BleBridgeService.signType(validKey, 'task_sync');
    expect(mac.length, 64);
    expect(mac, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(mac, Esp32BleBridgeService.signType(validKey, 'task_sync'));
    expect(mac, isNot(Esp32BleBridgeService.signType(validKey, 'notif')));
  });

  test('pairing flow stores 64-hex key and rejects wrong PIN', () async {
    transport.onCommandReply = (cmd) {
      if (cmd['type'] == 'pair_start') {
        return <String, dynamic>{'type': 'pair_code', 'ok': true};
      }
      if (cmd['type'] == 'pair_confirm') {
        if (cmd['code'] == '654321') {
          return <String, dynamic>{
            'type': 'pair_ok',
            'ok': true,
            'key': validKey,
          };
        }
        return <String, dynamic>{
          'type': 'pair_ok',
          'ok': false,
          'erro': 'codigo_invalido',
        };
      }
      return <String, dynamic>{'type': cmd['type'], 'ok': true};
    };

    expect(await service.isPaired(), isFalse);
    expect(await service.startPairing(), isTrue);
    expect(await service.confirmPairing('000000'), isFalse);
    expect(await service.isPaired(), isFalse);

    expect(await service.confirmPairing('654321'), isTrue);
    expect(await service.isPaired(), isTrue);
    expect(await secretStore.read(kEsp32BleKeySecret), validKey);

    await service.revokePairing();
    expect(await service.isPaired(), isFalse);
    expect(
      transport.sentCommands.last['type'],
      'revoke',
    );
  });

  test('task_sync batches under 950 bytes and deduplicates remote envelopes',
      () async {
    await secretStore.write(kEsp32BleKeySecret, validKey);
    transport.onCommandReply = (cmd) {
      expect(cmd['hmac'], Esp32BleBridgeService.signType(validKey, 'task_sync'));
      return <String, dynamic>{
        'type': 'task_sync',
        'ok': true,
        'envelopes': <Map<String, dynamic>>[
          <String, dynamic>{
            'entity_id': 'esp-1',
            'payload': <String, dynamic>{
              'text': 'Old board text',
              'done': false,
              'due_ts': 0,
            },
          },
          <String, dynamic>{
            'entity_id': 'esp-1',
            'payload': <String, dynamic>{
              'text': 'Latest board text',
              'done': true,
              'due_ts': 1764200000,
            },
          },
        ],
      };
    };

    final many = List<Esp32SyncTask>.generate(
      14,
      (i) => Esp32SyncTask(
        entityId: 'local-$i',
        text: 'Tarefa extensa numero $i para testar divisao em lotes BLE GATT',
        done: i.isEven,
      ),
    );

    final remote = await service.syncTasks(outgoing: many);
    expect(transport.sentCommands.length, greaterThanOrEqualTo(2));
    expect(remote, hasLength(1));
    expect(remote.single.entityId, 'esp-1');
    expect(remote.single.text, 'Latest board text');
    expect(remote.single.done, isTrue);
  });

  test('offline tasks queue when disconnected and replay on reconnect',
      () async {
    await secretStore.write(kEsp32BleKeySecret, validKey);
    transport.connected = false;
    transport.onCommandReply = (cmd) => <String, dynamic>{
          'type': 'task_sync',
          'ok': true,
          'envelopes': <dynamic>[],
        };

    final offlineResult = await service.syncTasks(
      outgoing: const <Esp32SyncTask>[
        Esp32SyncTask(entityId: 'q1', text: 'Comprar café'),
      ],
    );
    expect(offlineResult, isEmpty);
    expect(await service.loadPendingTasks(), hasLength(1));

    transport.simulateConnectionChange(true);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      transport.sentCommands.any((c) => c['type'] == 'task_sync'),
      isTrue,
    );
    expect(await service.loadPendingTasks(), isEmpty);
  });

  test('notif truncates multibyte UTF-8 cleanly and respects app filter',
      () async {
    await secretStore.write(kEsp32BleKeySecret, validKey);
    transport.onCommandReply = (cmd) => <String, dynamic>{
          'type': cmd['type'],
          'ok': true,
        };

    await service.saveAllowedApps(<String>{'whatsapp'});

    // Blocked app should not write to BLE.
    transport.simulateNotification('msg', 'SMS', 'Código 1234');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(transport.sentCommands, isEmpty);

    // Allowed app with emojis/accents gets safely truncated to byte limits.
    final ok = await service.forwardNotification(
      app: 'whatsapp',
      title: '👩🏽‍💻 Reunião importante sobre arquitetura BLE GATT ESP32-S3',
      body: 'ÁÉÍÓÚ café 🚀 ' * 25,
    );
    expect(ok, isTrue);
    final sent = transport.sentCommands.single;
    expect(sent['type'], 'notif');
    expect(utf8.encode(sent['title'] as String).length, lessThanOrEqualTo(63));
    expect(utf8.encode(sent['body'] as String).length, lessThanOrEqualTo(159));
  });

  test('configureBoard validates charIdx 0..3 and sends signed config',
      () async {
    await secretStore.write(kEsp32BleKeySecret, validKey);
    transport.onCommandReply = (cmd) => <String, dynamic>{
          'type': 'config',
          'ok': true,
        };

    await expectLater(
      () => service.configureBoard(charIdx: 4),
      throwsRangeError,
    );

    final ok = await service.configureBoard(
      ssid: 'MinhaRede',
      pass: 'segredo123',
      city: 'Curitiba',
      charIdx: 2,
    );
    expect(ok, isTrue);
    final cmd = transport.sentCommands.single;
    expect(cmd['type'], 'config');
    expect(cmd['hmac'], Esp32BleBridgeService.signType(validKey, 'config'));
    expect(cmd['ssid'], 'MinhaRede');
    expect(cmd['city'], 'Curitiba');
    expect(cmd['char_idx'], 2);
  });
}
