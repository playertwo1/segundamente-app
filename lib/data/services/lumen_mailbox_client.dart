import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:memex/data/services/lumen_relay_crypto.dart';
import 'package:memex/domain/models/lumen_pairing.dart';

/// HTTP or transport exception thrown by [LumenMailboxClient].
/// Messages and [toString] never include secrets, headers, or payload bodies.
class LumenMailboxHttpException implements Exception {
  final int statusCode;
  final String message;

  const LumenMailboxHttpException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isRevoked => statusCode == 410;
  bool get isPayloadTooLarge => statusCode == 413;
  bool get isRateLimited => statusCode == 429;
  bool get isMailboxFull => statusCode == 507;

  @override
  String toString() => 'LumenMailboxHttpException($statusCode): $message';
}

/// Result of `POST /v1/mailbox/<room>/messages`.
class LumenMailboxPostResult {
  final int seq;
  final bool duplicate;
  final String? msgId;

  const LumenMailboxPostResult({
    required this.seq,
    required this.duplicate,
    this.msgId,
  });

  @override
  String toString() =>
      'LumenMailboxPostResult(seq: $seq, duplicate: $duplicate, msgId: $msgId)';
}

/// Single opaque ciphertext envelope returned by `GET /v1/mailbox/<room>/messages`.
/// [toString] never prints [bodyBytes].
class LumenMailboxEnvelopeRecord {
  final int seq;
  final String? msgId;
  final int createdAtMs;
  final int sizeBytes;
  final Uint8List bodyBytes;

  const LumenMailboxEnvelopeRecord({
    required this.seq,
    this.msgId,
    required this.createdAtMs,
    required this.sizeBytes,
    required this.bodyBytes,
  });

  @override
  String toString() =>
      'LumenMailboxEnvelopeRecord(seq: $seq, msgId: $msgId, '
      'createdAtMs: $createdAtMs, sizeBytes: $sizeBytes)';
}

/// Result of `GET /v1/mailbox/<room>/messages`.
class LumenMailboxListResult {
  final List<LumenMailboxEnvelopeRecord> messages;
  final int latestSeq;
  final int pendingCount;

  const LumenMailboxListResult({
    required this.messages,
    required this.latestSeq,
    required this.pendingCount,
  });

  @override
  String toString() =>
      'LumenMailboxListResult(messages: ${messages.length}, '
      'latestSeq: $latestSeq, pendingCount: $pendingCount)';
}

/// Result of `POST /v1/mailbox/<room>/ack`.
class LumenMailboxAckResult {
  final int ackedUpto;
  final int deleted;
  final int remaining;

  const LumenMailboxAckResult({
    required this.ackedUpto,
    required this.deleted,
    required this.remaining,
  });

  @override
  String toString() =>
      'LumenMailboxAckResult(ackedUpto: $ackedUpto, '
      'deleted: $deleted, remaining: $remaining)';
}

/// Result of `GET /v1/mailbox/<room>/stats`.
class LumenMailboxStatsResult {
  final int pendingPc;
  final int pendingPhone;
  final int storedBytes;
  final bool revoked;
  final int dailyWrites;
  final int dailyWriteLimit;
  final int dailyRequests;
  final int roomBytes;

  const LumenMailboxStatsResult({
    required this.pendingPc,
    required this.pendingPhone,
    required this.storedBytes,
    required this.revoked,
    required this.dailyWrites,
    required this.dailyWriteLimit,
    required this.dailyRequests,
    required this.roomBytes,
  });

  @override
  String toString() =>
      'LumenMailboxStatsResult(pendingPc: $pendingPc, '
      'pendingPhone: $pendingPhone, storedBytes: $storedBytes, '
      'revoked: $revoked, dailyWrites: $dailyWrites/$dailyWriteLimit, '
      'dailyRequests: $dailyRequests, roomBytes: $roomBytes)';
}

/// HTTP client for Lumen's persistent E2EE mailbox endpoints (`/v1/mailbox/...`).
class LumenMailboxClient {
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const int maxListLimit = 100;

  final http.Client? _httpClient;
  final Duration _timeout;

  const LumenMailboxClient({
    http.Client? httpClient,
    Duration timeout = defaultTimeout,
  })  : _httpClient = httpClient,
        _timeout = timeout;

