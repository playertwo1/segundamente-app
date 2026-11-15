import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:pointycastle/export.dart';

/// Peer role in the Lumen persistent E2EE mailbox protocol (`coucou-mailbox/v1`).
enum LumenMailboxRole {
  pc(1, 'pc'),
  phone(2, 'phone');

  final int code;
  final String wireName;

  const LumenMailboxRole(this.code, this.wireName);

  static LumenMailboxRole fromWire(String wire) {
    return switch (wire) {
      'pc' => LumenMailboxRole.pc,
      'phone' => LumenMailboxRole.phone,
      _ => throw ArgumentError.value(wire, 'wire', 'Unknown mailbox role'),
    };
  }
}

/// Safe exception thrown by `coucou-mailbox/v1` encryption/decryption.
/// [toString] never includes keys, nonces, tags, or plaintext.
class LumenMailboxCipherException implements Exception {
  final String reason;
  final String message;

  const LumenMailboxCipherException(this.reason, this.message);

  @override
  String toString() => 'LumenMailboxCipherException($reason): $message';
}

/// Derived 32-byte keys and join proof from a pairing master key `K`.
/// [toString] is redacted so secrets are never printed in logs or errors.
class LumenDerivedKeys {
  final Uint8List kJoin;
  final String joinProof;
  final Uint8List kMailbox;
  final Uint8List kAuth;

  const LumenDerivedKeys({
    required this.kJoin,
    required this.joinProof,
    required this.kMailbox,
    required this.kAuth,
  });

  @override
  String toString() => 'LumenDerivedKeys(..)';
}

/// Pure-Dart RFC 5869 HKDF-SHA-256 key derivation compatible with Lumen's
/// `coucou-relay/v1` specification.
class LumenRelayCrypto {
  static const String label = 'coucou-relay/v1';
  static const String joinInfo = '$label join';
  static const String mailboxInfo = '$label mailbox';
  static const String authInfo = '$label auth';
  static const String mailboxLabel = 'coucou-mailbox/v1';
  static const int mailboxVersion = 1;
  static const int mailboxMinBodyBytes = 1 + 12 + 128 + 16;
  static const int mailboxMaxJsonBytes = 65536;

  static const int _hashLen = 32;
  static const int _maxOkmLength = 255 * _hashLen;
  static const int masterKeyBytes = 32;
  static const int _mailboxNonceBytes = 12;
  static const int _mailboxMacBits = 128;
  static const int _mailboxBlockBytes = 128;

  static final RegExp _roomRegex = RegExp(r'^[A-Za-z0-9_-]{22}$');
  static final math.Random _secureRandom = math.Random.secure();
  static final Uint8List _emptySalt = Uint8List(0);
  static final Uint8List _joinInfoBytes = Uint8List.fromList(ascii.encode(joinInfo));
  static final Uint8List _mailboxInfoBytes =
      Uint8List.fromList(ascii.encode(mailboxInfo));
  static final Uint8List _authInfoBytes = Uint8List.fromList(ascii.encode(authInfo));
  static final Uint8List _mailboxLabelBytes =
      Uint8List.fromList(ascii.encode(mailboxLabel));

  const LumenRelayCrypto._();

  /// Computes RFC 5869 HKDF-SHA-256 (Extract + Expand).
  static Uint8List hkdfSha256({
    required Uint8List ikm,
    required Uint8List salt,
    required Uint8List info,
    required int length,
  }) {
    if (length < 0 || length > _maxOkmLength) {
      throw ArgumentError(
        'HKDF output length must be between 0 and $_maxOkmLength bytes.',
      );
    }
    if (length == 0) {
      return Uint8List(0);
    }

    // RFC 5869 section 2.2: empty salt defaults to HashLen zero bytes.
    final effectiveSalt = salt.isEmpty ? Uint8List(_hashLen) : salt;
    final prk = Hmac(sha256, effectiveSalt).convert(ikm).bytes;

    final prkHmac = Hmac(sha256, prk);
    final okm = Uint8List(length);
    var previousBlock = const <int>[];
    var offset = 0;
    var counter = 1;

    while (offset < length) {
      final input = Uint8List(previousBlock.length + info.length + 1);
      input.setRange(0, previousBlock.length, previousBlock);
      input.setRange(
        previousBlock.length,
        previousBlock.length + info.length,
        info,
      );
      input[input.length - 1] = counter;

      final block = prkHmac.convert(input).bytes;
      final copyLen = math.min(block.length, length - offset);
      okm.setRange(offset, offset + copyLen, block);
      offset += copyLen;
      previousBlock = block;
      counter++;
    }

    return okm;
  }

