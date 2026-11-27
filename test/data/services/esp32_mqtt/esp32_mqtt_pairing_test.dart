import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_pairing.dart';

import 'fake_esp32_mqtt_transport.dart';

Map<String, dynamic> _qrMap({
  String? t = 'sm-mqtt',
  Object? v = 1,
  String uri = 'mqtts://broker.example.test:8883',
  String? u = 'celular-user',
  String? p = 'synthetic-pass',
  String sala = kFakeRoom,
  String k = kFakeRoomKey,
}) {
  return <String, dynamic>{
    if (t != null) 't': t,
    'v': v,
    'uri': uri,
    if (u != null) 'u': u,
    if (p != null) 'p': p,
    'sala': sala,
    'k': k,
  };
}

String _qr(Map<String, dynamic> map) => jsonEncode(map);

void main() {
  group('Esp32MqttPairing.parse', () {
    test('accepts a valid QR with an explicit port', () {
      final result = Esp32MqttPairing.parse(_qr(_qrMap(
        uri: 'mqtts://broker.example.test:8884',
      )));

      final pairing = result.pairing!;
      expect(result.error, isNull);
      expect(pairing.host, 'broker.example.test');
      expect(pairing.port, 8884);
      expect(pairing.username, 'celular-user');
      expect(pairing.password, 'synthetic-pass');
      expect(pairing.room, kFakeRoom);
      expect(pairing.roomKey, kFakeRoomKey);
      expect(pairing.uri, 'mqtts://broker.example.test:8884');
    });

    test('uses port 8883 when the URI has no port', () {
      final pairing = Esp32MqttPairing.parse(_qr(_qrMap(
        uri: 'mqtts://broker.example.test',
      )))
          .pairing!;

      expect(pairing.port, 8883);
    });

    test('trims surrounding whitespace before parsing', () {
      final result = Esp32MqttPairing.parse('  ${_qr(_qrMap())}\n');

      expect(result.pairing, isNotNull);
    });

    test('keeps the room key exactly as received', () {
      const upperKey =
          '00112233445566778899AABBCCDDEEFF00112233445566778899aabbccddeeff';
      final pairing = Esp32MqttPairing.parse(_qr(_qrMap(k: upperKey)))
          .pairing!;

      expect(pairing.roomKey, upperKey);
    });

    test('toJson produces the same shape as the QR', () {
      final pairing = Esp32MqttPairing.parse(_qr(_qrMap())).pairing!;

      expect(pairing.toJson(), <String, dynamic>{
        't': 'sm-mqtt',
        'v': 1,
        'uri': 'mqtts://broker.example.test:8883',
        'u': 'celular-user',
        'p': 'synthetic-pass',
        'sala': kFakeRoom,
        'k': kFakeRoomKey,
      });
    });

    test('text that is not JSON gives notJson', () {
      expect(
        Esp32MqttPairing.parse('isto não é um QR').error,
        Esp32PairingError.notJson,
      );
    });

    test('a JSON array gives notJson', () {
      expect(
        Esp32MqttPairing.parse('[1,2,3]').error,
        Esp32PairingError.notJson,
      );
    });

    test('a different type gives wrongType', () {
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(t: 'outro'))).error,
        Esp32PairingError.wrongType,
      );
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(t: null))).error,
        Esp32PairingError.wrongType,
      );
    });

    test('version 2 gives unsupportedVersion', () {
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(v: 2))).error,
        Esp32PairingError.unsupportedVersion,
      );
    });

    test('plain mqtt without TLS gives badUri', () {
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(
          uri: 'mqtt://broker.example.test:1883',
        ))).error,
        Esp32PairingError.badUri,
      );
    });

    test('empty host, port 0 and port above 65535 give badUri', () {
      for (final uri in <String>[
        'mqtts://',
        'mqtts://:8883',
        'mqtts://broker.example.test:0',
        'mqtts://broker.example.test:70000',
        'https://broker.example.test',
      ]) {
        expect(
          Esp32MqttPairing.parse(_qr(_qrMap(uri: uri))).error,
          Esp32PairingError.badUri,
          reason: uri,
        );
      }
    });

    test('empty username or password give missingCredentials', () {
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(u: ''))).error,
        Esp32PairingError.missingCredentials,
      );
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(p: ''))).error,
        Esp32PairingError.missingCredentials,
      );
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(u: null))).error,
        Esp32PairingError.missingCredentials,
      );
    });

    test('room with uppercase letters or 11 characters gives badRoom', () {
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(sala: 'ABC123DEF456'))).error,
        Esp32PairingError.badRoom,
      );
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(sala: 'abc123def45'))).error,
        Esp32PairingError.badRoom,
      );
    });

    test('key with 63 characters gives badKey', () {
      expect(
        Esp32MqttPairing.parse(_qr(_qrMap(
          k: kFakeRoomKey.substring(0, 63),
        ))).error,
        Esp32PairingError.badKey,
      );
    });

    test('toString shows only host and room, never password or key', () {
      final pairing = Esp32MqttPairing.parse(_qr(_qrMap())).pairing!;

      final text = pairing.toString();

      expect(text, contains('broker.example.test'));
      expect(text, contains(kFakeRoom));
      expect(text, isNot(contains('synthetic-pass')));
      expect(text, isNot(contains(kFakeRoomKey)));
    });
  });
}