  /// Enqueues an encrypted `coucou-mailbox/v1` body for [to] with deduplication
  /// key [mutationId] (`X-Lumen-Msg-Id`). Accepts HTTP 200 (duplicate) and 201.
  Future<LumenMailboxPostResult> postMessage({
    required LumenPairing pairing,
    required String joinProof,
    required String mutationId,
    required Uint8List encryptedBody,
    LumenMailboxRole to = LumenMailboxRole.pc,
  }) async {
    final uri = _mailboxUri(
      pairing,
      'messages',
      queryParameters: <String, String>{'to': to.wireName},
    );
    final result = await _sendJson(
      method: 'POST',
      uri: uri,
      pairing: pairing,
      joinProof: joinProof,
      extraHeaders: <String, String>{
        'X-Lumen-Msg-Id': mutationId,
        'Content-Type': 'application/octet-stream',
      },
      body: encryptedBody,
      okStatuses: const <int>{200, 201},
    );
    final json = result.json;
    return LumenMailboxPostResult(
      seq: _requireField<int>(json, 'seq', result.statusCode),
      duplicate: _optionalField<bool>(json, 'duplicate', result.statusCode) ??
          (result.statusCode == 200),
      msgId: _optionalField<String>(json, 'id', result.statusCode),
    );
  }

  /// Lists pending ciphertext envelopes addressed to [recipient] with `seq > afterSeq`.
  Future<LumenMailboxListResult> listMessages({
    required LumenPairing pairing,
    required String joinProof,
    int afterSeq = 0,
    int limit = maxListLimit,
    LumenMailboxRole recipient = LumenMailboxRole.phone,
  }) async {
    if (afterSeq < 0) {
      throw ArgumentError.value(afterSeq, 'afterSeq', 'Must be >= 0');
    }
    if (limit < 1 || limit > maxListLimit) {
      throw RangeError.range(limit, 1, maxListLimit, 'limit');
    }
    final uri = _mailboxUri(
      pairing,
      'messages',
      queryParameters: <String, String>{
        'for': recipient.wireName,
        'after': '$afterSeq',
        'limit': '$limit',
      },
    );
    final result = await _sendJson(
      method: 'GET',
      uri: uri,
      pairing: pairing,
      joinProof: joinProof,
      okStatuses: const <int>{200},
    );
    final json = result.json;
    final rawMessages =
        _requireField<List<dynamic>>(json, 'messages', result.statusCode);
    final messages = <LumenMailboxEnvelopeRecord>[];
    for (final item in rawMessages) {
      if (item is! Map<String, dynamic>) {
        throw LumenMailboxHttpException(
          result.statusCode,
          'Invalid mailbox message item.',
        );
      }
      final payloadB64 =
          _requireField<String>(item, 'payloadB64', result.statusCode);
      final Uint8List bodyBytes;
      try {
        bodyBytes = Uint8List.fromList(base64Decode(payloadB64));
      } on FormatException {
        throw LumenMailboxHttpException(
          result.statusCode,
          'Invalid base64 payload in mailbox response.',
        );
      }
      messages.add(
        LumenMailboxEnvelopeRecord(
          seq: _requireField<int>(item, 'seq', result.statusCode),
          msgId: _optionalField<String>(item, 'id', result.statusCode),
          createdAtMs:
              _requireField<int>(item, 'createdAt', result.statusCode),
          sizeBytes: _requireField<int>(item, 'sizeBytes', result.statusCode),
          bodyBytes: bodyBytes,
        ),
      );
    }
    return LumenMailboxListResult(
      messages: messages,
      latestSeq: _requireField<int>(json, 'latestSeq', result.statusCode),
      pendingCount: _requireField<int>(json, 'pendingCount', result.statusCode),
    );
  }