  /// Derives `K_join`, `joinProof`, `K_mailbox` and `K_auth` from a 32-byte
  /// pairing master key.
  static LumenDerivedKeys deriveKeys(Uint8List masterKey) {
    _assertMasterKey(masterKey);
    final kJoin = hkdfSha256(
      ikm: masterKey,
      salt: _emptySalt,
      info: _joinInfoBytes,
      length: masterKeyBytes,
    );
    final kMailbox = hkdfSha256(
      ikm: masterKey,
      salt: _emptySalt,
      info: _mailboxInfoBytes,
      length: masterKeyBytes,
    );
    final kAuth = hkdfSha256(
      ikm: masterKey,
      salt: _emptySalt,
      info: _authInfoBytes,
      length: masterKeyBytes,
    );
    return LumenDerivedKeys(
      kJoin: kJoin,
      joinProof: encodeBase64UrlNoPad(kJoin),
      kMailbox: kMailbox,
      kAuth: kAuth,
    );
  }

  /// Decodes a strict 43-char unpadded base64url master key and derives all
  /// relay subkeys.
  static LumenDerivedKeys deriveFromBase64Url(String keyB64) {
    final masterKey =
        decodeBase64UrlStrict(keyB64, expectedBytes: masterKeyBytes);
    return deriveKeys(masterKey);
  }

  /// Computes the 43-char unpadded base64url `X-Lumen-Join` header proof from
  /// a 32-byte master key.
  static String joinProof(Uint8List masterKey) {
    _assertMasterKey(masterKey);
    final kJoin = hkdfSha256(
      ikm: masterKey,
      salt: _emptySalt,
      info: _joinInfoBytes,
      length: masterKeyBytes,
    );
    return encodeBase64UrlNoPad(kJoin);
  }

  /// Computes the 43-char unpadded base64url `X-Lumen-Join` header proof from
  /// a strict base64url master key string.
  static String joinProofFromBase64Url(String keyB64) {
    final masterKey =
        decodeBase64UrlStrict(keyB64, expectedBytes: masterKeyBytes);
    return joinProof(masterKey);
  }

  /// Builds the 41-byte `coucou-mailbox/v1` AEAD associated data:
  /// `ascii("coucou-mailbox/v1") || ascii(room) || [to.code, 1]`.
  static Uint8List mailboxAad({
    required String room,
    required LumenMailboxRole to,
  }) {
    if (room.length != 22 || !_roomRegex.hasMatch(room)) {
      throw const LumenMailboxCipherException(
        'invalid_room',
        'Mailbox room identifier must be 22 base64url characters.',
      );
    }
    final roomBytes = ascii.encode(room);
    final out = Uint8List(_mailboxLabelBytes.length + roomBytes.length + 2);
    out.setRange(0, _mailboxLabelBytes.length, _mailboxLabelBytes);
    out.setRange(
      _mailboxLabelBytes.length,
      _mailboxLabelBytes.length + roomBytes.length,
      roomBytes,
    );
    out[out.length - 2] = to.code;
    out[out.length - 1] = mailboxVersion;
    return out;
  }

  /// Prefixes UTF-8 [json] with its u32 big-endian byte length and zero-pads to
  /// a 128-byte boundary (minimum 128 bytes).
  static Uint8List padMailboxJson(String json) {
    final text = utf8.encode(json);
    if (text.length > mailboxMaxJsonBytes) {
      throw const LumenMailboxCipherException(
        'bad_length',
        'Mailbox JSON payload exceeds maximum allowed size.',
      );
    }
    final rawLen = 4 + text.length;
    final total =
        ((rawLen + _mailboxBlockBytes - 1) ~/ _mailboxBlockBytes) *
            _mailboxBlockBytes;
    final out = Uint8List(total < _mailboxBlockBytes ? _mailboxBlockBytes : total);
    ByteData.sublistView(out, 0, 4).setUint32(0, text.length, Endian.big);
    out.setRange(4, rawLen, text);
    return out;
  }

