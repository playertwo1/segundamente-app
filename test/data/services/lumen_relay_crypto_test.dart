import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/lumen_relay_crypto.dart';
import 'package:memex/domain/models/lumen_pairing.dart';

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    final raw =
        File('test/fixtures/lumen_relay_test_vectors.json').readAsStringSync();
    vectors = jsonDecode(raw) as Map<String, dynamic>;
  });

  group('LumenRelayCrypto', () {
    test('hkdfSha256 matches RFC 5869 Appendix A.1 vector', () {
      final a1 = vectors['rfc5869_a1'] as Map<String, dynamic>;
      final okm = LumenRelayCrypto.hkdfSha256(
        ikm: _hexToBytes(a1['ikm'] as String),
        salt: _hexToBytes(a1['salt'] as String),
        info: _hexToBytes(a1['info'] as String),
        length: a1['length'] as int,
      );

      expect(_bytesToHex(okm), equals(a1['okm'] as String));
    });

    test('deriveKeys and joinProof match Lumen synthetic test vectors byte-for-byte', () {
      final inputs = vectors['inputs'] as Map<String, dynamic>;
      final derivedVec = vectors['derived'] as Map<String, dynamic>;

      final masterKey = _hexToBytes(inputs['key'] as String);
      final masterKeyB64 = encodeBase64UrlNoPad(masterKey);

      final derivedFromBytes = LumenRelayCrypto.deriveKeys(masterKey);
      final derivedFromB64 = LumenRelayCrypto.deriveFromBase64Url(masterKeyB64);

      expect(_bytesToHex(derivedFromBytes.kAuth), derivedVec['kAuth']);
      expect(_bytesToHex(derivedFromBytes.kJoin), derivedVec['kJoin']);
      expect(_bytesToHex(derivedFromBytes.kMailbox), derivedVec['kMailbox']);

      expect(derivedFromB64.kAuth, equals(derivedFromBytes.kAuth));
      expect(derivedFromB64.kJoin, equals(derivedFromBytes.kJoin));
      expect(derivedFromB64.kMailbox, equals(derivedFromBytes.kMailbox));
      expect(derivedFromB64.joinProof, equals(derivedFromBytes.joinProof));

      final expectedJoinProof = encodeBase64UrlNoPad(derivedFromBytes.kJoin);
      expect(derivedFromBytes.joinProof, equals(expectedJoinProof));
      expect(derivedFromBytes.joinProof.length, 43);
      expect(LumenRelayCrypto.joinProof(masterKey), equals(expectedJoinProof));
      expect(
        LumenRelayCrypto.joinProofFromBase64Url(masterKeyB64),
        equals(expectedJoinProof),
      );

      final joinVerifier =
          _bytesToHex(sha256.convert(derivedFromBytes.kJoin).bytes);
      expect(joinVerifier, equals(derivedVec['joinVerifier']));

      expect(derivedFromBytes.kAuth, isNot(equals(derivedFromBytes.kJoin)));
      expect(derivedFromBytes.kMailbox, isNot(equals(derivedFromBytes.kJoin)));
      expect(derivedFromBytes.kMailbox, isNot(equals(derivedFromBytes.kAuth)));
    });

    test('LumenDerivedKeys.toString is fully redacted', () {
      final inputs = vectors['inputs'] as Map<String, dynamic>;
      final derivedVec = vectors['derived'] as Map<String, dynamic>;
      final masterKey = _hexToBytes(inputs['key'] as String);
      final derived = LumenRelayCrypto.deriveKeys(masterKey);

      final printed = derived.toString();
      expect(printed, equals('LumenDerivedKeys(..)'));
      expect(printed, isNot(contains(derived.joinProof)));
      expect(printed, isNot(contains(derivedVec['kAuth'] as String)));
      expect(printed, isNot(contains(derivedVec['kJoin'] as String)));
      expect(printed, isNot(contains(derivedVec['kMailbox'] as String)));
    });

    test('handles zero length and rejects invalid lengths or invalid master keys', () {
      expect(
        LumenRelayCrypto.hkdfSha256(
          ikm: Uint8List(32),
          salt: Uint8List(0),
          info: Uint8List(0),
          length: 0,
        ),
        isEmpty,
      );
      expect(
        () => LumenRelayCrypto.hkdfSha256(
          ikm: Uint8List(32),
          salt: Uint8List(0),
          info: Uint8List(0),
          length: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => LumenRelayCrypto.hkdfSha256(
          ikm: Uint8List(32),
          salt: Uint8List(0),
          info: Uint8List(0),
          length: 255 * 32 + 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => LumenRelayCrypto.deriveKeys(Uint8List(31)),
        throwsArgumentError,
      );
      expect(
        () => LumenRelayCrypto.joinProof(Uint8List(33)),
        throwsArgumentError,
      );
      expect(
        () => LumenRelayCrypto.deriveFromBase64Url('not-valid-43-char-key'),
        throwsFormatException,
      );
      expect(
        () => LumenRelayCrypto.joinProofFromBase64Url('not-valid-43-char-key'),
        throwsFormatException,
      );
    });
  });
}
