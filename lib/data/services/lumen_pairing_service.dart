import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:memex/data/services/lumen_relay_crypto.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:memex/utils/secret_storage.dart';
import 'package:uuid/uuid.dart';

/// Abstraction over secure key-value storage for Lumen pairing secrets so unit
/// and widget tests can inject an in-memory store.
abstract interface class LumenSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Safe exception thrown by [SecureLumenSecretStore] without ever including
/// stored secret values or pairing URIs.
class LumenSecretStoreException implements Exception {
  final String message;

  const LumenSecretStoreException(this.message);

  @override
  String toString() => 'LumenSecretStoreException: $message';
}

/// Default [LumenSecretStore] backed by [SecretStorage] (OS keystore).
class SecureLumenSecretStore implements LumenSecretStore {
  const SecureLumenSecretStore();

  @override
  Future<String?> read(String key) async {
    try {
      return await SecretStorage.read(key);
    } on PlatformException catch (e) {
      throw LumenSecretStoreException(
        'Secure storage read failed (${e.code})',
      );
    } catch (_) {
      throw const LumenSecretStoreException('Secure storage read failed');
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await SecretStorage.write(key, value);
    } on PlatformException catch (e) {
      throw LumenSecretStoreException(
        'Secure storage write failed (${e.code})',
      );
    } catch (_) {
      throw const LumenSecretStoreException('Secure storage write failed');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await SecretStorage.delete(key);
    } on PlatformException catch (e) {
      throw LumenSecretStoreException(
        'Secure storage delete failed (${e.code})',
      );
    } catch (_) {
      throw const LumenSecretStoreException('Secure storage delete failed');
    }
  }
}

/// Current pairing snapshot loaded from secure storage.
class LumenPairingStatus {
  final LumenPairing? pairing;
  final String deviceId;

  const LumenPairingStatus({
    this.pairing,
    required this.deviceId,
  });

  bool get isPaired => pairing != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LumenPairingStatus &&
          runtimeType == other.runtimeType &&
          pairing == other.pairing &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(pairing, deviceId);

  @override
  String toString() =>
      'LumenPairingStatus(isPaired: $isPaired, deviceId: $deviceId, pairing: $pairing)';
}

/// Outcome of [LumenPairingService.unlink].
class LumenUnlinkResult {
  final bool remoteRevoked;
  final bool hadPairing;