  /// Seals [json] with `coucou-mailbox/v1` AES-256-GCM using an explicit 12-byte
  /// [nonce]. Intended for deterministic vector tests; production callers should
  /// use [sealMailboxJson] or [sealMailboxEnvelope].
  static Uint8List sealMailboxWithNonce({
    required Uint8List kMailbox,
    required String room,
    required LumenMailboxRole to,
    required String json,
    required Uint8List nonce,
  }) {
    _assertKeyBytes(kMailbox, masterKeyBytes, 'Mailbox key');
    _assertKeyBytes(nonce, _mailboxNonceBytes, 'Mailbox nonce');
    final aad = mailboxAad(room: room, to: to);
    final padded = padMailboxJson(json);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(kMailbox),
          _mailboxMacBits,
          nonce,
          aad,
        ),
      );
    final ctAndTag = cipher.process(padded);

    final body = Uint8List(1 + nonce.length + ctAndTag.length);
    body[0] = mailboxVersion;
    body.setRange(1, 1 + nonce.length, nonce);
    body.setRange(1 + nonce.length, body.length, ctAndTag);
    return body;
  }

  /// Seals [json] with `coucou-mailbox/v1` AES-256-GCM and a fresh CSPRNG nonce.
  static Uint8List sealMailboxJson({
    required Uint8List kMailbox,
    required String room,
    required LumenMailboxRole to,
    required String json,
  }) {
    final nonce = Uint8List(_mailboxNonceBytes);
    for (var i = 0; i < nonce.length; i++) {
      nonce[i] = _secureRandom.nextInt(256);
    }
    return sealMailboxWithNonce(
      kMailbox: kMailbox,
      room: room,
      to: to,
      json: json,
      nonce: nonce,
    );
  }

  /// JSON-encodes [envelope] and seals it with `coucou-mailbox/v1` AES-256-GCM.
  static Uint8List sealMailboxEnvelope({
    required Uint8List kMailbox,
    required String room,
    required LumenMailboxRole to,
    required Map<String, dynamic> envelope,
  }) {
    return sealMailboxJson(
      kMailbox: kMailbox,
      room: room,
      to: to,
      json: jsonEncode(envelope),
    );
  }

  /// Opens and validates a `coucou-mailbox/v1` body, returning the JSON string.
  static String openMailboxJson({
    required Uint8List kMailbox,
    required String room,
    required LumenMailboxRole to,
    required Uint8List body,
  }) {
    return _openMailboxDecoded(
      kMailbox: kMailbox,
      room: room,
      to: to,
      body: body,
    ).json;
  }

  /// Opens and validates a `coucou-mailbox/v1` body, returning the decoded JSON
  /// object map.
  static Map<String, dynamic> openMailboxMap({
    required Uint8List kMailbox,
    required String room,
    required LumenMailboxRole to,
    required Uint8List body,
  }) {
    return _openMailboxDecoded(
      kMailbox: kMailbox,
      room: room,
      to: to,
      body: body,
    ).map;
  }

  static ({String json, Map<String, dynamic> map}) _openMailboxDecoded({
    required Uint8List kMailbox,
    required String room,
    required LumenMailboxRole to,
    required Uint8List body,
  }) {
    _assertKeyBytes(kMailbox, masterKeyBytes, 'Mailbox key');
    final aad = mailboxAad(room: room, to: to);
    if (body.length < mailboxMinBodyBytes) {
      throw const LumenMailboxCipherException(
        'too_short',
        'Mailbox body is shorter than minimum envelope length.',
      );
    }
    if (body[0] != mailboxVersion) {
      throw const LumenMailboxCipherException(
        'bad_version',
        'Unsupported mailbox ciphertext version.',
      );
    }

    final nonce = Uint8List.sublistView(body, 1, 1 + _mailboxNonceBytes);
    final ctAndTag = Uint8List.sublistView(body, 1 + _mailboxNonceBytes);

    final Uint8List plain;
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(kMailbox),
            _mailboxMacBits,
            nonce,
            aad,
          ),
        );
      plain = cipher.process(ctAndTag);
    } on InvalidCipherTextException {
      throw const LumenMailboxCipherException(
        'bad_tag',
        'Mailbox ciphertext authentication tag failed.',
      );
    } catch (_) {
      throw const LumenMailboxCipherException(
        'bad_tag',
        'Mailbox ciphertext decryption failed.',
      );
    }

    if (plain.length < _mailboxBlockBytes ||
        plain.length % _mailboxBlockBytes != 0) {
      throw const LumenMailboxCipherException(
        'bad_length',
        'Mailbox plaintext is not padded to 128-byte blocks.',
      );
    }
    final declared = ByteData.sublistView(plain, 0, 4).getUint32(0, Endian.big);
    if (declared > mailboxMaxJsonBytes || 4 + declared > plain.length) {
      throw const LumenMailboxCipherException(
        'bad_length',
        'Mailbox plaintext declared length is out of bounds.',
      );
    }

    final end = 4 + declared;
    for (var i = end; i < plain.length; i++) {
      if (plain[i] != 0) {
        throw const LumenMailboxCipherException(
          'bad_padding',
          'Mailbox plaintext trailing padding is non-zero.',
        );
      }
    }

    final String text;
    try {
      text = utf8.decode(
        Uint8List.sublistView(plain, 4, end),
        allowMalformed: false,
      );
    } on FormatException {
      throw const LumenMailboxCipherException(
        'bad_json',
        'Mailbox plaintext is not valid UTF-8.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const LumenMailboxCipherException(
        'bad_json',
        'Mailbox plaintext is not valid JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LumenMailboxCipherException(
        'bad_json',
        'Mailbox plaintext JSON must be an object.',
      );
    }
    return (json: text, map: decoded);
  }

  static void _assertMasterKey(Uint8List masterKey) {
    _assertKeyBytes(masterKey, masterKeyBytes, 'Master key');
  }

  static void _assertKeyBytes(Uint8List bytes, int expectedLen, String label) {
    if (bytes.length != expectedLen) {
      throw ArgumentError('$label must be exactly $expectedLen bytes.');
    }
  }
}
