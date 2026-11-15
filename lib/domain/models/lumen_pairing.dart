import 'dart:convert';
import 'dart:typed_data';

/// Exception thrown when a Lumen pairing link or persisted pairing record fails
/// validation. Messages never include raw URI values or secrets.
class LumenPairingParseException implements Exception {
  final String code;
  final String message;

  const LumenPairingParseException(this.code, this.message);

  @override
  String toString() => 'LumenPairingParseException($code): $message';
}

int _base64UrlValue(int codeUnit) {
  if (codeUnit >= 0x41 && codeUnit <= 0x5A) return codeUnit - 0x41;
  if (codeUnit >= 0x61 && codeUnit <= 0x7A) return codeUnit - 0x61 + 26;
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30 + 52;
  if (codeUnit == 0x2D) return 62;
  if (codeUnit == 0x5F) return 63;
  return -1;
}

/// Encodes [bytes] as unpadded URL-safe base64 (`[A-Za-z0-9_-]`).
String encodeBase64UrlNoPad(List<int> bytes) {
  final encoded = base64Url.encode(bytes);
  final padIndex = encoded.indexOf('=');
  return padIndex == -1 ? encoded : encoded.substring(0, padIndex);
}

/// Decodes unpadded URL-safe base64 strictly: accepts only `[A-Za-z0-9_-]`,
/// rejects `=`, `+`, `/`, whitespace, invalid remainder lengths (`len % 4 == 1`),
/// and non-zero unused trailing bits. Never includes [input] in error messages.
Uint8List decodeBase64UrlStrict(String input, {int? expectedBytes}) {
  if (input.length % 4 == 1) {
    throw const FormatException('Invalid base64url length');
  }
  final builder = BytesBuilder(copy: false);
  for (var i = 0; i < input.length; i += 4) {
    final remaining = input.length - i;
    final chunkLen = remaining < 4 ? remaining : 4;
    var acc = 0;
    for (var j = 0; j < chunkLen; j++) {
      final value = _base64UrlValue(input.codeUnitAt(i + j));
      if (value < 0) {
        throw const FormatException('Invalid base64url character');
      }
      acc |= value << (18 - 6 * j);
    }
    final take = (chunkLen * 6) ~/ 8;
    final unusedBits = chunkLen * 6 - take * 8;
    if (unusedBits > 0) {
      final trailing = (acc >> (24 - chunkLen * 6)) & ((1 << unusedBits) - 1);
      if (trailing != 0) {
        throw const FormatException('Non-zero base64url trailing bits');
      }
    }
    builder.addByte((acc >> 16) & 0xFF);
    if (take >= 2) {
      builder.addByte((acc >> 8) & 0xFF);
    }
    if (take >= 3) {
      builder.addByte(acc & 0xFF);
    }
  }
  final bytes = builder.takeBytes();
  if (expectedBytes != null && bytes.length != expectedBytes) {
    throw FormatException(
      'Unexpected base64url byte length: expected $expectedBytes, got ${bytes.length}',
    );
  }
  return bytes;
}

class _RelayTarget {
  final bool tls;
  final String host;
  final int port;
  final String displayUrl;

  const _RelayTarget({
    required this.tls,
    required this.host,
    required this.port,
    required this.displayUrl,
  });
}

/// Validated pairing credentials from a Lumen `coucou://pair?...` link.
class LumenPairing {
  /// Exclusive maximum raw pairing URI length (`raw.length < 2048`).
  static const int maxUriLength = 2048;
  static const String expectedScheme = 'coucou';
  static const String expectedHost = 'pair';
  static const String expectedVersion = '1';
  static const int roomBytes = 16;
  static const int roomEncodedLength = 22;
  static const int keyBytes = 32;
  static const int keyEncodedLength = 43;
  static const int accessBytes = 32;
  static const int accessEncodedLength = 43;
  static const int fingerprintHexLength = 64;
  static const int minTokenLength = 16;
  static const int maxTokenLength = 128;
  static const int maxRelayHostLength = 253;

  static final RegExp _controlCharsRegex = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _whitespaceRegex = RegExp(r'\s');
  static final RegExp _digitsOnlyRegex = RegExp(r'^[0-9]+$');
  static final RegExp _fingerprintRegex = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _tokenRegex = RegExp(r'^[A-Za-z0-9_-]{16,128}$');
  static final RegExp _asciiHostRegex = RegExp(r'^[A-Za-z0-9.-]+$');

  final String host;
  final int port;
  final String fingerprint;
  final String token;
  final String name;
  final String relayUrl;
  final String relayHost;
  final int relayPort;
  final bool relayTls;
  final String room;
  final String key;
  final String access;
  final String pairedAtIso;

