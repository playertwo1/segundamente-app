import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';

/// Room key used by the synthetic fixtures (64 hex characters, not a real key).
const String kFakeRoomKey =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

const String kFakeRoom = 'abc123def456';

/// Valid pairing QR text using only synthetic values.
const String kFakeQrJson =
    '{"t":"sm-mqtt","v":1,"uri":"mqtts://broker.example.test:8883",'
    '"u":"celular-user","p":"synthetic-pass","sala":"$kFakeRoom",'
    '"k":"$kFakeRoomKey"}';

class FakeConnectCall {
  const FakeConnectCall({
    required this.host,
    required this.port,
    required this.clientId,
    required this.username,
    required this.password,
    required this.willTopic,
    required this.willPayload,
    required this.willRetain,
  });

  final String host;
  final int port;
  final String clientId;
  final String username;
  final String password;
  final String willTopic;
  final String willPayload;
  final bool willRetain;
}

class FakePublishCall {
  const FakePublishCall({
    required this.topic,
    required this.payload,
    required this.retain,
  });

  final String topic;
  final Uint8List payload;
  final bool retain;

  String get text => utf8.decode(payload);
}

/// In-memory broker seam. Records calls, injects incoming messages and
/// simulates connect results and drops.
class FakeEsp32MqttTransport implements Esp32MqttTransport {
  Esp32MqttConnectResult nextConnectResult = Esp32MqttConnectResult.ok;
  bool publishSucceeds = true;

  final List<FakeConnectCall> connects = <FakeConnectCall>[];
  final List<FakePublishCall> publishes = <FakePublishCall>[];
  final List<String> subscribes = <String>[];
  int disconnectCount = 0;

  bool _connected = false;
  final StreamController<Esp32MqttIncomingRaw> _incoming =
      StreamController<Esp32MqttIncomingRaw>.broadcast();
  final StreamController<void> _drops = StreamController<void>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  Stream<Esp32MqttIncomingRaw> get incoming => _incoming.stream;

  @override
  Stream<void> get unexpectedDisconnects => _drops.stream;

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
    connects.add(
      FakeConnectCall(
        host: host,
        port: port,
        clientId: clientId,
        username: username,
        password: password,
        willTopic: willTopic,
        willPayload: willPayload,
        willRetain: willRetain,
      ),
    );
    _connected = nextConnectResult == Esp32MqttConnectResult.ok;
    return nextConnectResult;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _connected = false;
  }

  @override
  Future<bool> publish(
    String topic,
    Uint8List payload, {
    required bool retain,
  }) async {
    if (!_connected || !publishSucceeds) return false;
    publishes.add(
      FakePublishCall(topic: topic, payload: payload, retain: retain),
    );
    return true;
  }

  @override
  Future<bool> subscribe(String topicFilter) async {
    if (!_connected) return false;
    subscribes.add(topicFilter);
    return true;
  }

  /// Delivers a message from the broker as if it arrived now.
  Future<void> inject(
    String topic,
    Uint8List payload, {
    bool retained = false,
  }) async {
    _incoming.add(
      Esp32MqttIncomingRaw(topic: topic, payload: payload, retained: retained),
    );
    await flushEvents();
  }

  /// Simulates a broker drop that was not requested by the app.
  Future<void> simulateDrop() async {
    if (!_connected) return;
    _connected = false;
    _drops.add(null);
    await flushEvents();
  }

  Future<void> close() async {
    await _incoming.close();
    await _drops.close();
  }
}

/// Timer seam: records scheduled callbacks and runs them only when a test
/// fires them.
class FakeEsp32MqttTimers {
  final List<FakeEsp32MqttTimer> timers = <FakeEsp32MqttTimer>[];

  FakeEsp32MqttTimer create(Duration delay, void Function() callback) {
    final timer = FakeEsp32MqttTimer(delay, callback);
    timers.add(timer);
    return timer;
  }

  List<FakeEsp32MqttTimer> get active =>
      timers.where((t) => t.isActive).toList();
}

class FakeEsp32MqttTimer implements Timer {
  FakeEsp32MqttTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _cancelled = false;
  bool _fired = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled && !_fired;

  @override
  int get tick => _fired ? 1 : 0;

  /// Runs the callback as if the delay elapsed.
  void fire() {
    if (!isActive) return;
    _fired = true;
    _callback();
  }
}

class MemoryEsp32MqttSecretStore implements Esp32MqttSecretStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

/// Lets queued stream events and microtasks run.
Future<void> flushEvents() => Future<void>.delayed(Duration.zero);