  const LumenUnlinkResult({
    required this.remoteRevoked,
    required this.hadPairing,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LumenUnlinkResult &&
          runtimeType == other.runtimeType &&
          remoteRevoked == other.remoteRevoked &&
          hadPairing == other.hadPairing;

  @override
  int get hashCode => Object.hash(remoteRevoked, hadPairing);

  @override
  String toString() =>
      'LumenUnlinkResult(hadPairing: $hadPairing, remoteRevoked: $remoteRevoked)';
}

/// Manages Lumen QR pairing validation, OS keystore persistence, stable
/// installation `device_id`, and remote mailbox revocation.
class LumenPairingService {
  static const String pairingStorageKey = 'lumen_pairing_v1';
  static const String deviceIdStorageKey = 'lumen_device_id';
  static const Duration defaultRevokeTimeout = Duration(seconds: 5);

  static final RegExp _uuidV4Regex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final LumenSecretStore _secretStore;
  final http.Client? _httpClient;
  final String Function() _deviceIdGenerator;
  final Duration _revokeTimeout;
  final DateTime Function() _now;

  LumenPairingService({
    LumenSecretStore? secretStore,
    http.Client? httpClient,
    String Function()? deviceIdGenerator,
    Duration revokeTimeout = defaultRevokeTimeout,
    DateTime Function()? now,
  })  : _secretStore = secretStore ?? const SecureLumenSecretStore(),
        _httpClient = httpClient,
        _deviceIdGenerator = deviceIdGenerator ?? _defaultUuidV4,
        _revokeTimeout = revokeTimeout,
        _now = now ?? DateTime.now;

  static String _defaultUuidV4() => const Uuid().v4();

  /// Returns the stable UUID v4 `device_id` from secure storage, generating and
  /// persisting a new one only when missing or invalid.
  Future<String> ensureDeviceId() async {
    final stored = await _secretStore.read(deviceIdStorageKey);
    if (stored != null && _uuidV4Regex.hasMatch(stored)) {
      return stored;
    }
    final generated = _deviceIdGenerator();
    await _secretStore.write(deviceIdStorageKey, generated);
    return generated;
  }

  /// Loads the persisted pairing and guarantees a valid `device_id`.
  /// Corrupted pairing JSON is cleared without removing `lumen_device_id`.
  Future<LumenPairingStatus> loadStatus() async {
    final pairing = await _readStoredPairing(deleteIfCorrupted: true);
    final deviceId = await ensureDeviceId();
    return LumenPairingStatus(
      pairing: pairing,
      deviceId: deviceId,
    );
  }

  /// Validates [raw] before changing any stored state, revokes the previous
  /// mailbox room best-effort when switching rooms, ensures `device_id`, and
  /// persists the new pairing into secure storage.
  Future<LumenPairingStatus> pairFromUri(String raw) async {
    final next = LumenPairing.parseUri(raw, now: _now());
    final previous = await _readStoredPairing(deleteIfCorrupted: false);
    if (previous != null && previous.room != next.room) {
      await _revokeRemoteBestEffort(previous);
    }
    final deviceId = await ensureDeviceId();
    await _secretStore.write(
      pairingStorageKey,
      jsonEncode(next.toJson()),
    );
    return LumenPairingStatus(
      pairing: next,
      deviceId: deviceId,
    );
  }

  /// Revokes the active mailbox room on the relay (best-effort within
  /// [_revokeTimeout]) and always deletes local pairing credentials while
  /// preserving `lumen_device_id`.
  Future<LumenUnlinkResult> unlink() async {
    final current = await _readStoredPairing(deleteIfCorrupted: false);
    final remoteRevoked =
        current != null ? await _revokeRemoteBestEffort(current) : false;
    await _secretStore.delete(pairingStorageKey);
    return LumenUnlinkResult(
      remoteRevoked: remoteRevoked,
      hadPairing: current != null,
    );
  }

  Future<LumenPairing?> _readStoredPairing({
    required bool deleteIfCorrupted,
  }) async {
    final raw = await _secretStore.read(pairingStorageKey);
    if (raw == null) {
      return null;
    }
    if (raw.trim().isEmpty) {
      if (deleteIfCorrupted) {
        await _secretStore.delete(pairingStorageKey);
      }
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        if (deleteIfCorrupted) {
          await _secretStore.delete(pairingStorageKey);
        }
        return null;
      }
      return LumenPairing.fromJson(decoded);
    } on FormatException {
      if (deleteIfCorrupted) {
        await _secretStore.delete(pairingStorageKey);
      }
      return null;
    } on LumenPairingParseException {
      if (deleteIfCorrupted) {
        await _secretStore.delete(pairingStorageKey);
      }
      return null;
    } on TypeError {
      if (deleteIfCorrupted) {
        await _secretStore.delete(pairingStorageKey);
      }
      return null;
    }
  }

  Future<bool> _revokeRemoteBestEffort(LumenPairing pairing) async {
    final ownsClient = _httpClient == null;
    final client = _httpClient ?? http.Client();
    try {
      final uri = Uri.parse(
        '${pairing.httpBaseUrl}/v1/mailbox/${pairing.room}/revoke',
      );
      final joinProof = LumenRelayCrypto.joinProofFromBase64Url(pairing.key);
      final response = await client
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer ${pairing.access}',
              'X-Lumen-Join': joinProof,
            },
          )
          .timeout(_revokeTimeout);
      return response.statusCode == 200 || response.statusCode == 410;
    } catch (_) {
      return false;
    } finally {
      if (ownsClient) {
        client.close();
      }
    }
  }
}
