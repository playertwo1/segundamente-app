import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/data/services/lumen_pairing_service.dart';
import 'package:memex/data/services/lumen_relay_crypto.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemorySecretStore implements LumenSecretStore {
  final Map<String, String> values = <String, String>{};
  final List<String> deletedKeys = <String>[];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    values.remove(key);
  }
}

class _TrackingClient extends http.BaseClient {
  final http.Client _inner;
  int closeCalls = 0;

  _TrackingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    closeCalls++;
    _inner.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomA = 'oKGio6SlpqeoqaqrrK2urw';
  final roomB = encodeBase64UrlNoPad(
    List<int>.generate(16, (i) => 0x10 + i),
  );
  final keyA = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i));
  final keyB = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i + 64));
  final accessA = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i + 32));
  final accessB = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i + 96));
  final fp = List<String>.filled(64, 'a').join();
  const token = 'tok_0123456789abcdef';

  String buildPairUri({
    String room = '',
    String key = '',
    String access = '',
    String relay = 'wss%3A%2F%2Frelay.example.workers.dev',
    String name = 'Desktop-Exemplo',
  }) {
    final effectiveRoom = room.isEmpty ? roomA : room;
    final effectiveKey = key.isEmpty ? keyA : key;
    final effectiveAccess = access.isEmpty ? accessA : access;
    return 'coucou://pair?v=1&host=192.0.2.10&port=38443&fp=$fp'
        '&token=$token&name=$name&relay=$relay'
        '&room=$effectiveRoom&key=$effectiveKey&access=$effectiveAccess';
  }

  late _InMemorySecretStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _InMemorySecretStore();
  });

  group('device_id stability and recovery', () {
    test('generates UUID v4 once, persists only in secret store, and preserves across operations', () async {
      var generatedCount = 0;
      const fixedUuid = '550e8400-e29b-41d4-a716-446655440000';
      final service = LumenPairingService(
        secretStore: store,
        httpClient: _TrackingClient(
          MockClient((_) async => http.Response('{"revoked":true}', 200)),
        ),
        deviceIdGenerator: () {
          generatedCount++;
          return fixedUuid;
        },
      );

      final initial = await service.loadStatus();
      expect(initial.isPaired, isFalse);
      expect(initial.pairing, isNull);
      expect(initial.deviceId, fixedUuid);
      expect(generatedCount, 1);

      final paired = await service.pairFromUri(buildPairUri());
      expect(paired.isPaired, isTrue);
      expect(paired.deviceId, fixedUuid);
      expect(generatedCount, 1);

      final unlinked = await service.unlink();
      expect(unlinked.hadPairing, isTrue);
      expect(unlinked.remoteRevoked, isTrue);
      expect(
        store.values[LumenPairingService.deviceIdStorageKey],
        fixedUuid,
      );
      expect(
        store.values.containsKey(LumenPairingService.pairingStorageKey),
        isFalse,
      );

      final reloaded = await service.loadStatus();
      expect(reloaded.isPaired, isFalse);
      expect(reloaded.deviceId, fixedUuid);
      expect(generatedCount, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('regenerates device_id when missing or invalid and uses real UUID v4 by default', () async {
      store.values[LumenPairingService.deviceIdStorageKey] = 'not-a-uuid';
      final service = LumenPairingService(secretStore: store);

      final id = await service.ensureDeviceId();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(await service.ensureDeviceId(), id);
    });

    test('loadStatus deletes corrupted pairing JSON while preserving device_id', () async {
      const existingId = '11111111-1111-4111-8111-111111111111';
      store.values[LumenPairingService.deviceIdStorageKey] = existingId;
      store.values[LumenPairingService.pairingStorageKey] = '{not valid json';

      final service = LumenPairingService(secretStore: store);
      final status = await service.loadStatus();

      expect(status.isPaired, isFalse);
      expect(status.pairing, isNull);
      expect(status.deviceId, existingId);
      expect(
        store.values.containsKey(LumenPairingService.pairingStorageKey),
        isFalse,
      );
      expect(
        store.deletedKeys,
        equals(<String>[LumenPairingService.pairingStorageKey]),
      );
    });

    test('loadStatus deletes invalid pairing schema JSON while preserving device_id', () async {
      const existingId = '11111111-1111-4111-8111-111111111111';
      store.values[LumenPairingService.deviceIdStorageKey] = existingId;
      store.values[LumenPairingService.pairingStorageKey] =
          '{"host":"192.0.2.10","port":0}';

      final service = LumenPairingService(secretStore: store);
      final status = await service.loadStatus();

      expect(status.isPaired, isFalse);
      expect(status.deviceId, existingId);
      expect(
        store.values.containsKey(LumenPairingService.pairingStorageKey),
        isFalse,
      );
    });
  });

  group('pairFromUri and room switching', () {
    test('invalid QR throws LumenPairingParseException and leaves previous pairing untouched', () async {
      final requests = <http.Request>[];
      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response('ok', 200);
        }),
      );
      final service = LumenPairingService(
        secretStore: store,
        httpClient: client,
      );

      final first = await service.pairFromUri(buildPairUri());
      final storedBefore = store.values[LumenPairingService.pairingStorageKey];

      await expectLater(
        () => service.pairFromUri('https://example.com/not-coucou'),
        throwsA(isA<LumenPairingParseException>()),
      );

      expect(
        store.values[LumenPairingService.pairingStorageKey],
        storedBefore,
      );
      expect((await service.loadStatus()).pairing, equals(first.pairing));
      expect(requests, isEmpty);
    });

    test('switching to a different room revokes the old room before saving the new pairing', () async {
      final requests = <http.Request>[];
      String? storedDuringRevoke;
      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          storedDuringRevoke =
              store.values[LumenPairingService.pairingStorageKey];
          return http.Response('{"revoked":true}', 200);
        }),
      );
      final service = LumenPairingService(
        secretStore: store,
        httpClient: client,
        now: () => DateTime.utc(2026, 11, 14, 22, 0, 0),
      );

      final first = await service.pairFromUri(buildPairUri(
        room: roomA,
        key: keyA,
        access: accessA,
        relay: 'ws%3A%2F%2F127.0.0.1%3A8787',
      ));
      expect(first.pairing!.room, roomA);

      final second = await service.pairFromUri(buildPairUri(
        room: roomB,
        key: keyB,
        access: accessB,
      ));
      expect(second.pairing!.room, roomB);
      expect(requests, hasLength(1));

      final revokeReq = requests.single;
      expect(revokeReq.method, 'POST');
      expect(
        revokeReq.url.toString(),
        'http://127.0.0.1:8787/v1/mailbox/$roomA/revoke',
      );
      expect(revokeReq.headers['Authorization'], 'Bearer $accessA');
      expect(
        revokeReq.headers['X-Lumen-Join'],
        LumenRelayCrypto.joinProofFromBase64Url(keyA),
      );
      expect(storedDuringRevoke, contains(roomA));
      expect(client.closeCalls, 0);
    });

    test('switching rooms still persists new pairing when old room revoke fails', () async {
      final client = _TrackingClient(
        MockClient((_) async => http.Response('error', 500)),
      );
      final service = LumenPairingService(
        secretStore: store,
        httpClient: client,
      );

      await service.pairFromUri(buildPairUri(room: roomA, key: keyA));
      final updated = await service.pairFromUri(buildPairUri(room: roomB, key: keyB));

      expect(updated.isPaired, isTrue);
      expect(updated.pairing!.room, roomB);
      expect((await service.loadStatus()).pairing!.room, roomB);
    });

    test('re-pairing with the same room does not revoke', () async {
      final requests = <http.Request>[];
      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response('ok', 200);
        }),
      );
      final service = LumenPairingService(
        secretStore: store,
        httpClient: client,
      );

      await service.pairFromUri(buildPairUri(name: 'PC-One'));
      final updated = await service.pairFromUri(buildPairUri(name: 'PC-Two'));

      expect(updated.pairing!.name, 'PC-Two');
      expect(requests, isEmpty);
    });
  });

  group('unlink and remote revocation', () {
    test('unlink when unpaired makes no network call and clears cleanly', () async {
      final requests = <http.Request>[];
      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response('ok', 200);
        }),
      );
      final service = LumenPairingService(
        secretStore: store,
        httpClient: client,
      );

      final result = await service.unlink();
      expect(result.hadPairing, isFalse);
      expect(result.remoteRevoked, isFalse);
      expect(requests, isEmpty);
      expect(client.closeCalls, 0);
    });

    for (final statusCode in [200, 410]) {
      test('unlink sends signed POST /revoke and treats HTTP $statusCode as remoteRevoked=true', () async {
        final requests = <http.Request>[];
        final client = _TrackingClient(
          MockClient((request) async {
            requests.add(request);
            return http.Response('', statusCode);
          }),
        );
        final service = LumenPairingService(
          secretStore: store,
          httpClient: client,
        );

        final paired = await service.pairFromUri(buildPairUri());
        final result = await service.unlink();

        expect(result.hadPairing, isTrue);
        expect(result.remoteRevoked, isTrue);
        expect(requests, hasLength(1));
        final req = requests.single;
        expect(req.method, 'POST');
        expect(
          req.url.toString(),
          'https://relay.example.workers.dev/v1/mailbox/$roomA/revoke',
        );
        expect(req.headers['Authorization'], 'Bearer $accessA');
        expect(
          req.headers['X-Lumen-Join'],
          LumenRelayCrypto.joinProofFromBase64Url(keyA),
        );
        expect(
          store.values.containsKey(LumenPairingService.pairingStorageKey),
          isFalse,
        );
        expect(
          store.values[LumenPairingService.deviceIdStorageKey],
          paired.deviceId,
        );
        expect(client.closeCalls, 0);
      });
    }

    test('unlink still wipes local pairing on HTTP 500, ClientException, and TimeoutException', () async {
      for (final scenario in ['http_500', 'network_error', 'timeout']) {
        final localStore = _InMemorySecretStore();
        final client = _TrackingClient(
          MockClient((_) async {
            if (scenario == 'http_500') {
              return http.Response('server error', 500);
            }
            if (scenario == 'network_error') {
              throw http.ClientException('offline');
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
            return http.Response('too late', 200);
          }),
        );

        final service = LumenPairingService(
          secretStore: localStore,
          httpClient: client,
          revokeTimeout: const Duration(milliseconds: 15),
        );

        final paired = await service.pairFromUri(buildPairUri());
        expect(paired.isPaired, isTrue);

        final result = await service.unlink();
        expect(result.hadPairing, isTrue, reason: scenario);
        expect(result.remoteRevoked, isFalse, reason: scenario);
        expect(
          localStore.values.containsKey(LumenPairingService.pairingStorageKey),
          isFalse,
          reason: scenario,
        );
        expect(
          localStore.values[LumenPairingService.deviceIdStorageKey],
          paired.deviceId,
          reason: scenario,
        );
        expect(client.closeCalls, 0, reason: scenario);
      }
    });

    test('LumenPairingStatus.toString redacts pairing secrets', () async {
      final service = LumenPairingService(secretStore: store);
      final status = await service.pairFromUri(buildPairUri());
      final text = status.toString();

      expect(text, contains(status.deviceId));
      expect(text, contains('[REDACTED]'));
      expect(text, isNot(contains(keyA)));
      expect(text, isNot(contains(accessA)));
      expect(text, isNot(contains(token)));
    });
  });
}
