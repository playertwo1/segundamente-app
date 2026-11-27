import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:memex/utils/logger.dart';

/// Raw message from the broker, before envelope decoding.
class Esp32MqttIncomingRaw {
  const Esp32MqttIncomingRaw({
    required this.topic,
    required this.payload,
    required this.retained,
  });

  final String topic;
  final Uint8List payload;
  final bool retained;
}

enum Esp32MqttConnectResult { ok, badCredentials, unreachable, refused }

/// Broker seam. The production implementation wraps `mqtt_client`; tests use
/// an in-memory fake.
abstract class Esp32MqttTransport {
  Future<Esp32MqttConnectResult> connect({
    required String host,
    required int port,
    required String clientId,
    required String username,
    required String password,
    required String willTopic,
    required String willPayload,
    required bool willRetain,
  });

  Future<void> disconnect();

  bool get isConnected;

  /// QoS 1. An empty [payload] clears a retained message.
  Future<bool> publish(String topic, Uint8List payload, {required bool retain});

  /// QoS 1.
  Future<bool> subscribe(String topicFilter);

  Stream<Esp32MqttIncomingRaw> get incoming;

  /// Emits only for drops that were not requested through [disconnect].
  Stream<void> get unexpectedDisconnects;
}

/// Production transport: MQTT 3.1.1 over TLS with `mqtt_client`.
/// Never logs the username, password, key or payload.
class MqttClientEsp32Transport implements Esp32MqttTransport {
  MqttClientEsp32Transport();

  static final _logger = getLogger('MqttClientEsp32Transport');
  static const int _keepAliveSeconds = 30;
  static const int _connectionTimeoutMs = 15000;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  bool _disconnectRequested = false;
  bool _wasConnected = false;

  final StreamController<Esp32MqttIncomingRaw> _incoming =
      StreamController<Esp32MqttIncomingRaw>.broadcast();
  final StreamController<void> _drops = StreamController<void>.broadcast();

  @override
  Stream<Esp32MqttIncomingRaw> get incoming => _incoming.stream;

  @override
  Stream<void> get unexpectedDisconnects => _drops.stream;

  @override
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Future<Esp32MqttConnectResult> connect({
    required String host,
    required int port,
    required String clientId,
    required String username,
    required String password,
    required String willTopic,
    required String willPayload,
    required bool willRetain,
  }) async {
    _disconnectRequested = false;
    final client = MqttServerClient.withPort(host, clientId, port)
      ..secure = true
      ..setProtocolV311()
      ..keepAlivePeriod = _keepAliveSeconds
      ..autoReconnect = false
      ..logging(on: false)
      ..connectionTimeout = _connectionTimeoutMs
      ..onDisconnected = _handleDisconnected;

    var will = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic(willTopic)
        .withWillMessage(willPayload)
        .withWillQos(MqttQos.atLeastOnce)
        .authenticateAs(username, password)
        .startClean();
    if (willRetain) {
      will = will.withWillRetain();
    }
    client.connectionMessage = will;

    await _updatesSub?.cancel();
    _updatesSub = null;
    _client = client;

    try {
      await client.connect(username, password);
    } catch (e) {
      final rc = client.connectionStatus?.returnCode;
      _logger.warning('MQTT connect failed: ${e.runtimeType}');
      _disconnectRequested = true;
      client.disconnect();
      return _mapFailure(e, rc);
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final rc = client.connectionStatus?.returnCode;
      _disconnectRequested = true;
      client.disconnect();
      return _mapReturnCode(rc);
    }

    _wasConnected = true;
    _updatesSub = client.updates?.listen(_handleUpdates);
    return Esp32MqttConnectResult.ok;
  }

  Esp32MqttConnectResult _mapFailure(Object error, MqttConnectReturnCode? rc) {
    if (rc == MqttConnectReturnCode.badUsernameOrPassword ||
        rc == MqttConnectReturnCode.notAuthorized) {
      return Esp32MqttConnectResult.badCredentials;
    }
    final broke = rc != null &&
        rc != MqttConnectReturnCode.noneSpecified &&
        rc != MqttConnectReturnCode.connectionAccepted;
    if (broke) return Esp32MqttConnectResult.refused;
    if (error is SocketException ||
        error is TlsException ||
        error is TimeoutException ||
        error is NoConnectionException) {
      return Esp32MqttConnectResult.unreachable;
    }
    return Esp32MqttConnectResult.refused;
  }

  Esp32MqttConnectResult _mapReturnCode(MqttConnectReturnCode? rc) {
    if (rc == MqttConnectReturnCode.badUsernameOrPassword ||
        rc == MqttConnectReturnCode.notAuthorized) {
      return Esp32MqttConnectResult.badCredentials;
    }
    return Esp32MqttConnectResult.refused;
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage>> batch) {
    for (final record in batch) {
      final message = record.payload;
      if (message is! MqttPublishMessage) continue;
      _incoming.add(
        Esp32MqttIncomingRaw(
          topic: record.topic,
          payload: Uint8List.fromList(message.payload.message),
          retained: message.header?.retain ?? false,
        ),
      );
    }
  }

  void _handleDisconnected() {
    final wasConnected = _wasConnected;
    _wasConnected = false;
    if (_disconnectRequested || !wasConnected) return;
    _logger.info('MQTT connection dropped');
    _drops.add(null);
  }

  @override
  Future<void> disconnect() async {
    _disconnectRequested = true;
    _wasConnected = false;
    await _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
  }

  @override
  Future<bool> publish(
    String topic,
    Uint8List payload, {
    required bool retain,
  }) async {
    final client = _client;
    if (client == null || !isConnected) return false;
    try {
      final builder = MqttClientPayloadBuilder();
      for (final byte in payload) {
        builder.addByte(byte);
      }
      client.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: retain,
      );
      return true;
    } catch (e) {
      _logger.warning('MQTT publish failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> subscribe(String topicFilter) async {
    final client = _client;
    if (client == null || !isConnected) return false;
    try {
      return client.subscribe(topicFilter, MqttQos.atLeastOnce) != null;
    } catch (e) {
      _logger.warning('MQTT subscribe failed: ${e.runtimeType}');
      return false;
    }
  }
}
