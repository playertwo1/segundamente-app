import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_notification_forwarder.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_pairing.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_task_sync.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/ui/esp32/view_models/esp32_board_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/esp32_mqtt/fake_esp32_mqtt_transport.dart';

class _FakeNotifSource implements Esp32NotificationSource {
  bool access = false;
  int openSettingsCount = 0;

  @override
  Future<bool> hasNotificationAccess() async => access;

  @override
  Future<void> openNotificationAccessSettings() async {
    openSettingsCount++;
  }

  @override
  void setOnNotification(
    void Function(String app, String title, String body)? handler,
  ) {}
}

class _MemoryMetaStore implements Esp32TaskMetaStore {
  Map<String, Esp32TaskMeta> data = <String, Esp32TaskMeta>{};

  @override
  Future<Map<String, Esp32TaskMeta>> load() async => data;

  @override
  Future<void> save(Map<String, Esp32TaskMeta> metas) async {
    data = Map<String, Esp32TaskMeta>.from(metas);
  }
}

/// Envelope sealed by the board with a key the app does not have.
String _foreignBoardEnvelope() => Esp32RoomCrypto(
      'ff' * 32,
      random: Random(3),
    ).seal(from: kEsp32FromBoard, plaintext: '{"x":1}');

void main() {
  late FakeEsp32MqttTransport transport;
  late MemoryEsp32MqttSecretStore store;
  late FakeEsp32MqttTimers timers;
  late Esp32MqttService service;
  late _FakeNotifSource source;
  late Esp32MqttNotificationForwarder forwarder;
  late Esp32MqttTaskSync taskSync;
  late Esp32BoardViewModel vm;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    transport = FakeEsp32MqttTransport();
    store = MemoryEsp32MqttSecretStore();
    timers = FakeEsp32MqttTimers();
    service = Esp32MqttService(
      transportFactory: () => transport,
      secretStore: store,
      random: Random(7),
      timerFactory: timers.create,
    );
    source = _FakeNotifSource();
    forwarder = Esp32MqttNotificationForwarder(
      service: service,
      source: source,
      timerFactory: timers.create,
    );
    taskSync = Esp32MqttTaskSync(
      service: service,
      todoService: TodoService(),
      userIdProvider: () async => null,
      metaStore: _MemoryMetaStore(),
      timerFactory: timers.create,
    );
    vm = Esp32BoardViewModel(
      service: service,
      taskSync: taskSync,
      forwarder: forwarder,
    );
  });

  tearDown(() async {
    vm.dispose();
    await taskSync.stop();
    await forwarder.stop();
    service.dispose();
    await transport.close();
  });

  test('starts unpaired with no error', () {
    expect(vm.paired, isFalse);
    expect(vm.link, Esp32MqttLinkState.notPaired);
    expect(vm.pairingError, isNull);
    expect(vm.busy, isFalse);
  });

  test('an invalid code keeps the board unpaired and exposes the error', () async {
    final ok = await vm.pairFromCode('{"t":"outro"}');

    expect(ok, isFalse);
    expect(vm.pairingError, Esp32PairingError.wrongType);
    expect(vm.paired, isFalse);
    expect(store.data, isEmpty);
    expect(vm.busy, isFalse);
  });

  test('a valid code pairs, connects and clears the previous error', () async {
    await vm.pairFromCode('{"t":"outro"}');

    final ok = await vm.pairFromCode(kFakeQrJson);

    expect(ok, isTrue);
    expect(vm.pairingError, isNull);
    expect(vm.paired, isTrue);
    expect(vm.link, Esp32MqttLinkState.connected);
    expect(vm.busy, isFalse);
  });

  test('forget disconnects, deletes the key and clears the error', () async {
    await vm.pairFromCode(kFakeQrJson);

    await vm.forget();

    expect(vm.paired, isFalse);
    expect(vm.link, Esp32MqttLinkState.notPaired);
    expect(store.data, isEmpty);
    expect(vm.pairingError, isNull);
  });

  test('the view model exposes the status changes of the service', () async {
    await vm.pairFromCode(kFakeQrJson);
    var notified = 0;
    vm.addListener(() => notified++);

    await transport.simulateDrop();
    await flushEvents();

    expect(vm.link, isNot(Esp32MqttLinkState.connected));
    expect(notified, greaterThan(0));
  });

  test('a message sealed with another key marks the key as rejected', () async {
    await vm.pairFromCode(kFakeQrJson);
    expect(vm.keyRejected, isFalse);

    await transport.inject(
      'sm/$kFakeRoom/tarefas/esp-1',
      Uint8List.fromList(utf8.encode(_foreignBoardEnvelope())),
    );

    expect(vm.keyRejected, isTrue);
  });

  test('bad credentials at connect are exposed as lastError', () async {
    transport.nextConnectResult = Esp32MqttConnectResult.badCredentials;

    final ok = await vm.pairFromCode(kFakeQrJson);

    expect(ok, isTrue);
    expect(vm.link, Esp32MqttLinkState.disconnected);
    expect(vm.lastError, Esp32MqttConnectResult.badCredentials);
  });

  test('initialize reads the notification access and the saved apps', () async {
    source.access = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      kEsp32NotifAllowedAppsPrefsKey: <String>['whatsapp'],
    });

    await vm.initialize();

    expect(vm.hasNotificationAccess, isTrue);
    expect(vm.allowedApps, {'whatsapp'});
  });

  test('refreshNotificationAccess picks up access granted in settings', () async {
    await vm.initialize();
    expect(vm.hasNotificationAccess, isFalse);

    source.access = true;
    await vm.refreshNotificationAccess();

    expect(vm.hasNotificationAccess, isTrue);
  });

  test('toggling an app saves it through the forwarder', () async {
    await vm.initialize();
    expect(vm.allowedApps, isNot(contains('msg')));

    await vm.toggleAllowedApp('msg', true);

    expect(vm.allowedApps, contains('msg'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(kEsp32NotifAllowedAppsPrefsKey), contains('msg'));

    await vm.toggleAllowedApp('whatsapp', false);
    expect(vm.allowedApps, isNot(contains('whatsapp')));
    expect(
      prefs.getStringList(kEsp32NotifAllowedAppsPrefsKey),
      isNot(contains('whatsapp')),
    );
  });

  test('openNotificationAccessSettings opens the Android screen', () async {
    await vm.openNotificationAccessSettings();

    expect(source.openSettingsCount, 1);
  });

  test('syncNow connects a paired board that is down', () async {
    await vm.pairFromCode(kFakeQrJson);
    await transport.simulateDrop();
    final before = transport.connects.length;

    await vm.syncNow();

    expect(transport.connects.length, greaterThan(before));
    expect(vm.link, Esp32MqttLinkState.connected);
  });
}
