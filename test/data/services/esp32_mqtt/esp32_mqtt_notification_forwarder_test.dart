import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_notification_forwarder.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_esp32_mqtt_transport.dart';

const String _kNotifTopic = 'sm/$kFakeRoom/notif';

class FakeEsp32NotificationSource implements Esp32NotificationSource {
  bool access = true;
  int openSettingsCount = 0;
  void Function(String app, String title, String body)? handler;

  @override
  Future<bool> hasNotificationAccess() async => access;

  @override
  Future<void> openNotificationAccessSettings() async {
    openSettingsCount++;
  }

  @override
  void setOnNotification(
    void Function(String app, String title, String body)? handler,
  ) {
    this.handler = handler;
  }
}

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await flushEvents();
  }
}

void main() {
  late FakeEsp32MqttTransport transport;
  late MemoryEsp32MqttSecretStore store;
  late FakeEsp32MqttTimers timers;
  late Esp32MqttService service;
  late FakeEsp32NotificationSource source;
  late DateTime clock;
  late Esp32MqttNotificationForwarder forwarder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    transport = FakeEsp32MqttTransport();
    store = MemoryEsp32MqttSecretStore();
    timers = FakeEsp32MqttTimers();
    service = Esp32MqttService(
      transportFactory: () => transport,
      secretStore: store,
      random: Random(7),
      timerFactory: timers.create,
    );
    source = FakeEsp32NotificationSource();
    clock = DateTime.utc(2026, 1, 1, 12);
    forwarder = Esp32MqttNotificationForwarder(
      service: service,
      source: source,
      now: () => clock,
      timerFactory: timers.create,
    );
    await forwarder.start();
  });

  tearDown(() async {
    await forwarder.stop();
    service.dispose();
    await transport.close();
  });

  Future<void> pair() async {
    expect(await service.pairFromCode(kFakeQrJson), isNull);
  }

  List<FakePublishCall> notifPublishes() =>
      transport.publishes.where((p) => p.topic == _kNotifTopic).toList();

  Map<String, dynamic> decrypt(FakePublishCall call) {
    final result = Esp32RoomCrypto(kFakeRoomKey).open(
      call.text,
      self: kEsp32FromBoard,
    );
    expect(result.isOk, isTrue);
    return jsonDecode(result.plaintext!) as Map<String, dynamic>;
  }

  List<String> sentBodies() => notifPublishes()
      .map((p) => decrypt(p)['body'] as String)
      .toList();

  group('filter', () {
    test('apps that are not allowed or not supported are neither published nor queued', () async {
      await pair();
      final connectsBefore = transport.connects.length;

      // msg is supported but not in the default allowed set.
      expect(
        await forwarder.forward(app: 'msg', title: 'Oi', body: 'texto'),
        isFalse,
      );
      expect(
        await forwarder.forward(app: 'telegram', title: 'Oi', body: 'texto'),
        isFalse,
      );
      await settle();

      expect(notifPublishes(), isEmpty);
      expect(forwarder.queuedCount, 0);
      expect(transport.connects.length, connectsBefore);
    });
  });

  group('publish', () {
    test('an allowed app is published to sm/<sala>/notif, not retained, with the expected JSON', () async {
      await pair();

      final ok = await forwarder.forward(
        app: 'WhatsApp',
        title: ' Ana ',
        body: ' Oi, tudo bem? ',
      );
      await settle();

      expect(ok, isTrue);
      final publishes = notifPublishes();
      expect(publishes, hasLength(1));
      expect(publishes.single.topic, _kNotifTopic);
      expect(publishes.single.retain, isFalse);
      expect(decrypt(publishes.single), <String, dynamic>{
        'app': 'whatsapp',
        'title': 'Ana',
        'body': 'Oi, tudo bem?',
        'silent': false,
      });
    });

    test('title and body longer than the limits are cut on whole characters', () async {
      await pair();
      final title = 'Reunião de ação 🚀 ' * 10;
      final body = 'çã😀 ' * 80;

      await forwarder.forward(app: 'call', title: title, body: body);
      await settle();

      final sent = decrypt(notifPublishes().single);
      final sentTitle = sent['title'] as String;
      final sentBody = sent['body'] as String;

      expect(utf8.encode(sentTitle).length, lessThanOrEqualTo(63));
      expect(utf8.encode(sentBody).length, lessThanOrEqualTo(159));
      // Close to the limit, not cut much shorter than it.
      expect(utf8.encode(sentTitle).length, greaterThan(63 - 4));
      expect(utf8.encode(sentBody).length, greaterThan(159 - 4));
      // Prefix of the original, and no broken character.
      expect(title.trim().startsWith(sentTitle), isTrue);
      expect(body.trim().startsWith(sentBody), isTrue);
      expect(utf8.decode(utf8.encode(sentTitle)), sentTitle);
      expect(utf8.decode(utf8.encode(sentBody)), sentBody);
    });

    test('a notification from the source goes through the same path', () async {
      await pair();
      expect(source.handler, isNotNull);

      source.handler!('whatsapp', 'Pedro', 'Chegou');
      await settle();

      expect(sentBodies(), ['Chegou']);
    });
  });

  group('offline queue', () {
    test('notifications wait while offline and go out in order on reconnect', () async {
      await pair();
      await service.disconnect();
      transport.nextConnectResult = Esp32MqttConnectResult.unreachable;

      expect(
        await forwarder.forward(app: 'call', title: 'Um', body: '1'),
        isFalse,
      );
      expect(
        await forwarder.forward(app: 'call', title: 'Dois', body: '2'),
        isFalse,
      );
      await settle();

      expect(notifPublishes(), isEmpty);
      expect(forwarder.queuedCount, 2);

      transport.nextConnectResult = Esp32MqttConnectResult.ok;
      timers.active.single.fire();
      await settle();

      expect(sentBodies(), ['1', '2']);
      expect(forwarder.queuedCount, 0);
    });

    test('items older than five minutes are dropped on reconnect', () async {
      await pair();
      await service.disconnect();
      transport.nextConnectResult = Esp32MqttConnectResult.unreachable;

      await forwarder.forward(app: 'call', title: 'Velha', body: 'antiga');
      await settle();
      clock = clock.add(const Duration(minutes: 6));
      await forwarder.forward(app: 'call', title: 'Nova', body: 'recente');
      await settle();

      transport.nextConnectResult = Esp32MqttConnectResult.ok;
      timers.active.single.fire();
      await settle();

      expect(sentBodies(), ['recente']);
    });

    test('the queue keeps at most 20 items, dropping the oldest', () async {
      await pair();
      await service.disconnect();
      transport.nextConnectResult = Esp32MqttConnectResult.unreachable;

      for (var i = 0; i < 25; i++) {
        await forwarder.forward(app: 'call', title: 't', body: 'n$i');
      }
      await settle();
      expect(forwarder.queuedCount, 20);

      transport.nextConnectResult = Esp32MqttConnectResult.ok;
      timers.active.single.fire();
      await settle();

      final bodies = sentBodies();
      expect(bodies, hasLength(20));
      expect(bodies.first, 'n5');
      expect(bodies.last, 'n24');
    });
  });

  group('background link', () {
    test('in the background the link closes after backgroundIdle from the last send', () async {
      await pair();
      forwarder.appInForeground = false;

      await forwarder.forward(app: 'whatsapp', title: 'a', body: 'b');
      await settle();
      expect(notifPublishes(), hasLength(1));
      expect(transport.disconnectCount, 0);

      final idle = timers.active.single;
      expect(idle.delay, const Duration(seconds: 60));
      idle.fire();
      await settle();

      expect(transport.disconnectCount, 1);
      expect(service.status.value.link, Esp32MqttLinkState.disconnected);
    });

    test('returning to the foreground cancels the pending idle close', () async {
      await pair();
      forwarder.appInForeground = false;
      await forwarder.forward(app: 'whatsapp', title: 'a', body: 'b');
      await settle();
      expect(timers.active, hasLength(1));

      forwarder.appInForeground = true;

      expect(timers.active, isEmpty);
      expect(transport.disconnectCount, 0);
      expect(service.status.value.link, Esp32MqttLinkState.connected);
    });

    test('in the foreground the link is never closed by the forwarder', () async {
      await pair();

      await forwarder.forward(app: 'whatsapp', title: 'a', body: 'b');
      await settle();

      expect(notifPublishes(), hasLength(1));
      expect(timers.active, isEmpty);
      expect(transport.disconnectCount, 0);
    });
  });

  group('allowed apps storage', () {
    test('saveAllowedApps keeps only supported apps and loadAllowedApps reads them back', () async {
      await forwarder.saveAllowedApps({' WhatsApp ', 'msg', 'telegram'});

      expect(await forwarder.loadAllowedApps(), {'whatsapp', 'msg'});
    });

    test('loadAllowedApps ignores unsupported apps that are stored', () async {
      SharedPreferences.setMockInitialValues({
        kEsp32NotifAllowedAppsPrefsKey: ['whatsapp', 'telegram', ' CALL '],
      });

      expect(await forwarder.loadAllowedApps(), {'whatsapp', 'call'});
    });

    test('without a saved choice the default set is used', () async {
      SharedPreferences.setMockInitialValues({});

      expect(
        await forwarder.loadAllowedApps(),
        kEsp32NotifDefaultApps,
      );
    });
  });

  group('helpers', () {
    test('esp32Utf8Truncate returns the input when it already fits', () {
      expect(esp32Utf8Truncate('oi', 63), 'oi');
      expect(esp32Utf8Truncate('abc', 0), '');
    });

    test('esp32Utf8Truncate does not split a multi-byte character', () {
      // 'é' takes 2 bytes; 3 bytes fit only 'aé'.
      expect(esp32Utf8Truncate('aéé', 3), 'aé');
    });
  });
}
