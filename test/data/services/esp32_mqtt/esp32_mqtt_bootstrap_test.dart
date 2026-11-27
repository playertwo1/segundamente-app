import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_bootstrap.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_notification_forwarder.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_task_sync.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_esp32_mqtt_transport.dart';

class _FakeNotifSource implements Esp32NotificationSource {
  @override
  Future<bool> hasNotificationAccess() async => true;

  @override
  Future<void> openNotificationAccessSettings() async {}

  @override
  void setOnNotification(
    void Function(String app, String title, String body)? handler,
  ) {}
}

class _MemoryMetaStore implements Esp32TaskMetaStore {
  @override
  Future<Map<String, Esp32TaskMeta>> load() async => <String, Esp32TaskMeta>{};

  @override
  Future<void> save(Map<String, Esp32TaskMeta> metas) async {}
}

void main() {
  late FakeEsp32MqttTransport transport;
  late MemoryEsp32MqttSecretStore store;
  late FakeEsp32MqttTimers timers;
  late Esp32MqttService service;
  late Esp32MqttNotificationForwarder forwarder;
  late Esp32MqttTaskSync taskSync;
  late Esp32MqttBootstrap bootstrap;

  Esp32MqttBootstrap buildBootstrap() => Esp32MqttBootstrap(
        service: service,
        taskSync: taskSync,
        forwarder: forwarder,
        secretStore: store,
        timerFactory: timers.create,
      );

  setUp(() {
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
    forwarder = Esp32MqttNotificationForwarder(
      service: service,
      source: _FakeNotifSource(),
      timerFactory: timers.create,
    );
    taskSync = Esp32MqttTaskSync(
      service: service,
      todoService: TodoService(),
      userIdProvider: () async => null,
      metaStore: _MemoryMetaStore(),
      timerFactory: timers.create,
    );
    bootstrap = buildBootstrap();
  });

  tearDown(() async {
    await taskSync.stop();
    await forwarder.stop();
    service.dispose();
    await transport.close();
  });

  Future<void> settle() async {
    await flushEvents();
    await flushEvents();
  }

  FakeEsp32MqttTimer idleTimer() => timers.active.singleWhere(
        (t) => t.delay == const Duration(seconds: 60),
      );

  test('the first start removes the BLE key and pending tasks, only once',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kEsp32BleLegacyPendingPrefsKey: '[]',
    });
    store.data[kEsp32BleLegacyKeySecret] = 'legacy-ble-key';

    await bootstrap.start();

    expect(store.data.containsKey(kEsp32BleLegacyKeySecret), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kEsp32BleLegacyPendingPrefsKey), isFalse);
    expect(prefs.getBool(kEsp32BleLegacyCleanedPrefsKey), isTrue);

    // A later start, with leftovers back in place, leaves them alone.
    store.data[kEsp32BleLegacyKeySecret] = 'again';
    await prefs.setString(kEsp32BleLegacyPendingPrefsKey, '[]');
    await buildBootstrap().start();

    expect(store.data[kEsp32BleLegacyKeySecret], 'again');
    expect(prefs.containsKey(kEsp32BleLegacyPendingPrefsKey), isTrue);
  });

  test('start is idempotent for the same instance', () async {
    await bootstrap.start();
    await bootstrap.start();

    expect(transport.connects, isEmpty);
  });

  test('a paired board connects on start', () async {
    store.data[kEsp32MqttPairingSecret] = kFakeQrJson;

    await bootstrap.start();
    await settle();

    expect(transport.connects, hasLength(1));
    expect(service.status.value.link, Esp32MqttLinkState.connected);
  });

  test('an unpaired board does not connect on start', () async {
    await bootstrap.start();
    await settle();

    expect(transport.connects, isEmpty);
    expect(service.status.value.link, Esp32MqttLinkState.notPaired);
  });

  test('going to the background closes the link after 60 s', () async {
    store.data[kEsp32MqttPairingSecret] = kFakeQrJson;
    await bootstrap.start();
    await settle();
    expect(service.status.value.link, Esp32MqttLinkState.connected);

    bootstrap.onPaused();
    expect(forwarder.appInForeground, isFalse);
    expect(service.status.value.link, Esp32MqttLinkState.connected);

    idleTimer().fire();
    await settle();

    expect(service.status.value.link, Esp32MqttLinkState.disconnected);
    expect(transport.publishes.last.text, '0');
  });

  test('coming back before 60 s cancels the disconnect', () async {
    store.data[kEsp32MqttPairingSecret] = kFakeQrJson;
    await bootstrap.start();
    await settle();

    bootstrap.onPaused();
    bootstrap.onResumed();
    expect(forwarder.appInForeground, isTrue);
    expect(
      timers.active.where((t) => t.delay == const Duration(seconds: 60)),
      isEmpty,
    );

    await settle();
    expect(service.status.value.link, Esp32MqttLinkState.connected);
  });

  test('coming back reconnects a paired board that went down', () async {
    store.data[kEsp32MqttPairingSecret] = kFakeQrJson;
    await bootstrap.start();
    await settle();
    bootstrap.onPaused();
    idleTimer().fire();
    await settle();
    expect(service.status.value.link, Esp32MqttLinkState.disconnected);

    bootstrap.onResumed();
    await settle();

    expect(service.status.value.link, Esp32MqttLinkState.connected);
  });

  test('resuming an unpaired board does not connect', () async {
    await bootstrap.start();

    bootstrap.onResumed();
    await settle();

    expect(transport.connects, isEmpty);
  });
}
