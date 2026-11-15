import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/data/services/lumen_mailbox_client.dart';
import 'package:memex/data/services/lumen_relay_crypto.dart';
import 'package:memex/domain/models/lumen_pairing.dart';

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
  const room = 'oKGio6SlpqeoqaqrrK2urw';
  final keyB64 = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i));
  final accessB64 = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i + 32));
  final joinProof = LumenRelayCrypto.joinProofFromBase64Url(keyB64);

  LumenPairing buildPairing({
    String relayHost = 'relay.example.workers.dev',
    int relayPort = 443,
    bool relayTls = true,
  }) {
    final scheme = relayTls ? 'wss' : 'ws';
    final defaultPort = relayTls ? 443 : 80;
    final relayUrl = relayPort == defaultPort
        ? '$scheme://$relayHost'
        : '$scheme://$relayHost:$relayPort';
    return LumenPairing(
      host: '192.0.2.10',
      port: 38443,
      fingerprint: List<String>.filled(64, 'a').join(),
      token: 'tok_0123456789abcdef',
      name: 'Desktop-Exemplo',
      relayUrl: relayUrl,
      relayHost: relayHost,
      relayPort: relayPort,
      relayTls: relayTls,
      room: room,
      key: keyB64,
      access: accessB64,
      pairedAtIso: '2026-11-15T00:00:00Z',
    );
  }

  group('LumenMailboxClient', () {
    test('postMessage sends binary octet-stream with auth headers and parses 201 & 200 duplicate', () async {
      final requests = <http.Request>[];
      var responseIndex = 0;
      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          responseIndex++;
          if (responseIndex == 1) {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'seq': 7,
                'id': 'mut-task-001',
                'createdAt': 1763164800000,
                'duplicate': false,
              }),
              201,
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'seq': 7,
              'id': 'mut-task-001',
              'createdAt': 1763164800000,
              'duplicate': true,
            }),
            200,
          );
        }),
      );

      final mailbox = LumenMailboxClient(httpClient: client);
      final pairing = buildPairing();
      final body = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);

      final created = await mailbox.postMessage(
        pairing: pairing,
        joinProof: joinProof,
        mutationId: 'mut-task-001',
        encryptedBody: body,
      );
      final dup = await mailbox.postMessage(
        pairing: pairing,
        joinProof: joinProof,
        mutationId: 'mut-task-001',
        encryptedBody: body,
        to: LumenMailboxRole.phone,
      );

      expect(created.seq, 7);
      expect(created.duplicate, isFalse);
      expect(created.msgId, 'mut-task-001');

      expect(dup.seq, 7);
      expect(dup.duplicate, isTrue);
      expect(dup.msgId, 'mut-task-001');

      expect(requests, hasLength(2));
      final req1 = requests[0];
      expect(req1.method, 'POST');
      expect(
        req1.url.toString(),
        'https://relay.example.workers.dev/v1/mailbox/$room/messages?to=pc',
      );
      expect(req1.headers['Authorization'], 'Bearer $accessB64');
      expect(req1.headers['X-Lumen-Join'], joinProof);
      expect(req1.headers['X-Lumen-Msg-Id'], 'mut-task-001');
      expect(req1.headers['Content-Type'], 'application/octet-stream');
      expect(req1.bodyBytes, equals(body));

      final req2 = requests[1];
      expect(
        req2.url.toString(),
        'https://relay.example.workers.dev/v1/mailbox/$room/messages?to=phone',
      );
      expect(client.closeCalls, 0);
    });

    test('listMessages decodes base64 payloads and honors query parameters', () async {
      final requests = <http.Request>[];
      final cipherA = Uint8List.fromList(List<int>.generate(16, (i) => i + 10));
      final cipherB = Uint8List.fromList(List<int>.generate(16, (i) => i + 40));

      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'messages': <Map<String, dynamic>>[
                <String, dynamic>{
                  'seq': 11,
                  'id': 'mut-task-011',
                  'createdAt': 1763164801000,
                  'sizeBytes': cipherA.length,
                  'payloadB64': base64Encode(cipherA),
                },
                <String, dynamic>{
                  'seq': 12,
                  'id': null,
                  'createdAt': 1763164802000,
                  'sizeBytes': cipherB.length,
                  'payloadB64': base64Encode(cipherB),
                },
              ],
              'latestSeq': 12,
              'pendingCount': 4,
            }),
            200,
          );
        }),
      );

      final mailbox = LumenMailboxClient(httpClient: client);
      final pairing = buildPairing(
        relayHost: '127.0.0.1',
        relayPort: 8787,
        relayTls: false,
      );

      final list = await mailbox.listMessages(
        pairing: pairing,
        joinProof: joinProof,
        afterSeq: 10,
        limit: 25,
        recipient: LumenMailboxRole.phone,
      );

      expect(requests, hasLength(1));
      final req = requests.single;
      expect(req.method, 'GET');
      expect(
        req.url.toString(),
        'http://127.0.0.1:8787/v1/mailbox/$room/messages?for=phone&after=10&limit=25',
      );
      expect(req.headers['Authorization'], 'Bearer $accessB64');
      expect(req.headers['X-Lumen-Join'], joinProof);

      expect(list.latestSeq, 12);
      expect(list.pendingCount, 4);
      expect(list.messages, hasLength(2));
      expect(list.messages[0].seq, 11);
      expect(list.messages[0].msgId, 'mut-task-011');
      expect(list.messages[0].createdAtMs, 1763164801000);
      expect(list.messages[0].sizeBytes, cipherA.length);
      expect(list.messages[0].bodyBytes, equals(cipherA));
      expect(list.messages[1].seq, 12);
      expect(list.messages[1].msgId, isNull);
      expect(list.messages[1].bodyBytes, equals(cipherB));

      // Never print ciphertext bytes in toString().
      expect(
        list.messages[0].toString(),
        isNot(contains(base64Encode(cipherA))),
      );
      expect(client.closeCalls, 0);
    });

    test('ackMessages posts uptoSeq JSON and parses counts', () async {
      final requests = <http.Request>[];
      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ackedUpto': 12,
              'deleted': 2,
              'remaining': 1,
            }),
            200,
          );
        }),
      );

      final mailbox = LumenMailboxClient(httpClient: client);
      final ack = await mailbox.ackMessages(
        pairing: buildPairing(),
        joinProof: joinProof,
        uptoSeq: 12,
        recipient: LumenMailboxRole.pc,
      );

      expect(ack.ackedUpto, 12);
      expect(ack.deleted, 2);
      expect(ack.remaining, 1);

      final req = requests.single;
      expect(req.method, 'POST');
      expect(
        req.url.toString(),
        'https://relay.example.workers.dev/v1/mailbox/$room/ack?for=pc',
      );
      expect(req.headers['Authorization'], 'Bearer $accessB64');
      expect(req.headers['X-Lumen-Join'], joinProof);
      expect(req.headers['Content-Type'], 'application/json');
      expect(jsonDecode(req.body), equals(<String, dynamic>{'uptoSeq': 12}));
      expect(client.closeCalls, 0);
    });

    test('getStats fetches room counters and freePlan limits', () async {
      final requests = <http.Request>[];
      final client = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'pendingPc': 2,
              'pendingPhone': 5,
              'storedBytes': 1024,
              'revoked': false,
              'freePlan': <String, dynamic>{
                'day': '2026-11-15',
                'dailyWrites': 42,
                'dailyWriteLimit': 100000,
                'dailyRequests': 19,
                'roomBytes': 1024,
              },
            }),
            200,
          );
        }),
      );

      final mailbox = LumenMailboxClient(httpClient: client);
      final stats = await mailbox.getStats(
        pairing: buildPairing(),
        joinProof: joinProof,
      );

      expect(stats.pendingPc, 2);
      expect(stats.pendingPhone, 5);
      expect(stats.storedBytes, 1024);
      expect(stats.revoked, isFalse);
      expect(stats.dailyWrites, 42);
      expect(stats.dailyWriteLimit, 100000);
      expect(stats.dailyRequests, 19);
      expect(stats.roomBytes, 1024);

      final req = requests.single;
      expect(req.method, 'GET');
      expect(
        req.url.toString(),
        'https://relay.example.workers.dev/v1/mailbox/$room/stats',
      );
      expect(req.headers['Authorization'], 'Bearer $accessB64');
      expect(req.headers['X-Lumen-Join'], joinProof);
      expect(client.closeCalls, 0);
    });

    test('maps HTTP error status codes to LumenMailboxHttpException flags without leaking secrets', () async {
      final cases = <int, bool Function(LumenMailboxHttpException)>{
        401: (e) => e.isUnauthorized,
        403: (e) => e.isUnauthorized,
        410: (e) => e.isRevoked,
        413: (e) => e.isPayloadTooLarge,
        429: (e) => e.isRateLimited,
        507: (e) => e.isMailboxFull,
      };

      for (final entry in cases.entries) {
        final client = _TrackingClient(
          MockClient(
            (_) async => http.Response('secret-echo-$accessB64', entry.key),
          ),
        );
        final mailbox = LumenMailboxClient(httpClient: client);
        late LumenMailboxHttpException caught;
        try {
          await mailbox.getStats(
            pairing: buildPairing(),
            joinProof: joinProof,
          );
          fail('Expected LumenMailboxHttpException for HTTP ${entry.key}');
        } on LumenMailboxHttpException catch (e) {
          caught = e;
        }
        expect(caught.statusCode, entry.key);
        expect(entry.value(caught), isTrue, reason: 'HTTP ${entry.key}');
        expect(caught.toString(), isNot(contains(accessB64)));
        expect(caught.toString(), isNot(contains(joinProof)));
        expect(caught.toString(), isNot(contains(keyB64)));
        expect(caught.toString(), isNot(contains(room)));
      }
    });

    test('handles timeouts, transport errors, malformed payloads, and invalid arguments safely', () async {
      final timeoutClient = _TrackingClient(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('{}', 200);
        }),
      );
      final timeoutMailbox = LumenMailboxClient(
        httpClient: timeoutClient,
        timeout: const Duration(milliseconds: 15),
      );

      await expectLater(
        () => timeoutMailbox.getStats(
          pairing: buildPairing(),
          joinProof: joinProof,
        ),
        throwsA(
          isA<LumenMailboxHttpException>()
              .having((e) => e.statusCode, 'statusCode', 0),
        ),
      );

      final netErrorClient = _TrackingClient(
        MockClient((_) async {
          throw http.ClientException(
            'Connection refused',
            Uri.parse('https://relay.example.workers.dev/v1/mailbox/$room/stats'),
          );
        }),
      );
      final netMailbox = LumenMailboxClient(httpClient: netErrorClient);
      late LumenMailboxHttpException netErr;
      try {
        await netMailbox.getStats(
          pairing: buildPairing(),
          joinProof: joinProof,
        );
        fail('Expected network LumenMailboxHttpException');
      } on LumenMailboxHttpException catch (e) {
        netErr = e;
      }
      expect(netErr.statusCode, 0);
      expect(netErr.isUnauthorized, isFalse);
      expect(netErr.toString(), isNot(contains(room)));

      final badPayloadClient = _TrackingClient(
        MockClient((_) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'messages': <Map<String, dynamic>>[
                <String, dynamic>{
                  'seq': 1,
                  'id': 'mut-1',
                  'createdAt': 1000,
                  'sizeBytes': 4,
                  'payloadB64': '%%%not-base64%%%',
                },
              ],
              'latestSeq': 1,
              'pendingCount': 1,
            }),
            200,
          );
        }),
      );
      final badPayloadMailbox = LumenMailboxClient(httpClient: badPayloadClient);
      await expectLater(
        () => badPayloadMailbox.listMessages(
          pairing: buildPairing(),
          joinProof: joinProof,
        ),
        throwsA(isA<LumenMailboxHttpException>()),
      );

      expect(
        () => badPayloadMailbox.listMessages(
          pairing: buildPairing(),
          joinProof: joinProof,
          afterSeq: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => badPayloadMailbox.listMessages(
          pairing: buildPairing(),
          joinProof: joinProof,
          limit: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => badPayloadMailbox.listMessages(
          pairing: buildPairing(),
          joinProof: joinProof,
          limit: 101,
        ),
        throwsRangeError,
      );
      expect(
        () => badPayloadMailbox.ackMessages(
          pairing: buildPairing(),
          joinProof: joinProof,
          uptoSeq: -1,
        ),
        throwsArgumentError,
      );
      expect(badPayloadMailbox.toString(), isNot(contains(accessB64)));
    });
  });
}
