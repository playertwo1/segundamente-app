import 'dart:convert';

const String kEsp32MqttPairingType = 'sm-mqtt';
const int kEsp32MqttPairingVersion = 1;
const int kEsp32MqttDefaultTlsPort = 8883;

final RegExp _kMqttsUriPattern = RegExp(r'^mqtts://([^/:?#@\s]+)(?::(\d{1,5}))?$');
final RegExp _kRoomPattern = RegExp(r'^[a-z0-9]{12}$');
final RegExp _kKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

enum Esp32PairingError {
  notJson,
  wrongType,
  unsupportedVersion,
  badUri,
  missingCredentials,
  badRoom,
  badKey,
}

class Esp32PairingParseResult {
  const Esp32PairingParseResult._({this.pairing, this.error});

  const Esp32PairingParseResult.ok(Esp32MqttPairing pairing)
      : this._(pairing: pairing);

  const Esp32PairingParseResult.failed(Esp32PairingError error)
      : this._(error: error);

  final Esp32MqttPairing? pairing;
  final Esp32PairingError? error;
}

/// Pairing data read from the board QR code (PROTOCOLO.md, "Pareamento").
/// [toString] never shows the password or the room key.
class Esp32MqttPairing {
  const Esp32MqttPairing({
    required this.uri,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.room,
    required this.roomKey,
  });

  final String uri;
  final String host;
  final int port;
  final String username;
  final String password;

  /// Room id (`sala`), 12 characters `[a-z0-9]`.
  final String room;

  /// Room key text exactly as received (64 hex characters).
  final String roomKey;

  /// Same JSON shape as the QR code.
  Map<String, dynamic> toJson() => <String, dynamic>{
        't': kEsp32MqttPairingType,
        'v': kEsp32MqttPairingVersion,
        'uri': uri,
        'u': username,
        'p': password,
        'sala': room,
        'k': roomKey,
      };

  static Esp32PairingParseResult parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } catch (_) {
      return const Esp32PairingParseResult.failed(Esp32PairingError.notJson);
    }
    if (decoded is! Map) {
      return const Esp32PairingParseResult.failed(Esp32PairingError.notJson);
    }

    if (decoded['t'] != kEsp32MqttPairingType) {
      return const Esp32PairingParseResult.failed(Esp32PairingError.wrongType);
    }
    final version = decoded['v'];
    if (version is! int || version != kEsp32MqttPairingVersion) {
      return const Esp32PairingParseResult.failed(
        Esp32PairingError.unsupportedVersion,
      );
    }

    final uriRaw = decoded['uri'];
    final match = uriRaw is String ? _kMqttsUriPattern.firstMatch(uriRaw) : null;
    if (uriRaw is! String || match == null) {
      return const Esp32PairingParseResult.failed(Esp32PairingError.badUri);
    }
    final host = match.group(1)!;
    final portText = match.group(2);
    final port = portText == null ? kEsp32MqttDefaultTlsPort : int.parse(portText);
    if (port < 1 || port > 65535) {
      return const Esp32PairingParseResult.failed(Esp32PairingError.badUri);
    }

    final user = decoded['u'];
    final password = decoded['p'];
    if (user is! String ||
        user.isEmpty ||
        password is! String ||
        password.isEmpty) {
      return const Esp32PairingParseResult.failed(
        Esp32PairingError.missingCredentials,
      );
    }

    final room = decoded['sala'];
    if (room is! String || !_kRoomPattern.hasMatch(room)) {
      return const Esp32PairingParseResult.failed(Esp32PairingError.badRoom);
    }

    final key = decoded['k'];
    if (key is! String || !_kKeyPattern.hasMatch(key)) {
      return const Esp32PairingParseResult.failed(Esp32PairingError.badKey);
    }

    return Esp32PairingParseResult.ok(
      Esp32MqttPairing(
        uri: uriRaw,
        host: host,
        port: port,
        username: user,
        password: password,
        room: room,
        roomKey: key,
      ),
    );
  }

  @override
  String toString() => 'Esp32MqttPairing(host: $host, sala: $room)';
}