  const LumenPairing({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.token,
    required this.name,
    required this.relayUrl,
    required this.relayHost,
    required this.relayPort,
    required this.relayTls,
    required this.room,
    required this.key,
    required this.access,
    required this.pairedAtIso,
  });

  /// HTTP(S) base URL corresponding to [relayUrl], omitting standard ports
  /// (`443` for `https://`, `80` for `http://`).
  String get httpBaseUrl {
    final scheme = relayTls ? 'https' : 'http';
    final defaultPort = relayTls ? 443 : 80;
    return relayPort == defaultPort
        ? '$scheme://$relayHost'
        : '$scheme://$relayHost:$relayPort';
  }

  /// Parses and strictly validates a `coucou://pair?...` URI.
  factory LumenPairing.parseUri(String raw, {DateTime? now}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const LumenPairingParseException(
        'empty_uri',
        'Pairing link cannot be empty.',
      );
    }
    if (raw.length >= maxUriLength) {
      throw const LumenPairingParseException(
        'uri_too_long',
        'Pairing link exceeds maximum length.',
      );
    }
    if (_controlCharsRegex.hasMatch(trimmed)) {
      throw const LumenPairingParseException(
        'invalid_uri',
        'Pairing link contains invalid control characters.',
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const LumenPairingParseException(
        'invalid_uri',
        'Pairing link is not a valid coucou://pair URI.',
      );
    }
    if (uri.scheme != expectedScheme || uri.host != expectedHost) {
      throw const LumenPairingParseException(
        'invalid_scheme',
        'Pairing link must use coucou://pair.',
      );
    }

    final version = _singleParam(uri, 'v');
    if (version != expectedVersion) {
      throw const LumenPairingParseException(
        'unsupported_version',
        'Unsupported pairing link version.',
      );
    }

    final host = _validateLanHost(_singleParam(uri, 'host'));
    final port = _validatePort(_singleParam(uri, 'port'));
    final fingerprint = _validateFingerprint(_singleParam(uri, 'fp'));
    final token = _validateToken(_singleParam(uri, 'token'));
    final name = _validateName(_singleParam(uri, 'name'));
    final relay = _parseRelayTarget(_singleParam(uri, 'relay'));
    final room = _validateBase64UrlField(
      _singleParam(uri, 'room'),
      expectedChars: roomEncodedLength,
      expectedBytes: roomBytes,
      code: 'invalid_room',
      message: 'Pairing link has an invalid room identifier.',
    );
    final key = _validateBase64UrlField(
      _singleParam(uri, 'key'),
      expectedChars: keyEncodedLength,
      expectedBytes: keyBytes,
      code: 'invalid_key',
      message: 'Pairing link has an invalid pairing key.',
    );
    final access = _validateBase64UrlField(
      _singleParam(uri, 'access'),
      expectedChars: accessEncodedLength,
      expectedBytes: accessBytes,
      code: 'invalid_access',
      message: 'Pairing link has an invalid relay access key.',
    );

    final pairedAtIso = (now ?? DateTime.now()).toUtc().toIso8601String();
    return LumenPairing(
      host: host,
      port: port,
      fingerprint: fingerprint,
      token: token,
      name: name,
      relayUrl: relay.displayUrl,
      relayHost: relay.host,
      relayPort: relay.port,
      relayTls: relay.tls,
      room: room,
      key: key,
      access: access,
      pairedAtIso: pairedAtIso,
    );
  }

