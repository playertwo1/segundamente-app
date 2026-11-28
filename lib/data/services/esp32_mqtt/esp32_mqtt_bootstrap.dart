import 'dart:async';

import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_agent_alerts.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_notification_forwarder.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_task_sync.dart';
import 'package:memex/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys left behind by the F16 BLE bridge. Removed once, on the first start.
/// The allowed-apps preference is kept on purpose (see F17-04).
const String kEsp32BleLegacyKeySecret = 'esp32_ble_key_v1';
const String kEsp32BleLegacyPendingPrefsKey = 'esp32_pending_sync_tasks';
const String kEsp32BleLegacyCleanedPrefsKey = 'esp32_ble_legacy_cleaned_v1';

/// Wires the MQTT services to the app lifecycle (F17-06).
///
/// The link is kept only while the app is in the foreground, plus a short
/// grace period after it goes to the background, because Android cuts the
/// network of background apps anyway.
class Esp32MqttBootstrap {
  Esp32MqttBootstrap({
    required Esp32MqttService service,
    required Esp32MqttTaskSync taskSync,
    required Esp32MqttNotificationForwarder forwarder,
    required Esp32MqttSecretStore secretStore,
    Esp32MqttAgentAlerts? agentAlerts,
    Future<SharedPreferences> Function()? prefsProvider,
    Timer Function(Duration, void Function())? timerFactory,
    this.backgroundIdle = const Duration(seconds: 60),
  })  : _service = service,
        _taskSync = taskSync,
        _forwarder = forwarder,
        _secretStore = secretStore,
        _agentAlerts = agentAlerts,
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _timerFactory = timerFactory ?? _defaultTimer;

  static final Esp32MqttBootstrap instance = Esp32MqttBootstrap(
    service: Esp32MqttService.instance,
    taskSync: Esp32MqttTaskSync.instance,
    forwarder: Esp32MqttNotificationForwarder.instance,
    secretStore: const SecureEsp32MqttSecretStore(),
    agentAlerts: Esp32MqttAgentAlerts.instance,
  );

  static final _logger = getLogger('Esp32MqttBootstrap');

  final Esp32MqttService _service;
  final Esp32MqttTaskSync _taskSync;
  final Esp32MqttNotificationForwarder _forwarder;
  final Esp32MqttSecretStore _secretStore;
  final Esp32MqttAgentAlerts? _agentAlerts;
  final Future<SharedPreferences> Function() _prefsProvider;
  final Timer Function(Duration, void Function()) _timerFactory;

  /// Time in the background before the link is closed.
  final Duration backgroundIdle;

  Future<void>? _starting;
  Timer? _idleTimer;

  /// Idempotent. Clears the F16 leftovers once, loads the pairing, starts the
  /// task sync and the notification forwarder, and connects when paired. Does
  /// not wait for the connection, so opening the app is not delayed.
  Future<void> start() => _starting ??= _run();

  Future<void> _run() async {
    await _cleanLegacyOnce();
    await _service.init();
    await _taskSync.start();
    await _forwarder.start();
    await _agentAlerts?.start();
    if (_service.status.value.paired) {
      unawaited(
        _service.connect().then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _logger.warning('MQTT connect at start failed', error, stackTrace);
          },
        ),
      );
    }
  }

  /// Called when the app comes to the foreground. Cancels a pending
  /// disconnect, reconnects when paired and publishes the pending tasks.
  void onResumed() {
    _forwarder.appInForeground = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_service.status.value.paired) return;
    unawaited(_reconnectAndSync());
  }

  /// Called when the app goes to the background. The link closes after
  /// [backgroundIdle], unless the app comes back first.
  void onPaused() {
    _forwarder.appInForeground = false;
    _idleTimer?.cancel();
    _idleTimer = _timerFactory(backgroundIdle, () {
      _idleTimer = null;
      unawaited(_service.disconnect());
    });
  }

  Future<void> _reconnectAndSync() async {
    try {
      await _service.connect();
      await _taskSync.syncNow();
    } catch (error, stackTrace) {
      _logger.warning('MQTT resume sync failed', error, stackTrace);
    }
  }

  /// Removes the BLE secret and the BLE pending-tasks preference, once. If it
  /// fails, nothing is marked as done and the next start tries again.
  Future<void> _cleanLegacyOnce() async {
    try {
      final prefs = await _prefsProvider();
      if (prefs.getBool(kEsp32BleLegacyCleanedPrefsKey) ?? false) return;
      await _secretStore.delete(kEsp32BleLegacyKeySecret);
      await prefs.remove(kEsp32BleLegacyPendingPrefsKey);
      await prefs.setBool(kEsp32BleLegacyCleanedPrefsKey, true);
    } catch (error, stackTrace) {
      _logger.warning('BLE legacy cleanup failed', error, stackTrace);
    }
  }

  static Timer _defaultTimer(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
