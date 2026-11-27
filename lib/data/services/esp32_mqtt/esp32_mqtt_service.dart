import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_pairing.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/secret_storage.dart';

const String kEsp32MqttPairingSecret = 'esp32_mqtt_pairing_v1';

const String _kPresenceCelular = 'presenca/celular';
const String _kPresencePlaca = 'presenca/placa';
const String _kPresencePrefix = 'presenca/';

enum Esp32MqttLinkState { notPaired, disconnected, connecting, connected }

class Esp32MqttStatus {
  const Esp32MqttStatus({
    this.paired = false,
    this.link = Esp32MqttLinkState.notPaired,
    this.boardOnline = false,
    this.keyRejected = false,
    this.lastError,
  });

  final bool paired;
  final Esp32MqttLinkState link;
  final bool boardOnline;

  /// The board sent a message that fails authentication with our key, which
  /// means the key was revoked on the board ("Revogar").
  final bool keyRejected;
  final Esp32MqttConnectResult? lastError;

  Esp32MqttStatus copyWith({
    bool? paired,
    Esp32MqttLinkState? link,
    bool? boardOnline,
    bool? keyRejected,
    Esp32MqttConnectResult? lastError,
    bool clearLastError = false,
  }) {
    return Esp32MqttStatus(
      paired: paired ?? this.paired,
      link: link ?? this.link,
      boardOnline: boardOnline ?? this.boardOnline,
      keyRejected: keyRejected ?? this.keyRejected,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Decoded message from the room, without the `sm/<sala>/` prefix.
class Esp32MqttMessage {
  const Esp32MqttMessage({
    required this.suffix,
    required this.plaintext,
    required this.from,
    required this.retained,
  });

  /// Topic relative to the room, e.g. `tarefas/esp-1a2b3c`.
  final String suffix;

  /// Null when the payload was empty (for example, a cleared retained task).
  final String? plaintext;
  final String? from;
  final bool retained;
}

/// Secret store seam so tests do not need the platform keystore.
abstract class Esp32MqttSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureEsp32MqttSecretStore implements Esp32MqttSecretStore {
  const SecureEsp32MqttSecretStore();

  @override
  Future<String?> read(String key) => SecretStorage.read(key);

  @override
  Future<void> write(String key, String value) => SecretStorage.write(key, value);

  @override
  Future<void> delete(String key) => SecretStorage.delete(key);
}

/// Connection, presence and decryption for the MQTT link with the ESP32 board.
class Esp32MqttService {
  Esp32MqttService({
    Esp32MqttTransport Function()? transportFactory,
    Esp32MqttSecretStore? secretStore,
    Random? random,
    this.initialBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 5),
    Timer Function(Duration, void Function())? timerFactory,
  })  : _transportFactory =
            transportFactory ?? (() => MqttClientEsp32Transport()),
        _secretStore = secretStore ?? const SecureEsp32MqttSecretStore(),
        _random = random ?? Random.secure(),
        _timerFactory = timerFactory ?? _defaultTimer,
        _nextBackoff = initialBackoff;

  static final Esp32MqttService instance = Esp32MqttService();
  static final _logger = getLogger('Esp32MqttService');

  final Duration initialBackoff;
  final Duration maxBackoff;

  final Esp32MqttTransport Function() _transportFactory;
  final Esp32MqttSecretStore _secretStore;
  final Random _random;
  final Timer Function(Duration, void Function()) _timerFactory;

  final ValueNotifier<Esp32MqttStatus> _status =
      ValueNotifier<Esp32MqttStatus>(const Esp32MqttStatus());
  final StreamController<Esp32MqttMessage> _messages =
      StreamController<Esp32MqttMessage>.broadcast();
  final StreamController<void> _connected = StreamController<void>.broadcast();

  Esp32MqttPairing? _pairing;
  Esp32RoomCrypto? _crypto;
  Esp32MqttTransport? _transport;
  StreamSubscription<Esp32MqttIncomingRaw>? _incomingSub;
  StreamSubscription<void>? _dropSub;
  Future<bool>? _connectInFlight;
  Timer? _reconnectTimer;
  Duration _nextBackoff;
  bool _wantConnected = false;

  /// Bumped on every disconnect or pairing change, so an attempt that
  /// finishes late discards its own connection.
  int _generation = 0;

  ValueListenable<Esp32MqttStatus> get status => _status;

  Stream<Esp32MqttMessage> get messages => _messages.stream;

  /// Fires after each successful connection, once presence and subscriptions
  /// are in place.
  Stream<void> get onConnected => _connected.stream;

  /// Full topic for a suffix of the paired room.
  String topic(String suffix) {
    final pairing = _pairing;
    if (pairing == null) throw StateError('not_paired');
    return _fullTopic(pairing, suffix);
  }

  /// Loads a stored pairing. Does not connect.
  Future<void> init() async {
    final stored = await _secretStore.read(kEsp32MqttPairingSecret);
    Esp32MqttPairing? pairing;
    if (stored != null) {
      pairing = Esp32MqttPairing.parse(stored).pairing;
      if (pairing == null) {
        _logger.warning('Stored MQTT pairing is unreadable; treating as unpaired');
      }
    }
    _adoptPairing(pairing);
  }

  /// Validates the QR text. On error, nothing is stored. On success, replaces
  /// any previous pairing and connects.
  Future<Esp32PairingError?> pairFromCode(String raw) async {
    final parsed = Esp32MqttPairing.parse(raw);
    final pairing = parsed.pairing;
    if (pairing == null) return parsed.error ?? Esp32PairingError.notJson;

    await disconnect();
    await _secretStore.write(
      kEsp32MqttPairingSecret,
      jsonEncode(pairing.toJson()),
    );
    _adoptPairing(pairing);
    await connect();
    return null;
  }

  /// Disconnects, then removes the stored pairing.
  Future<void> forget() async {
    await disconnect();
    await _secretStore.delete(kEsp32MqttPairingSecret);
    _adoptPairing(null);
  }

  /// Idempotent. Returns false when not paired or when the attempt fails.
  Future<bool> connect() async {
    final pairing = _pairing;
    if (pairing == null) {
      _wantConnected = false;
      return false;
    }
    _wantConnected = true;
    if (_status.value.link == Esp32MqttLinkState.connected) return true;
    final inFlight = _connectInFlight;
    if (inFlight != null) return inFlight;

    final attempt = _runConnect(pairing, _generation);
    _connectInFlight = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_connectInFlight, attempt)) _connectInFlight = null;
    }
  }

  /// Marks the connection as not wanted, publishes presence `0` (retained)
  /// and disconnects. Cancels any pending reconnect.
  Future<void> disconnect() async {
    _wantConnected = false;
    _generation++;
    _connectInFlight = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final pairing = _pairing;
    final transport = _transport;
    if (pairing != null && transport != null && transport.isConnected) {
      await transport.publish(
        _fullTopic(pairing, _kPresenceCelular),
        _bytes('0'),
        retain: true,
      );
    }
    await transport?.disconnect();
    _setStatus(
      link: pairing == null ? null : Esp32MqttLinkState.disconnected,
      boardOnline: false,
    );
  }

  /// Seals [plaintext] for the room with `from: celular` and publishes it.
  Future<bool> publishEncrypted(
    String suffix,
    String plaintext, {
    bool retain = false,
  }) async {
    final pairing = _pairing;
    final crypto = _crypto;
    final transport = _transport;
    if (pairing == null ||
        crypto == null ||
        transport == null ||
        !transport.isConnected) {
      return false;
    }
    final envelope = crypto.seal(from: kEsp32FromPhone, plaintext: plaintext);
    return transport.publish(
      _fullTopic(pairing, suffix),
      _bytes(envelope),
      retain: retain,
    );
  }

  /// Publishes an empty retained payload, which clears the topic.
  Future<bool> publishEmptyRetained(String suffix) async {
    final pairing = _pairing;
    final transport = _transport;
    if (pairing == null || transport == null || !transport.isConnected) {
      return false;
    }
    return transport.publish(
      _fullTopic(pairing, suffix),
      Uint8List(0),
      retain: true,
    );
  }

  Future<bool> subscribe(String suffixFilter) async {
    final pairing = _pairing;
    final transport = _transport;
    if (pairing == null || transport == null || !transport.isConnected) {
      return false;
    }
    return transport.subscribe(_fullTopic(pairing, suffixFilter));
  }

  void dispose() {
    _wantConnected = false;
    _generation++;
    _reconnectTimer?.cancel();
    _incomingSub?.cancel();
    _dropSub?.cancel();
    final transport = _transport;
    if (transport != null) unawaited(transport.disconnect());
    _messages.close();
    _connected.close();
    _status.dispose();
  }

  void _adoptPairing(Esp32MqttPairing? pairing) {
    _generation++;
    _pairing = pairing;
    _crypto = pairing == null
        ? null
        : Esp32RoomCrypto(pairing.roomKey, random: _random);
    _status.value = pairing == null
        ? const Esp32MqttStatus()
        : const Esp32MqttStatus(
            paired: true,
            link: Esp32MqttLinkState.disconnected,
          );
  }

  Future<bool> _runConnect(Esp32MqttPairing pairing, int generation) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final transport = _openTransport();
    _setStatus(link: Esp32MqttLinkState.connecting, clearLastError: true);

    final result = await transport.connect(
      host: pairing.host,
      port: pairing.port,
      clientId: 'celular-${pairing.room}',
      username: pairing.username,
      password: pairing.password,
      willTopic: _fullTopic(pairing, _kPresenceCelular),
      willPayload: '0',
      willRetain: true,
    );

    if (generation != _generation) {
      if (result == Esp32MqttConnectResult.ok) await transport.disconnect();
      return false;
    }

    switch (result) {
      case Esp32MqttConnectResult.ok:
        return _onConnected(pairing, transport);
      case Esp32MqttConnectResult.badCredentials:
        _logger.warning('MQTT broker rejected the credentials');
        _setStatus(
          link: Esp32MqttLinkState.disconnected,
          lastError: result,
        );
        return false;
      case Esp32MqttConnectResult.unreachable:
      case Esp32MqttConnectResult.refused:
        _logger.warning('MQTT connect failed: ${result.name}');
        _setStatus(
          link: Esp32MqttLinkState.disconnected,
          lastError: result,
        );
        _scheduleReconnect();
        return false;
    }
  }

  Future<bool> _onConnected(
    Esp32MqttPairing pairing,
    Esp32MqttTransport transport,
  ) async {
    _nextBackoff = initialBackoff;
    _setStatus(
      link: Esp32MqttLinkState.connected,
      clearLastError: true,
    );
    await transport.publish(
      _fullTopic(pairing, _kPresenceCelular),
      _bytes('1'),
      retain: true,
    );
    await transport.subscribe(_fullTopic(pairing, _kPresencePlaca));
    _connected.add(null);
    return true;
  }

  Esp32MqttTransport _openTransport() {
    _incomingSub?.cancel();
    _dropSub?.cancel();
    final transport = _transportFactory();
    _transport = transport;
    _incomingSub = transport.incoming.listen(_handleIncoming);
    _dropSub = transport.unexpectedDisconnects.listen(
      (_) => _handleUnexpectedDisconnect(),
    );
    return transport;
  }

  void _handleUnexpectedDisconnect() {
    if (!_wantConnected) return;
    _setStatus(link: Esp32MqttLinkState.disconnected, boardOnline: false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_wantConnected || _pairing == null) return;
    _reconnectTimer?.cancel();
    final delay = _nextBackoff;
    final doubled = _nextBackoff * 2;
    _nextBackoff = doubled > maxBackoff ? maxBackoff : doubled;
    _reconnectTimer = _timerFactory(delay, () {
      _reconnectTimer = null;
      unawaited(connect());
    });
  }

  void _handleIncoming(Esp32MqttIncomingRaw raw) {
    final pairing = _pairing;
    final crypto = _crypto;
    if (pairing == null || crypto == null) return;
    final prefix = 'sm/${pairing.room}/';
    if (!raw.topic.startsWith(prefix)) return;
    final suffix = raw.topic.substring(prefix.length);

    if (suffix.startsWith(_kPresencePrefix)) {
      if (suffix == _kPresencePlaca) {
        final text = utf8.decode(raw.payload, allowMalformed: true).trim();
        _setStatus(boardOnline: text == '1');
      }
      return;
    }

    if (raw.payload.isEmpty) {
      _messages.add(
        Esp32MqttMessage(
          suffix: suffix,
          plaintext: null,
          from: null,
          retained: raw.retained,
        ),
      );
      return;
    }

    final envelope = utf8.decode(raw.payload, allowMalformed: true);
    final result = crypto.open(envelope, self: kEsp32FromPhone);
    final failure = result.failure;
    if (failure == null) {
      _messages.add(
        Esp32MqttMessage(
          suffix: suffix,
          plaintext: result.plaintext,
          from: result.from,
          retained: raw.retained,
        ),
      );
      return;
    }

    switch (failure) {
      case Esp32OpenFailure.self:
        return;
      case Esp32OpenFailure.authFailed:
        final from = result.from;
        if (from != null && from != kEsp32FromPhone) {
          _logger.warning('Room key rejected for sender $from');
          _setStatus(keyRejected: true);
        } else {
          _logger.warning('MQTT envelope failed authentication');
        }
        return;
      case Esp32OpenFailure.badFormat:
      case Esp32OpenFailure.badVersion:
      case Esp32OpenFailure.missingFrom:
      case Esp32OpenFailure.unknownFrom:
        _logger.warning('MQTT envelope dropped: ${failure.name}');
        return;
    }
  }

  void _setStatus({
    bool? paired,
    Esp32MqttLinkState? link,
    bool? boardOnline,
    bool? keyRejected,
    Esp32MqttConnectResult? lastError,
    bool clearLastError = false,
  }) {
    _status.value = _status.value.copyWith(
      paired: paired,
      link: link,
      boardOnline: boardOnline,
      keyRejected: keyRejected,
      lastError: lastError,
      clearLastError: clearLastError,
    );
  }

  static String _fullTopic(Esp32MqttPairing pairing, String suffix) =>
      'sm/${pairing.room}/$suffix';

  static Uint8List _bytes(String text) =>
      Uint8List.fromList(utf8.encode(text));

  static Timer _defaultTimer(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