  /// Deserializes and validates a pairing record read from secure storage.
  factory LumenPairing.fromJson(Map<String, dynamic> json) {
    final host = _validateLanHost(_requireString(json, 'host', 'invalid_host'));
    final rawPort = json['port'];
    if (rawPort is! int || rawPort < 1 || rawPort > 65535) {
      throw const LumenPairingParseException(
        'invalid_port',
        'Stored pairing has an invalid port.',
      );
    }
    final fingerprint = _validateFingerprint(
      _requireString(json, 'fingerprint', 'invalid_fingerprint'),
    );
    final token = _validateToken(
      _requireString(json, 'token', 'invalid_token'),
    );
    final name = _validateName(_requireString(json, 'name', 'invalid_name'));
    final relay = _parseRelayTarget(
      _requireString(json, 'relayUrl', 'invalid_relay'),
    );
    if (json.containsKey('relayHost') && json['relayHost'] != relay.host) {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Stored relay host does not match relay URL.',
      );
    }
    if (json.containsKey('relayPort') && json['relayPort'] != relay.port) {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Stored relay port does not match relay URL.',
      );
    }
    if (json.containsKey('relayTls') && json['relayTls'] != relay.tls) {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Stored relay TLS flag does not match relay URL.',
      );
    }
    final room = _validateBase64UrlField(
      _requireString(json, 'room', 'invalid_room'),
      expectedChars: roomEncodedLength,
      expectedBytes: roomBytes,
      code: 'invalid_room',
      message: 'Stored pairing has an invalid room identifier.',
    );
    final key = _validateBase64UrlField(
      _requireString(json, 'key', 'invalid_key'),
      expectedChars: keyEncodedLength,
      expectedBytes: keyBytes,
      code: 'invalid_key',
      message: 'Stored pairing has an invalid pairing key.',
    );
    final access = _validateBase64UrlField(
      _requireString(json, 'access', 'invalid_access'),
      expectedChars: accessEncodedLength,
      expectedBytes: accessBytes,
      code: 'invalid_access',
      message: 'Stored pairing has an invalid relay access key.',
    );
    final pairedAtIso = _requireString(json, 'pairedAtIso', 'invalid_uri').trim();
    if (pairedAtIso.isEmpty || DateTime.tryParse(pairedAtIso) == null) {
      throw const LumenPairingParseException(
        'invalid_uri',
        'Stored pairing has an invalid timestamp.',
      );
    }

    return LumenPairing(
      host: host,
      port: rawPort,
      fingerprint: fingerprint,
      token: token,
      name: name,
      relayUrl: relay.displayUrl,
      relayHost: relay.host,
      relayPort: relay.port,
      relayTls: relay.tls,
      room: room,
      key: key,
      access: access,
      pairedAtIso: pairedAtIso,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'host': host,
        'port': port,
        'fingerprint': fingerprint,
        'token': token,
        'name': name,
        'relayUrl': relayUrl,
        'relayHost': relayHost,
        'relayPort': relayPort,
        'relayTls': relayTls,
        'room': room,
        'key': key,
        'access': access,
        'pairedAtIso': pairedAtIso,
      };

  static String? _singleParam(Uri uri, String name) {
    final values = uri.queryParametersAll[name];
    if (values == null || values.length != 1) {
      return null;
    }
    return values.first;
  }

  static String _requireString(
    Map<String, dynamic> json,
    String field,
    String errorCode,
  ) {
    final value = json[field];
    if (value is! String) {
      throw LumenPairingParseException(
        errorCode,
        'Stored pairing is missing $field.',
      );
    }
    return value;
  }

  static String _validateLanHost(String? rawHost) {
    final trimmed = rawHost?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw const LumenPairingParseException(
        'invalid_host',
        'Pairing link is missing a valid host.',
      );
    }
    return trimmed;
  }

  static int _validatePort(String? rawPort) {
    if (rawPort == null || !_digitsOnlyRegex.hasMatch(rawPort)) {
      throw const LumenPairingParseException(
        'invalid_port',
        'Pairing link has an invalid port.',
      );
    }
    final parsed = int.tryParse(rawPort);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      throw const LumenPairingParseException(
        'invalid_port',
        'Pairing link port must be between 1 and 65535.',
      );
    }
    return parsed;
  }

  static String _validateFingerprint(String? rawFp) {
    if (rawFp == null || !_fingerprintRegex.hasMatch(rawFp)) {
      throw const LumenPairingParseException(
        'invalid_fingerprint',
        'Pairing link has an invalid certificate fingerprint.',
      );
    }
    return rawFp.toLowerCase();
  }

  static String _validateToken(String? rawToken) {
    if (rawToken == null || !_tokenRegex.hasMatch(rawToken)) {
      throw const LumenPairingParseException(
        'invalid_token',
        'Pairing link has an invalid pairing token.',
      );
    }
    return rawToken;
  }

  static String _validateName(String? rawName) {
    final trimmed = rawName?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw const LumenPairingParseException(
        'invalid_name',
        'Pairing link is missing a device name.',
      );
    }
    return trimmed;
  }

  static String _validateBase64UrlField(
    String? raw, {
    required int expectedChars,
    required int expectedBytes,
    required String code,
    required String message,
  }) {
    if (raw == null || raw.length != expectedChars) {
      throw LumenPairingParseException(code, message);
    }
    try {
      decodeBase64UrlStrict(raw, expectedBytes: expectedBytes);
    } on FormatException {
      throw LumenPairingParseException(code, message);
    }
    return raw;
  }

  static _RelayTarget _parseRelayTarget(String? rawRelay) {
    if (rawRelay == null ||
        rawRelay.isEmpty ||
        _whitespaceRegex.hasMatch(rawRelay)) {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Pairing link has an invalid relay URL.',
      );
    }

    final bool tls;
    String rest;
    if (rawRelay.startsWith('wss://')) {
      tls = true;
      rest = rawRelay.substring(6);
    } else if (rawRelay.startsWith('ws://')) {
      tls = false;
      rest = rawRelay.substring(5);
    } else {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Relay URL must start with wss:// or loopback ws://.',
      );
    }

    if (rest.endsWith('/')) {
      rest = rest.substring(0, rest.length - 1);
    }
    if (rest.isEmpty ||
        rest.contains('/') ||
        rest.contains('?') ||
        rest.contains('#') ||
        rest.contains('@') ||
        rest.contains('\\')) {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Relay URL must contain only scheme, host, and optional port.',
      );
    }

    final defaultPort = tls ? 443 : 80;
    final String host;
    final int port;

    if (rest.startsWith('[')) {
      final closeBracket = rest.indexOf(']');
      if (closeBracket <= 1) {
        throw const LumenPairingParseException(
          'invalid_relay',
          'Relay URL has an invalid IPv6 host.',
        );
      }
      final bracketedHost = rest.substring(0, closeBracket + 1);
      if (bracketedHost != '[::1]') {
        throw const LumenPairingParseException(
          'invalid_relay',
          'Only [::1] is supported as a bracketed IPv6 relay host.',
        );
      }
      host = bracketedHost;
      final suffix = rest.substring(closeBracket + 1);
      if (suffix.isEmpty) {
        port = defaultPort;
      } else if (suffix.startsWith(':')) {
        port = _parseRelayPort(suffix.substring(1));
      } else {
        throw const LumenPairingParseException(
          'invalid_relay',
          'Relay URL has an invalid authority.',
        );
      }
    } else {
      if (rest.contains(']')) {
        throw const LumenPairingParseException(
          'invalid_relay',
          'Relay URL has an invalid host.',
        );
      }
      final colonIndex = rest.indexOf(':');
      final String rawHost;
      if (colonIndex != -1) {
        if (rest.indexOf(':', colonIndex + 1) != -1) {
          throw const LumenPairingParseException(
            'invalid_relay',
            'Relay URL has an invalid host or port.',
          );
        }
        rawHost = rest.substring(0, colonIndex);
        final rawPort = rest.substring(colonIndex + 1);
        if (rawHost.isEmpty || rawPort.isEmpty) {
          throw const LumenPairingParseException(
            'invalid_relay',
            'Relay URL has an invalid host or port.',
          );
        }
        port = _parseRelayPort(rawPort);
      } else {
        rawHost = rest;
        port = defaultPort;
      }

      if (!_isValidAsciiRelayHost(rawHost)) {
        throw const LumenPairingParseException(
          'invalid_relay',
          'Relay URL has an invalid hostname.',
        );
      }
      host = rawHost.toLowerCase();
    }

    if (!tls &&
        host != 'localhost' &&
        host != '127.0.0.1' &&
        host != '[::1]') {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Plain ws:// relay is allowed only for loopback addresses.',
      );
    }

    final scheme = tls ? 'wss' : 'ws';
    final displayUrl =
        port == defaultPort ? '$scheme://$host' : '$scheme://$host:$port';
    return _RelayTarget(
      tls: tls,
      host: host,
      port: port,
      displayUrl: displayUrl,
    );
  }

  static int _parseRelayPort(String rawPort) {
    if (!_digitsOnlyRegex.hasMatch(rawPort)) {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Relay URL has an invalid port.',
      );
    }
    final port = int.tryParse(rawPort);
    if (port == null || port < 1 || port > 65535) {
      throw const LumenPairingParseException(
        'invalid_relay',
        'Relay URL port must be between 1 and 65535.',
      );
    }
    return port;
  }

  static bool _isValidAsciiRelayHost(String host) {
    if (host.isEmpty ||
        host.length > maxRelayHostLength ||
        !_asciiHostRegex.hasMatch(host) ||
        host.startsWith('.') ||
        host.endsWith('.') ||
        host.startsWith('-') ||
        host.endsWith('-') ||
        host.contains('..')) {
      return false;
    }
    final labels = host.split('.');
    return labels.every(
      (label) =>
          label.isNotEmpty &&
          !label.startsWith('-') &&
          !label.endsWith('-'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LumenPairing &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          fingerprint == other.fingerprint &&
          token == other.token &&
          name == other.name &&
          relayUrl == other.relayUrl &&
          relayHost == other.relayHost &&
          relayPort == other.relayPort &&
          relayTls == other.relayTls &&
          room == other.room &&
          key == other.key &&
          access == other.access &&
          pairedAtIso == other.pairedAtIso;

  @override
  int get hashCode => Object.hash(
        host,
        port,
        fingerprint,
        token,
        name,
        relayUrl,
        relayHost,
        relayPort,
        relayTls,
        room,
        key,
        access,
        pairedAtIso,
      );

  @override
  String toString() =>
      'LumenPairing(name: $name, host: $host:$port, relayUrl: $relayUrl, '
      'room: $room, fingerprint: $fingerprint, '
      'token: [REDACTED], key: [REDACTED], access: [REDACTED], '
      'pairedAtIso: $pairedAtIso)';
}