  /// Acknowledges and deletes all pending messages for [recipient] up to [uptoSeq].
  Future<LumenMailboxAckResult> ackMessages({
    required LumenPairing pairing,
    required String joinProof,
    required int uptoSeq,
    LumenMailboxRole recipient = LumenMailboxRole.phone,
  }) async {
    if (uptoSeq < 0) {
      throw ArgumentError.value(uptoSeq, 'uptoSeq', 'Must be >= 0');
    }
    final uri = _mailboxUri(
      pairing,
      'ack',
      queryParameters: <String, String>{'for': recipient.wireName},
    );
    final result = await _sendJson(
      method: 'POST',
      uri: uri,
      pairing: pairing,
      joinProof: joinProof,
      extraHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{'uptoSeq': uptoSeq}),
      okStatuses: const <int>{200},
    );
    final json = result.json;
    return LumenMailboxAckResult(
      ackedUpto: _requireField<int>(json, 'ackedUpto', result.statusCode),
      deleted: _requireField<int>(json, 'deleted', result.statusCode),
      remaining: _requireField<int>(json, 'remaining', result.statusCode),
    );
  }

  /// Reads pending counts and daily free-plan usage counters for [pairing.room].
  Future<LumenMailboxStatsResult> getStats({
    required LumenPairing pairing,
    required String joinProof,
  }) async {
    final uri = _mailboxUri(pairing, 'stats');
    final result = await _sendJson(
      method: 'GET',
      uri: uri,
      pairing: pairing,
      joinProof: joinProof,
      okStatuses: const <int>{200},
    );
    final json = result.json;
    final freePlan =
        _optionalField<Map<String, dynamic>>(json, 'freePlan', result.statusCode);
    return LumenMailboxStatsResult(
      pendingPc: _requireField<int>(json, 'pendingPc', result.statusCode),
      pendingPhone: _requireField<int>(json, 'pendingPhone', result.statusCode),
      storedBytes: _requireField<int>(json, 'storedBytes', result.statusCode),
      revoked: _requireField<bool>(json, 'revoked', result.statusCode),
      dailyWrites:
          _optionalField<int>(freePlan, 'dailyWrites', result.statusCode) ?? 0,
      dailyWriteLimit:
          _optionalField<int>(freePlan, 'dailyWriteLimit', result.statusCode) ??
              0,
      dailyRequests:
          _optionalField<int>(freePlan, 'dailyRequests', result.statusCode) ??
              0,
      roomBytes:
          _optionalField<int>(freePlan, 'roomBytes', result.statusCode) ?? 0,
    );
  }

  Uri _mailboxUri(
    LumenPairing pairing,
    String endpoint, {
    Map<String, String>? queryParameters,
  }) {
    final base = Uri.parse(
      '${pairing.httpBaseUrl}/v1/mailbox/${pairing.room}/$endpoint',
    );
    return queryParameters == null
        ? base
        : base.replace(queryParameters: queryParameters);
  }

  Future<({int statusCode, Map<String, dynamic> json})> _sendJson({
    required String method,
    required Uri uri,
    required LumenPairing pairing,
    required String joinProof,
    Map<String, String>? extraHeaders,
    Object? body,
    required Set<int> okStatuses,
  }) async {
    final ownsClient = _httpClient == null;
    final client = _httpClient ?? http.Client();
    final headers = <String, String>{
      'Authorization': 'Bearer ${pairing.access}',
      'X-Lumen-Join': joinProof,
      ...?extraHeaders,
    };

    final http.Response response;
    try {
      final Future<http.Response> call = switch (method) {
        'GET' => client.get(uri, headers: headers),
        'POST' => client.post(uri, headers: headers, body: body),
        _ => throw ArgumentError.value(method, 'method', 'Unsupported method'),
      };
      response = await call.timeout(_timeout);
    } on TimeoutException {
      throw const LumenMailboxHttpException(0, 'Mailbox request timed out.');
    } catch (_) {
      // Never propagate raw ClientException/SocketException strings that may embed URLs.
      throw const LumenMailboxHttpException(
        0,
        'Mailbox network request failed.',
      );
    } finally {
      if (ownsClient) {
        client.close();
      }
    }

    if (!okStatuses.contains(response.statusCode)) {
      throw LumenMailboxHttpException(
        response.statusCode,
        _messageForStatus(response.statusCode),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw LumenMailboxHttpException(
        response.statusCode,
        'Invalid mailbox JSON response.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw LumenMailboxHttpException(
        response.statusCode,
        'Mailbox JSON response must be an object.',
      );
    }
    return (statusCode: response.statusCode, json: decoded);
  }

  static String _messageForStatus(int statusCode) {
    return switch (statusCode) {
      400 => 'Malformed mailbox request.',
      401 => 'Mailbox access key rejected.',
      403 => 'Mailbox join proof rejected.',
      404 => 'Mailbox room or endpoint not found.',
      405 => 'Mailbox HTTP method not allowed.',
      410 => 'Mailbox room has been revoked.',
      413 => 'Mailbox payload exceeds size limit.',
      429 => 'Mailbox rate limit exceeded.',
      507 => 'Mailbox storage quota is full.',
      _ => 'Mailbox request failed with HTTP $statusCode.',
    };
  }

  static T _requireField<T>(
    Map<String, dynamic> map,
    String key,
    int statusCode,
  ) {
    final value = map[key];
    if (value is! T) {
      throw LumenMailboxHttpException(
        statusCode,
        'Missing or invalid field "$key".',
      );
    }
    return value;
  }

  static T? _optionalField<T>(
    Map<String, dynamic>? map,
    String key,
    int statusCode,
  ) {
    if (map == null || !map.containsKey(key) || map[key] == null) {
      return null;
    }
    final value = map[key];
    if (value is! T) {
      throw LumenMailboxHttpException(
        statusCode,
        'Invalid field "$key".',
      );
    }
    return value;
  }

  @override
  String toString() => 'LumenMailboxClient(timeout: $_timeout)';
}
