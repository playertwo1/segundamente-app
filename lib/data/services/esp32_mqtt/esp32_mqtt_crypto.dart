import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Sender roles allowed in the MQTT envelope `from` field (PROTOCOLO.md).
const String kEsp32FromPhone = 'celular';
const String kEsp32FromBoard = 'placa';
const String kEsp32FromLumen = 'lumen';

const Set<String> _kKnownFrom = {
  kEsp32FromBoard,
  kEsp32FromLumen,
  kEsp32FromPhone,
};

const int _kEnvelopeVersion = 1;
const int _kIvBytes = 12;
const int _kTagBytes = 16;

enum Esp32OpenFailure {
  badFormat,
  badVersion,
  missingFrom,
  unknownFrom,
  self,
  authFailed,
}

/// Result of [Esp32RoomCrypto.open]. [plaintext] is set only on success.
/// [from] is set only when the envelope named a known sender.
class Esp32OpenResult {
  const Esp32OpenResult._({this.plaintext, this.from, this.failure});

  const Esp32OpenResult.ok({required String plaintext, required String from})
      : this._(plaintext: plaintext, from: from);

  const Esp32OpenResult.failed(Esp32OpenFailure failure, {String? from})
      : this._(from: from, failure: failure);

  final String? plaintext;
  final String? from;
  final Esp32OpenFailure? failure;

  bool get isOk => failure == null;
}

/// AES-256-GCM envelope for the room MQTT topics. Matches `sm_seal`/`sm_open`
/// in the board firmware (`firmware/main/crypto_box.c`).
class Esp32RoomCrypto {
  Esp32RoomCrypto(String roomKeyText, {math.Random? random})
      : _key = Uint8List.fromList(
          sha256.convert(utf8.encode(roomKeyText)).bytes,
        ),
        _random = random ?? math.Random.secure();

  final Uint8List _key;
  final math.Random _random;

  /// Seals [plaintext] as the JSON envelope expected by the board.
  String seal({required String from, required String plaintext}) {
    final iv = Uint8List.fromList(
      List<int>.generate(_kIvBytes, (_) => _random.nextInt(256)),
    );
    final aad = Uint8List.fromList(utf8.encode(from));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_key), _kTagBytes * 8, iv, aad),
      );
    final out = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
    final ctLength = out.length - _kTagBytes;
    return jsonEncode(<String, dynamic>{
      'v': _kEnvelopeVersion,
      'from': from,
      'iv': base64Encode(iv),
      'ct': base64Encode(out.sublist(0, ctLength)),
      'tag': base64Encode(out.sublist(ctLength)),
    });
  }

  /// Opens an envelope received from the broker. Messages sent by [self] are
  /// reported as [Esp32OpenFailure.self] without decrypting.
  Esp32OpenResult open(String envelopeJson, {required String self}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(envelopeJson);
    } catch (_) {
      return const Esp32OpenResult.failed(Esp32OpenFailure.badFormat);
    }
    if (decoded is! Map) {
      return const Esp32OpenResult.failed(Esp32OpenFailure.badFormat);
    }

    final ivB64 = decoded['iv'];
    final ctB64 = decoded['ct'];
    final tagB64 = decoded['tag'];
    if (ivB64 is! String || ctB64 is! String || tagB64 is! String) {
      return const Esp32OpenResult.failed(Esp32OpenFailure.badFormat);
    }
    final Uint8List iv;
    final Uint8List ct;
    final Uint8List tag;
    try {
      iv = base64Decode(ivB64);
      ct = base64Decode(ctB64);
      tag = base64Decode(tagB64);
    } on FormatException {
      return const Esp32OpenResult.failed(Esp32OpenFailure.badFormat);
    }
    if (iv.length != _kIvBytes || tag.length != _kTagBytes) {
      return const Esp32OpenResult.failed(Esp32OpenFailure.badFormat);
    }

    if (decoded['v'] != _kEnvelopeVersion) {
      return const Esp32OpenResult.failed(Esp32OpenFailure.badVersion);
    }

    final fromRaw = decoded['from'];
    if (fromRaw is! String || fromRaw.isEmpty) {
      return const Esp32OpenResult.failed(Esp32OpenFailure.missingFrom);
    }
    if (!_kKnownFrom.contains(fromRaw)) {
      return const Esp32OpenResult.failed(Esp32OpenFailure.unknownFrom);
    }
    if (fromRaw == self) {
      return Esp32OpenResult.failed(Esp32OpenFailure.self, from: fromRaw);
    }

    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(_key),
            _kTagBytes * 8,
            iv,
            Uint8List.fromList(utf8.encode(fromRaw)),
          ),
        );
      final input = Uint8List.fromList(<int>[...ct, ...tag]);
      final plain = cipher.process(input);
      return Esp32OpenResult.ok(
        plaintext: utf8.decode(plain),
        from: fromRaw,
      );
    } catch (_) {
      // Covers InvalidCipherTextException and malformed UTF-8 after decrypt.
      return Esp32OpenResult.failed(
        Esp32OpenFailure.authFailed,
        from: fromRaw,
      );
    }
  }
}
