import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:memex/domain/models/lumen_pairing.dart';

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

  static const int _hashLen = 32;
  static const int _maxOkmLength = 255 * _hashLen;
  static const int masterKeyBytes = 32;

  static final Uint8List _emptySalt = Uint8List(0);
  static final Uint8List _joinInfoBytes = Uint8List.fromList(ascii.encode(joinInfo));
  static final Uint8List _mailboxInfoBytes =
      Uint8List.fromList(ascii.encode(mailboxInfo));
  static final Uint8List _authInfoBytes = Uint8List.fromList(ascii.encode(authInfo));

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

  static void _assertMasterKey(Uint8List masterKey) {
    if (masterKey.length != masterKeyBytes) {
      throw ArgumentError('Master key must be exactly $masterKeyBytes bytes.');
    }
  }
}
