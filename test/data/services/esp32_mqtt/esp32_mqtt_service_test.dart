import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_pairing.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';

import 'fake_esp32_mqtt_transport.dart';

Uint8List _b(String text) => Uint8List.fromList(utf8.encode(text));

String _presenceTopic(String who) => 'sm/$kFakeRoom/presenca/$who';

void main() {
  late FakeEsp32MqttTransport transport;
  late MemoryEsp32MqttSecretStore store;
  late FakeEsp32MqttTimers timers;
  late Esp32MqttService service;

  setUp(() {
    transport = FakeEsp32MqttTransport();
    store = MemoryEsp32MqttSecretStore();
    timers = FakeEsp32MqttTimers();
    service = Esp32MqttService(
      transportFactory: () => transport,
      secretStore: store,
      random: Random(7),
      timerFactory: timers.create,
    );
  });

  tearDown(() async {
    service.dispose();
    await transport.close();
  });

  Future<void> pairValid() async {
    final error = await service.pairFromCode(kFakeQrJson);
    expect(error, isNull);
  }

  group('pairing', () {
    test('an invalid QR returns the error and stores nothing', () async {
      final error = await service.pairFromCode('{"t":"outro"}');

      expect(error, Esp32PairingError.wrongType);
      expect(store.data, isEmpty);
      expect(transport.connects, isEmpty);
      expect(service.status.value.paired, isFalse);
    });

    test('a valid QR stores the pairing and connects with the will set', () async {
      await pairValid();

      final stored = jsonDecode(store.data[kEsp32MqttPairingSecret]!)
          as Map<String, dynamic>;
      expect(stored['sala'], kFakeRoom);
      expect(stored['k'], kFakeRoomKey);

      final connect = transport.connects.single;
      expect(connect.host, 'broker.example.test');
      expect(connect.port, 8883);
      expect(connect.clientId, 'celular-$kFakeRoom');
      expect(connect.username, 'celular-user');
      expect(connect.password, 'synthetic-pass');
      expect(connect.willTopic, _presenceTopic('celular'));
      expect(connect.willPayload, '0');
      expect(connect.willRetain, isTrue);

      expect(service.status.value.paired, isTrue);
      expect(service.status.value.link, Esp32MqttLinkState.connected);
    });

    test('after connecting it publishes presence 1 retained and subscribes to the board presence', () async {
      await pairValid();

      final presence = transport.publishes.singleWhere(
        (p) => p.topic == _presenceTopic('celular'),
      );
      expect(presence.text, '1');
      expect(presence.retain, isTrue);
      expect(transport.subscribes, <String>[_presenceTopic('placa')]);
    });

    test('init loads a stored pairing without connecting', () async {
      store.data[kEsp32MqttPairingSecret] = jsonEncode(
        Esp32MqttPairing.parse(kFakeQrJson).pairing!.toJson(),
      );

      await service.init();

      expect(service.status.value.paired, isTrue);
      expect(service.status.value.link, Esp32MqttLinkState.disconnected);
      expect(transport.connects, isEmpty);
    });

    test('forget deletes the stored pairing and resets the state', () async {
      await pairValid();

      await service.forget();

      expect(store.data.containsKey(kEsp32MqttPairingSecret), isFalse);
      expect(service.status.value.paired, isFalse);
      expect(service.status.value.link, Esp32MqttLinkState.notPaired);
    });

    test('connect without a pairing returns false', () async {
      expect(await service.connect(), isFalse);
      expect(transport.connects, isEmpty);
    });
  });

  group('connection and presence', () {
    test('board presence updates boardOnline with 1 and 0', () async {
      await pairValid();

      await transport.inject(_presenceTopic('placa'), _b('1'), retained: true);
      expect(service.status.value.boardOnline, isTrue);

      await transport.inject(_presenceTopic('placa'), _b('0'));
      expect(service.status.value.boardOnline, isFalse);
    });

    test('connect is idempotent while connected', () async {
      await pairValid();

      expect(await service.connect(), isTrue);
      expect(transport.connects.length, 1);
    });

    test('publishEncrypted produces an envelope that opens with from celular', () async {
      await pairValid();

      final ok = await service.publishEncrypted('tarefas/esp-1', 'Comprar leite');

      expect(ok, isTrue);
      final published = transport.publishes.last;
      expect(published.topic, 'sm/$kFakeRoom/tarefas/esp-1');
      expect(published.retain, isFalse);
      final opened = Esp32RoomCrypto(kFakeRoomKey)
          .open(published.text, self: kEsp32FromBoard);
      expect(opened.isOk, isTrue);
      expect(opened.from, kEsp32FromPhone);
      expect(opened.plaintext, 'Comprar leite');
    });

    test('publishEncrypted returns false when not connected', () async {
      transport.nextConnectResult = Esp32MqttConnectResult.unreachable;
      await pairValid();

      expect(await service.publishEncrypted('tarefas/x', 'texto'), isFalse);
    });

    test('a drop that nobody requested marks the link down and reconnects in 2 s', () async {
      await pairValid();

      await transport.simulateDrop();

      expect(service.status.value.link, Esp32MqttLinkState.disconnected);
      expect(service.status.value.boardOnline, isFalse);
      expect(timers.active.single.delay, const Duration(seconds: 2));

      timers.active.single.fire();
      await flushEvents();

      expect(transport.connects.length, 2);
      expect(service.status.value.link, Esp32MqttLinkState.connected);
    });
  });

  group('incoming messages', () {
    test('an encrypted message from the board arrives decrypted', () async {
      final received = <Esp32MqttMessage>[];
      final sub = service.messages.listen(received.add);
      await pairValid();
      final envelope = Esp32RoomCrypto(kFakeRoomKey)
          .seal(from: kEsp32FromBoard, plaintext: 'tarefa da placa');

      await transport.inject(
        'sm/$kFakeRoom/tarefas/esp-2',
        _b(envelope),
        retained: true,
      );

      expect(received.single.suffix, 'tarefas/esp-2');
      expect(received.single.plaintext, 'tarefa da placa');
      expect(received.single.from, kEsp32FromBoard);
      expect(received.single.retained, isTrue);
      await sub.cancel();
    });

    test('a message with our own from is dropped silently', () async {
      final received = <Esp32MqttMessage>[];
      final sub = service.messages.listen(received.add);
      await pairValid();
      final envelope = Esp32RoomCrypto(kFakeRoomKey)
          .seal(from: kEsp32FromPhone, plaintext: 'eco');

      await transport.inject('sm/$kFakeRoom/tarefas/esp-3', _b(envelope));

      expect(received, isEmpty);
      expect(service.status.value.keyRejected, isFalse);
      await sub.cancel();
    });

    test('a board message sealed with another key marks keyRejected and is dropped', () async {
      final received = <Esp32MqttMessage>[];
      final sub = service.messages.listen(received.add);
      await pairValid();
      final envelope = Esp32RoomCrypto(
        '11112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
      ).seal(from: kEsp32FromBoard, plaintext: 'com outra chave');

      await transport.inject('sm/$kFakeRoom/tarefas/esp-4', _b(envelope));

      expect(service.status.value.keyRejected, isTrue);
      expect(received, isEmpty);
      await sub.cancel();
    });

    test('an empty payload arrives with plaintext null', () async {
      final received = <Esp32MqttMessage>[];
      final sub = service.messages.listen(received.add);
      await pairValid();

      await transport.inject(
        'sm/$kFakeRoom/tarefas/esp-5',
        Uint8List(0),
        retained: true,
      );

      expect(received.single.suffix, 'tarefas/esp-5');
      expect(received.single.plaintext, isNull);
      expect(received.single.from, isNull);
      expect(received.single.retained, isTrue);
      await sub.cancel();
    });
  });

  group('reconnect and disconnect', () {
    test('unreachable schedules a reconnect in 2 s, then 4 s', () async {
      transport.nextConnectResult = Esp32MqttConnectResult.unreachable;
      await pairValid();

      expect(service.status.value.lastError, Esp32MqttConnectResult.unreachable);
      expect(timers.active.single.delay, const Duration(seconds: 2));

      timers.active.single.fire();
      await flushEvents();

      expect(transport.connects.length, 2);
      expect(timers.active.single.delay, const Duration(seconds: 4));
    });

    test('badCredentials does not schedule a reconnect', () async {
      transport.nextConnectResult = Esp32MqttConnectResult.badCredentials;
      await pairValid();

      expect(service.status.value.lastError, Esp32MqttConnectResult.badCredentials);
      expect(service.status.value.link, Esp32MqttLinkState.disconnected);
      expect(timers.active, isEmpty);
      expect(transport.connects.length, 1);
    });

    test('disconnect publishes presence 0 retained and cancels the pending reconnect', () async {
      await pairValid();
      await transport.simulateDrop();
      expect(timers.active.length, 1);

      await service.disconnect();

      expect(timers.active, isEmpty);
      expect(service.status.value.link, Esp32MqttLinkState.disconnected);
      expect(service.status.value.boardOnline, isFalse);
    });

    test('disconnect while connected publishes presence 0 retained', () async {
      await pairValid();

      await service.disconnect();

      final presence = transport.publishes.last;
      expect(presence.topic, _presenceTopic('celular'));
      expect(presence.text, '0');
      expect(presence.retain, isTrue);
      expect(transport.disconnectCount, greaterThanOrEqualTo(1));
      expect(timers.active, isEmpty);
    });

    test('disconnect stops a retry when the attempt was unreachable', () async {
      transport.nextConnectResult = Esp32MqttConnectResult.unreachable;
      await pairValid();

      await service.disconnect();
      transport.nextConnectResult = Esp32MqttConnectResult.ok;

      expect(timers.active, isEmpty);
      expect(transport.connects.length, 1);
    });
  });
}
