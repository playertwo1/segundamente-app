import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';

import 'fake_esp32_mqtt_transport.dart';

/// Envelope produced outside Dart by `AesGcm` in .NET (PowerShell 7):
/// key = SHA-256 of kFakeRoomKey text, iv = 00..0b, aad = "placa",
/// plaintext = "Comprar leite e paão". Synthetic values only.
const String kKnownEnvelope =
    '{"v":1,"from":"placa","iv":"AAECAwQFBgcICQoL",'
    '"ct":"4ECNpr46p4faTa08JRAMX/wdGDCD",'
    '"tag":"3EAyHgj3mHioThazS2R7VQ=="}';
const String kKnownPlaintext = 'Comprar leite e paão';

Map<String, dynamic> _envelopeMap(String envelope) =>
    jsonDecode(envelope) as Map<String, dynamic>;

String _encode(Map<String, dynamic> map) => jsonEncode(map);

/// Envelope produced by Python `cryptography` (`AESGCM`) with the board's
/// parameters: key = SHA-256 of [kPythonRoomKey] text, iv = bytes 100..111,
/// aad = "lumen", base64 standard. Synthetic values only.
const String kPythonRoomKey =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
const String kPythonEnvelope =
    '{"v":1,"from":"lumen","iv":"ZGVmZ2hpamtsbW5v",'
    '"ct":"KlJutEHx2VJeD5ndYAmbs8Kthm1D8H2DrKG18Jp6AxUZcve3/StUU2GfX22/NSmtHDPZF5qqaghdpQd+bll/eu5CNAQ=",'
    '"tag":"va2gQFSiSaKiiRTiXwm7IA=="}';
const String kPythonPlaintext =
    '{"app":"whatsapp","title":"Ação","body":"Olá ✓","silent":false}';

void main() {
  group('Esp32RoomCrypto', () {
    test('seal as placa and open as celular round-trips', () {
      final board = Esp32RoomCrypto(kFakeRoomKey);
      final phone = Esp32RoomCrypto(kFakeRoomKey);

      final envelope = board.seal(from: kEsp32FromBoard, plaintext: 'olá, mundo');
      final result = phone.open(envelope, self: kEsp32FromPhone);

      expect(result.isOk, isTrue);
      expect(result.failure, isNull);
      expect(result.plaintext, 'olá, mundo');
      expect(result.from, kEsp32FromBoard);
    });

    test('envelope has the v1 shape from PROTOCOLO.md', () {
      final envelope = Esp32RoomCrypto(kFakeRoomKey)
          .seal(from: kEsp32FromPhone, plaintext: 'x');
      final map = _envelopeMap(envelope);

      expect(map.keys.toSet(), {'v', 'from', 'iv', 'ct', 'tag'});
      expect(map['v'], 1);
      expect(map['from'], kEsp32FromPhone);
      expect(base64Decode(map['iv'] as String).length, 12);
      expect(base64Decode(map['tag'] as String).length, 16);
    });

    test('seal uses a fresh IV every time', () {
      final crypto = Esp32RoomCrypto(kFakeRoomKey);
      final a = _envelopeMap(crypto.seal(from: kEsp32FromBoard, plaintext: 'a'));
      final b = _envelopeMap(crypto.seal(from: kEsp32FromBoard, plaintext: 'a'));

      expect(a['iv'], isNot(b['iv']));
    });

    test('opens the known envelope generated outside Dart', () {
      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(kKnownEnvelope, self: kEsp32FromPhone);

      expect(result.isOk, isTrue);
      expect(result.plaintext, kKnownPlaintext);
      expect(result.from, kEsp32FromBoard);
    });

    test('wrong room key gives authFailed', () {
      final envelope = Esp32RoomCrypto(kFakeRoomKey)
          .seal(from: kEsp32FromBoard, plaintext: 'secret');
      final other = Esp32RoomCrypto(
        '11112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
      );

      final result = other.open(envelope, self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.authFailed);
      expect(result.plaintext, isNull);
    });

    test('tampered from (placa to lumen) gives authFailed because it is AAD', () {
      final map = _envelopeMap(kKnownEnvelope)..['from'] = kEsp32FromLumen;

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(_encode(map), self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.authFailed);
    });

    test('own from gives self without decrypting', () {
      final envelope = Esp32RoomCrypto(kFakeRoomKey)
          .seal(from: kEsp32FromPhone, plaintext: 'mine');

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(envelope, self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.self);
      expect(result.plaintext, isNull);
    });

    test('missing from gives missingFrom', () {
      final map = _envelopeMap(kKnownEnvelope)..remove('from');

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(_encode(map), self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.missingFrom);
    });

    test('empty from gives missingFrom', () {
      final map = _envelopeMap(kKnownEnvelope)..['from'] = '';

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(_encode(map), self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.missingFrom);
    });

    test('unknown from gives unknownFrom', () {
      final map = _envelopeMap(kKnownEnvelope)..['from'] = 'intruso';

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(_encode(map), self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.unknownFrom);
    });

    test('v 2 gives badVersion', () {
      final map = _envelopeMap(kKnownEnvelope)..['v'] = 2;

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(_encode(map), self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.badVersion);
    });

    test('IV with the wrong size gives badFormat', () {
      final map = _envelopeMap(kKnownEnvelope)
        ..['iv'] = base64Encode(List<int>.filled(11, 0));

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(_encode(map), self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.badFormat);
    });

    test('tag with the wrong size gives badFormat', () {
      final map = _envelopeMap(kKnownEnvelope)
        ..['tag'] = base64Encode(List<int>.filled(8, 0));

      final result = Esp32RoomCrypto(kFakeRoomKey)
          .open(_encode(map), self: kEsp32FromPhone);

      expect(result.failure, Esp32OpenFailure.badFormat);
    });

    test('invalid JSON, missing fields and invalid base64 give badFormat', () {
      final crypto = Esp32RoomCrypto(kFakeRoomKey);

      expect(
        crypto.open('não é json', self: kEsp32FromPhone).failure,
        Esp32OpenFailure.badFormat,
      );
      final noCt = _envelopeMap(kKnownEnvelope)..remove('ct');
      expect(
        crypto.open(_encode(noCt), self: kEsp32FromPhone).failure,
        Esp32OpenFailure.badFormat,
      );
      final badB64 = _envelopeMap(kKnownEnvelope)..['iv'] = '%%%';
      expect(
        crypto.open(_encode(badB64), self: kEsp32FromPhone).failure,
        Esp32OpenFailure.badFormat,
      );
    });

    test('opens the envelope sealed by Python cryptography AESGCM', () {
      final result = Esp32RoomCrypto(kPythonRoomKey)
          .open(kPythonEnvelope, self: kEsp32FromPhone);

      expect(result.failure, isNull);
      expect(result.from, kEsp32FromLumen);
      expect(result.plaintext, kPythonPlaintext);
    });

    test('Python envelope with the AAD swapped to placa fails', () {
      final forged = _envelopeMap(kPythonEnvelope)..['from'] = kEsp32FromBoard;
      expect(
        Esp32RoomCrypto(kPythonRoomKey)
            .open(_encode(forged), self: kEsp32FromPhone)
            .failure,
        Esp32OpenFailure.authFailed,
      );
    });
  });
}
