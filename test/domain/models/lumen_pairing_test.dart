import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/lumen_pairing.dart';

void main() {
  const validRoom = 'oKGio6SlpqeoqaqrrK2urw';
  final validKey = encodeBase64UrlNoPad(
    List<int>.generate(32, (i) => i),
  );
  final validAccess = encodeBase64UrlNoPad(
    List<int>.generate(32, (i) => i + 32),
  );
  final validFpLower = List<String>.filled(64, 'a').join();
  final validFpUpper = List<String>.filled(64, 'A').join();
  const validToken = 'tok_0123456789ABCDEF';
  const validHost = '192.0.2.10';
  const validPort = 38443;
  const validName = 'Desktop-Exemplo';
  const validRelayEncoded = 'wss%3A%2F%2Frelay.example.workers.dev';

  String buildUri({
    String scheme = 'coucou',
    String uriHost = 'pair',
    String? version = '1',
    String? host = validHost,
    String? port = '$validPort',
    String? fp = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    String? token = validToken,
    String? name = validName,
    String? relay = validRelayEncoded,
    String? room = validRoom,
    String? key,
    String? access,
    String suffix = '',
  }) {
    final params = <String>[
      if (version != null) 'v=$version',
      if (host != null) 'host=$host',
      if (port != null) 'port=$port',
      if (fp != null) 'fp=$fp',
      if (token != null) 'token=$token',
      if (name != null) 'name=$name',
      if (relay != null) 'relay=$relay',
      if (room != null) 'room=$room',
      if (key != null || key == null && room != null)
        'key=${key ?? validKey}',
      if (access != null || access == null && room != null)
        'access=${access ?? validAccess}',
    ];
    return '$scheme://$uriHost?${params.join('&')}$suffix';
  }

  String buildRawUri({
    String scheme = 'coucou',
    String uriHost = 'pair',
    Map<String, String?>? overrides,
    String suffix = '',
  }) {
    final fields = <String, String?>{
      'v': '1',
      'host': validHost,
      'port': '$validPort',
      'fp': validFpUpper,
      'token': validToken,
      'name': validName,
      'relay': validRelayEncoded,
      'room': validRoom,
      'key': validKey,
      'access': validAccess,
    };
    if (overrides != null) {
      for (final entry in overrides.entries) {
        if (entry.value == null) {
          fields.remove(entry.key);
        } else {
          fields[entry.key] = entry.value;
        }
      }
    }
    final query = fields.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return '$scheme://$uriHost?$query$suffix';
  }

  group('strict base64url helpers', () {
    test('round-trips byte lengths 0, 1, 2, 3, 16, and 32', () {
      for (final len in [0, 1, 2, 3, 16, 32]) {
        final input = Uint8List.fromList(
          List<int>.generate(len, (i) => (i * 17 + 5) & 0xFF),
        );
        final encoded = encodeBase64UrlNoPad(input);
        expect(encoded, isNot(contains('=')));
        expect(encoded, isNot(contains('+')));
        expect(encoded, isNot(contains('/')));
        expect(
          decodeBase64UrlStrict(encoded, expectedBytes: len),
          equals(input),
        );
      }
      expect(
        decodeBase64UrlStrict(validRoom, expectedBytes: 16),
        equals(Uint8List.fromList(List<int>.generate(16, (i) => 0xa0 + i))),
      );
    });

    test('rejects padding, non-url chars, whitespace, bad lengths, and non-zero trailing bits', () {
      for (final invalid in [
        'A', // length % 4 == 1
        'AA==', // padding
        'AAA=', // padding
        'AB+D', // standard base64 '+'
        'AB/D', // standard base64 '/'
        'AA AA', // whitespace
        'AA\n', // newline
        'AB', // 1 byte + 4 unused bits = 0001 != 0
        'AP', // 1 byte + 4 unused bits = 1111 != 0
        'AAB', // 2 bytes + 2 unused bits = 01 != 0
        'AAC', // 2 bytes + 2 unused bits = 10 != 0
        'AAD', // 2 bytes + 2 unused bits = 11 != 0
        'oKGio6SlpqeoqaqrrK2urx', // last char 'x' has trailing bit 1
      ]) {
        expect(
          () => decodeBase64UrlStrict(invalid),
          throwsFormatException,
          reason: 'Should reject "$invalid"',
        );
      }

      // Flipping the unused trailing bit on a 43-char 32-byte key must fail.
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      final lastChar = validKey[validKey.length - 1];
      final badLastChar = alphabet[alphabet.indexOf(lastChar) | 1];
      final badKey = '${validKey.substring(0, 42)}$badLastChar';
      expect(
        () => decodeBase64UrlStrict(badKey, expectedBytes: 32),
        throwsFormatException,
      );

      expect(
        () => decodeBase64UrlStrict(validRoom, expectedBytes: 32),
        throwsFormatException,
      );
    });
  });

  group('LumenPairing.parseUri valid inputs', () {
    test('parses complete wss:// pairing URI, normalizes fp and exposes httpBaseUrl', () {
      final now = DateTime.utc(2026, 11, 14, 21, 30, 0);
      final raw = '  ${buildRawUri(overrides: {
        'name': 'Desktop%20Exemplo',
        'relay': 'wss%3A%2F%2Frelay.example.workers.dev%2F',
      })}  ';

      final pairing = LumenPairing.parseUri(raw, now: now);

      expect(pairing.host, validHost);
      expect(pairing.port, validPort);
      expect(pairing.fingerprint, validFpLower);
      expect(pairing.token, validToken);
      expect(pairing.name, 'Desktop Exemplo');
      expect(pairing.relayUrl, 'wss://relay.example.workers.dev');
      expect(pairing.relayHost, 'relay.example.workers.dev');
      expect(pairing.relayPort, 443);
      expect(pairing.relayTls, isTrue);
      expect(pairing.httpBaseUrl, 'https://relay.example.workers.dev');
      expect(pairing.room, validRoom);
      expect(pairing.key, validKey);
      expect(pairing.access, validAccess);
      expect(pairing.pairedAtIso, '2026-11-14T21:30:00.000Z');
    });

    test('omits default ports and keeps custom ports on relayUrl and httpBaseUrl', () {
      final wssDefaultPort = LumenPairing.parseUri(
        buildRawUri(overrides: {
          'relay': Uri.encodeComponent('wss://Relay.Example.Workers.Dev:443/'),
        }),
      );
      expect(wssDefaultPort.relayUrl, 'wss://relay.example.workers.dev');
      expect(wssDefaultPort.httpBaseUrl, 'https://relay.example.workers.dev');
      expect(wssDefaultPort.relayPort, 443);

      final wssCustomPort = LumenPairing.parseUri(
        buildRawUri(overrides: {
          'relay': Uri.encodeComponent('wss://relay.example.com:8443/'),
        }),
      );
      expect(wssCustomPort.relayUrl, 'wss://relay.example.com:8443');
      expect(wssCustomPort.httpBaseUrl, 'https://relay.example.com:8443');
      expect(wssCustomPort.relayPort, 8443);

      for (final loopbackCase in [
        (
          input: 'ws://localhost:80/',
          relayUrl: 'ws://localhost',
          httpUrl: 'http://localhost',
          host: 'localhost',
          port: 80,
        ),
        (
          input: 'ws://127.0.0.1:8787',
          relayUrl: 'ws://127.0.0.1:8787',
          httpUrl: 'http://127.0.0.1:8787',
          host: '127.0.0.1',
          port: 8787,
        ),
        (
          input: 'ws://[::1]:8787/',
          relayUrl: 'ws://[::1]:8787',
          httpUrl: 'http://[::1]:8787',
          host: '[::1]',
          port: 8787,
        ),
        (
          input: 'ws://[::1]',
          relayUrl: 'ws://[::1]',
          httpUrl: 'http://[::1]',
          host: '[::1]',
          port: 80,
        ),
      ]) {
        final parsed = LumenPairing.parseUri(
          buildRawUri(overrides: {
            'relay': Uri.encodeComponent(loopbackCase.input),
          }),
        );
        expect(parsed.relayTls, isFalse);
        expect(parsed.relayHost, loopbackCase.host);
        expect(parsed.relayPort, loopbackCase.port);
        expect(parsed.relayUrl, loopbackCase.relayUrl);
        expect(parsed.httpBaseUrl, loopbackCase.httpUrl);
      }
    });

    test('accepts token boundary lengths 16 and 128', () {
      final token16 = 'a' * 16;
      final token128 = 'Z' * 128;
      expect(
        LumenPairing.parseUri(buildRawUri(overrides: {'token': token16})).token,
        token16,
      );
      expect(
        LumenPairing.parseUri(buildRawUri(overrides: {'token': token128})).token,
        token128,
      );
    });
  });

  group('LumenPairing.parseUri rejections', () {
    test('rejects empty, oversized >= 2048, bad scheme/host/version/structure', () {
      expect(
        () => LumenPairing.parseUri(''),
        throwsA(isA<LumenPairingParseException>()),
      );
      expect(
        () => LumenPairing.parseUri('   \n  '),
        throwsA(isA<LumenPairingParseException>()),
      );

      final base = buildRawUri();
      final padNeeded = 2048 - base.length - '&x='.length;
      final exact2048 = '$base&x=${'a' * padNeeded}';
      expect(exact2048.length, 2048);
      expect(
        () => LumenPairing.parseUri(exact2048),
        throwsA(isA<LumenPairingParseException>()),
      );

      final exact2047 = '$base&x=${'a' * (padNeeded - 1)}';
      expect(exact2047.length, 2047);
      expect(LumenPairing.parseUri(exact2047).room, validRoom);

      for (final badUri in [
        buildRawUri(scheme: 'https'),
        buildRawUri(uriHost: 'other'),
        buildRawUri(overrides: {'v': '2'}),
        buildRawUri(overrides: {'v': null}),
        '${buildRawUri()}&v=1', // duplicate param
        '${buildRawUri()}#fragment',
        '${buildRawUri()}#',
        'coucou://user@pair?v=1',
        'coucou://pair:8080?v=1',
        'coucou://pair/extra?v=1',
      ]) {
        expect(
          () => LumenPairing.parseUri(badUri),
          throwsA(isA<LumenPairingParseException>()),
          reason: 'Should reject $badUri',
        );
      }
    });

    test('rejects invalid relay URLs', () {
      for (final badRelay in [
        '',
        'relay.example.workers.dev',
        'https://relay.example.workers.dev',
        'http://127.0.0.1:8787',
        'ws://relay.example.workers.dev',
        'ws://192.168.1.5:8787',
        'ws://localhost.evil.com:8787',
        'wss://',
        'wss://user:pass@relay.example.com',
        'wss://relay.example.com/path',
        'wss://relay.example.com//',
        'wss://relay.example.com/?x=1',
        'wss://relay.example.com#frag',
        'wss://relay example.com',
        ' wss://relay.example.com',
        'wss://-bad.example.com',
        'wss://bad-.example.com',
        'wss://.bad.example.com',
        'wss://bad.example.com.',
        'wss://a..b',
        'wss://relay.example.com:0',
        'wss://relay.example.com:65536',
        'wss://relay.example.com:',
        'wss://relay.example.com:abc',
        'wss://relay.example.com:+443',
        'wss://rélay.example.com',
        'wss://relay.example.com\\x',
        'wss://[2001:db8::1]',
        'wss://${'a' * 250}.com', // 254 > 253
      ]) {
        expect(
          () => LumenPairing.parseUri(
            buildRawUri(overrides: {'relay': Uri.encodeComponent(badRelay)}),
          ),
          throwsA(isA<LumenPairingParseException>()),
          reason: 'Should reject relay "$badRelay"',
        );
      }
      expect(
        () => LumenPairing.parseUri(buildRawUri(overrides: {'relay': null})),
        throwsA(isA<LumenPairingParseException>()),
      );
    });

    test('rejects invalid room, key, access, host, port, fp, token, and name', () {
      final paddedRoom = '${validRoom.substring(0, 20)}==';
      const badTrailingRoom = 'oKGio6SlpqeoqaqrrK2urx';
      final paddedKey = '${validKey.substring(0, 42)}=';
      final stdB64Key = '${validKey.substring(0, 41)}+/';

      final invalidFieldCases = <Map<String, String?>>[
        {'room': null},
        {'room': validRoom.substring(0, 21)},
        {'room': '${validRoom}A'},
        {'room': paddedRoom},
        {'room': badTrailingRoom},
        {'key': null},
        {'key': validKey.substring(0, 42)},
        {'key': paddedKey},
        {'key': stdB64Key},
        {'access': null},
        {'access': validAccess.substring(0, 42)},
        {'access': '${validAccess.substring(0, 42)}='},
        {'host': null},
        {'host': '   '},
        {'port': null},
        {'port': '0'},
        {'port': '-1'},
        {'port': '65536'},
        {'port': 'abc'},
        {'fp': null},
        {'fp': validFpLower.substring(0, 63)},
        {'fp': '${validFpLower}a'},
        {'fp': '${validFpLower.substring(0, 63)}g'},
        {'token': null},
        {'token': 'a' * 15},
        {'token': 'a' * 129},
        {'token': 'tok_with_bad!char123'},
        {'name': null},
        {'name': '%20%20'},
      ];

      for (final override in invalidFieldCases) {
        expect(
          () => LumenPairing.parseUri(buildRawUri(overrides: override)),
          throwsA(isA<LumenPairingParseException>()),
          reason: 'Should reject override $override',
        );
      }
    });
  });

  group('serialization, equality, and secret redaction', () {
    test('toJson / fromJson round-trip preserves values and equality', () {
      final pairing = LumenPairing.parseUri(
        buildUri(key: validKey, access: validAccess),
        now: DateTime.utc(2026, 11, 14, 12, 0, 0),
      );
      final encodedJson = jsonEncode(pairing.toJson());
      final decoded = LumenPairing.fromJson(
        jsonDecode(encodedJson) as Map<String, dynamic>,
      );

      expect(decoded, equals(pairing));
      expect(decoded.hashCode, equals(pairing.hashCode));
    });

    test('fromJson rejects corrupted or inconsistent stored fields', () {
      final validJson = LumenPairing.parseUri(
        buildRawUri(),
        now: DateTime.utc(2026, 11, 14, 12, 0, 0),
      ).toJson();

      for (final mutation in [
        <String, dynamic>{...validJson, 'port': 0},
        <String, dynamic>{...validJson, 'port': '38443'},
        <String, dynamic>{...validJson, 'relayUrl': 'ws://evil.example.com'},
        <String, dynamic>{...validJson, 'relayHost': 'other.example.com'},
        <String, dynamic>{...validJson, 'room': 'short'},
        <String, dynamic>{...validJson, 'key': 'short'},
        <String, dynamic>{...validJson, 'access': 'short'},
        <String, dynamic>{...validJson, 'pairedAtIso': 'not-a-date'},
      ]) {
        expect(
          () => LumenPairing.fromJson(mutation),
          throwsA(isA<LumenPairingParseException>()),
        );
      }
    });

    test('toString and parse exception never leak key, access, or token', () {
      final pairing = LumenPairing.parseUri(buildRawUri());
      final printed = pairing.toString();

      expect(printed, contains('[REDACTED]'));
      expect(printed, contains(validName));
      expect(printed, contains(pairing.relayUrl));
      expect(printed, isNot(contains(validKey)));
      expect(printed, isNot(contains(validAccess)));
      expect(printed, isNot(contains(validToken)));

      late LumenPairingParseException captured;
      try {
        LumenPairing.parseUri(
          buildRawUri(overrides: {'fp': 'invalid'}),
        );
      } on LumenPairingParseException catch (e) {
        captured = e;
      }
      final errorText = captured.toString();
      expect(errorText, isNot(contains(validKey)));
      expect(errorText, isNot(contains(validAccess)));
      expect(errorText, isNot(contains(validToken)));
      expect(errorText, isNot(contains(validRoom)));
    });
  });
}
