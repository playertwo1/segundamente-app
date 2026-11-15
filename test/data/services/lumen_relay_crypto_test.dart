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
  late Map<String, dynamic> mailboxVectors;

  setUpAll(() {
    final raw =
        File('test/fixtures/lumen_relay_test_vectors.json').readAsStringSync();
    vectors = jsonDecode(raw) as Map<String, dynamic>;

    final rawMailbox =
        File('test/fixtures/lumen_mailbox_test_vectors.json').readAsStringSync();
    mailboxVectors = jsonDecode(rawMailbox) as Map<String, dynamic>;
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

  group('LumenRelayCrypto coucou-mailbox/v1', () {
    test('derives kMailbox matching mailbox test vectors', () {
      final inputs = mailboxVectors['inputs'] as Map<String, dynamic>;
      final masterKey = _hexToBytes(inputs['key'] as String);
      final derived = LumenRelayCrypto.deriveKeys(masterKey);

      expect(_bytesToHex(derived.kMailbox), equals(mailboxVectors['kMailbox']));
    });

    test('aad, padding, sealMailboxWithNonce and open match vectors byte-for-byte', () {
      final inputs = mailboxVectors['inputs'] as Map<String, dynamic>;
      final room = inputs['room'] as String;
      final kMailbox = _hexToBytes(mailboxVectors['kMailbox'] as String);
      final messages =
          (mailboxVectors['messages'] as List<dynamic>).cast<Map<String, dynamic>>();

      expect(messages, isNotEmpty);
      for (final msg in messages) {
        final to = LumenMailboxRole.fromWire(msg['to'] as String);
        final nonce = _hexToBytes(msg['nonce'] as String);
        final jsonText = msg['json'] as String;

        final aad = LumenRelayCrypto.mailboxAad(room: room, to: to);
        expect(_bytesToHex(aad), equals(msg['aad']), reason: 'aad for ${to.wireName}');

        final padded = LumenRelayCrypto.padMailboxJson(jsonText);
        expect(
          _bytesToHex(padded),
          equals(msg['plaintextPadded']),
          reason: 'padded for ${to.wireName}',
        );

        final sealed = LumenRelayCrypto.sealMailboxWithNonce(
          kMailbox: kMailbox,
          room: room,
          to: to,
          json: jsonText,
          nonce: nonce,
        );
        expect(
          _bytesToHex(sealed),
          equals(msg['body']),
          reason: 'body for ${to.wireName}',
        );

        final openedJson = LumenRelayCrypto.openMailboxJson(
          kMailbox: kMailbox,
          room: room,
          to: to,
          body: sealed,
        );
        expect(openedJson, equals(jsonText));

        final openedMap = LumenRelayCrypto.openMailboxMap(
          kMailbox: kMailbox,
          room: room,
          to: to,
          body: sealed,
        );
        expect(openedMap, equals(jsonDecode(jsonText) as Map<String, dynamic>));
      }
    });

    test('mustRefuse vectors fail with exact expected reason codes', () {
      final kMailbox = _hexToBytes(mailboxVectors['kMailbox'] as String);
      final mustRefuse =
          (mailboxVectors['mustRefuse'] as List<dynamic>).cast<Map<String, dynamic>>();

      expect(mustRefuse, isNotEmpty);
      for (final item in mustRefuse) {
        final name = item['name'] as String;
        final expectedReason = item['expect'] as String;
        final to = LumenMailboxRole.fromWire(item['to'] as String);
        final room = item['room'] as String;
        final body = _hexToBytes(item['body'] as String);

        expect(
          () => LumenRelayCrypto.openMailboxJson(
            kMailbox: kMailbox,
            room: room,
            to: to,
            body: body,
          ),
          throwsA(
            isA<LumenMailboxCipherException>()
                .having((e) => e.reason, 'reason', expectedReason),
          ),
          reason: name,
        );

        expect(
          () => LumenRelayCrypto.openMailboxMap(
            kMailbox: kMailbox,
            room: room,
            to: to,
            body: body,
          ),
          throwsA(
            isA<LumenMailboxCipherException>()
                .having((e) => e.reason, 'reason', expectedReason),
          ),
          reason: '$name (openMailboxMap)',
        );
      }
    });

    test('sealMailboxEnvelope round-trips with random CSPRNG nonces', () {
      final inputs = mailboxVectors['inputs'] as Map<String, dynamic>;
      final room = inputs['room'] as String;
      final kMailbox = _hexToBytes(mailboxVectors['kMailbox'] as String);
      final envelope = <String, dynamic>{
        'contract_version': 1,
        'mutation_id': 'mut-rnd-001',
        'origin_role': 'phone',
        'entity_type': 'task',
        'payload': <String, dynamic>{
          'id': 'task-1',
          'text': 'Ação rápida com UTF-8 çãõ',
          'done': false,
        },
      };

      final bodyA = LumenRelayCrypto.sealMailboxEnvelope(
        kMailbox: kMailbox,
        room: room,
        to: LumenMailboxRole.pc,
        envelope: envelope,
      );
      final bodyB = LumenRelayCrypto.sealMailboxEnvelope(
        kMailbox: kMailbox,
        room: room,
        to: LumenMailboxRole.pc,
        envelope: envelope,
      );

      expect(bodyA.length, greaterThanOrEqualTo(LumenRelayCrypto.mailboxMinBodyBytes));
      expect(bodyA[0], equals(LumenRelayCrypto.mailboxVersion));
      expect(bodyA.sublist(1, 13), isNot(equals(bodyB.sublist(1, 13))));
      expect(bodyA, isNot(equals(bodyB)));

      final decoded = LumenRelayCrypto.openMailboxMap(
        kMailbox: kMailbox,
        room: room,
        to: LumenMailboxRole.pc,
        body: bodyA,
      );
      expect(decoded, equals(envelope));
    });

    test('validates room, max JSON size, non-object JSON, key/nonce sizes, and redacts errors', () {
      final inputs = mailboxVectors['inputs'] as Map<String, dynamic>;
      final validRoom = inputs['room'] as String;
      final kMailbox = _hexToBytes(mailboxVectors['kMailbox'] as String);
      final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i));

      expect(
        () => LumenRelayCrypto.mailboxAad(
          room: 'too-short',
          to: LumenMailboxRole.pc,
        ),
        throwsA(
          isA<LumenMailboxCipherException>()
              .having((e) => e.reason, 'reason', 'invalid_room'),
        ),
      );
      expect(
        () => LumenRelayCrypto.mailboxAad(
          room: 'oKGio6SlpqeoqaqrrK2ur!',
          to: LumenMailboxRole.pc,
        ),
        throwsA(
          isA<LumenMailboxCipherException>()
              .having((e) => e.reason, 'reason', 'invalid_room'),
        ),
      );

      final tooBigJson = '{"a":"${'x' * LumenRelayCrypto.mailboxMaxJsonBytes}"}';
      expect(
        () => LumenRelayCrypto.padMailboxJson(tooBigJson),
        throwsA(
          isA<LumenMailboxCipherException>()
              .having((e) => e.reason, 'reason', 'bad_length'),
        ),
      );

      final arrayBody = LumenRelayCrypto.sealMailboxWithNonce(
        kMailbox: kMailbox,
        room: validRoom,
        to: LumenMailboxRole.phone,
        json: '[1,2,3]',
        nonce: nonce,
      );
      expect(
        () => LumenRelayCrypto.openMailboxJson(
          kMailbox: kMailbox,
          room: validRoom,
          to: LumenMailboxRole.phone,
          body: arrayBody,
        ),
        throwsA(
          isA<LumenMailboxCipherException>()
              .having((e) => e.reason, 'reason', 'bad_json'),
        ),
      );

      expect(
        () => LumenRelayCrypto.sealMailboxWithNonce(
          kMailbox: Uint8List(31),
          room: validRoom,
          to: LumenMailboxRole.pc,
          json: '{}',
          nonce: nonce,
        ),
        throwsArgumentError,
      );
      expect(
        () => LumenRelayCrypto.sealMailboxWithNonce(
          kMailbox: kMailbox,
          room: validRoom,
          to: LumenMailboxRole.pc,
          json: '{}',
          nonce: Uint8List(11),
        ),
        throwsArgumentError,
      );
      expect(
        () => LumenMailboxRole.fromWire('tablet'),
        throwsArgumentError,
      );

      const err = LumenMailboxCipherException('bad_tag', 'Tag check failed.');
      expect(err.toString(), equals('LumenMailboxCipherException(bad_tag): Tag check failed.'));
    });
  });
}
