import 'package:flutter/foundation.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_notification_forwarder.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_pairing.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_task_sync.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';
import 'package:memex/utils/logger.dart';

/// State controller for [Esp32BoardPage] (F17-05). Holds no secrets: the
/// pairing lives in [Esp32MqttService] and this only reads its status.
class Esp32BoardViewModel extends ChangeNotifier {
  Esp32BoardViewModel({
    required Esp32MqttService service,
    required Esp32MqttTaskSync taskSync,
    required Esp32MqttNotificationForwarder forwarder,
  })  : _service = service,
        _taskSync = taskSync,
        _forwarder = forwarder {
    _status = _service.status.value;
    _service.status.addListener(_onStatusChanged);
  }

  static final _logger = getLogger('Esp32BoardViewModel');

  final Esp32MqttService _service;
  final Esp32MqttTaskSync _taskSync;
  final Esp32MqttNotificationForwarder _forwarder;

  late Esp32MqttStatus _status;
  bool _busy = false;
  Esp32PairingError? _pairingError;
  bool _hasNotificationAccess = false;
  Set<String> _allowedApps = Set<String>.from(kEsp32NotifDefaultApps);

  bool get paired => _status.paired;
  Esp32MqttLinkState get link => _status.link;
  bool get boardOnline => _status.boardOnline;
  bool get keyRejected => _status.keyRejected;
  Esp32MqttConnectResult? get lastError => _status.lastError;
  bool get busy => _busy;
  Esp32PairingError? get pairingError => _pairingError;
  bool get hasNotificationAccess => _hasNotificationAccess;
  Set<String> get allowedApps => Set<String>.unmodifiable(_allowedApps);

  /// Reads the notification access and the apps the user allowed.
  Future<void> initialize() async {
    _allowedApps = await _forwarder.loadAllowedApps();
    await refreshNotificationAccess();
  }

  /// Called when the app comes back from the Android settings screen.
  Future<void> refreshNotificationAccess() async {
    try {
      _hasNotificationAccess = await _forwarder.hasNotificationAccess();
    } catch (error, stackTrace) {
      _logger.warning('Notification access unavailable', error, stackTrace);
      _hasNotificationAccess = false;
    }
    notifyListeners();
  }

  Future<void> openNotificationAccessSettings() =>
      _forwarder.openNotificationAccessSettings();

  /// Returns true when the code paired. On error, [pairingError] says why and
  /// nothing is stored.
  Future<bool> pairFromCode(String raw) async {
    var paired = false;
    await _runBusy(() async {
      final error = await _service.pairFromCode(raw);
      _pairingError = error;
      paired = error == null;
    });
    return paired;
  }

  Future<void> syncNow() => _runBusy(_taskSync.syncNow);

  Future<void> connect() => _runBusy(() async {
        await _service.connect();
      });

  /// Disconnects, deletes the stored key and clears the task sync metadata.
  Future<void> forget() => _runBusy(() async {
        await _service.forget();
        await _taskSync.clearMeta();
        _pairingError = null;
      });

  Future<void> toggleAllowedApp(String app, bool enabled) async {
    final next = Set<String>.from(_allowedApps);
    if (enabled) {
      next.add(app);
    } else {
      next.remove(app);
    }
    _allowedApps = next;
    notifyListeners();
    await _forwarder.saveAllowedApps(next);
  }

  void _onStatusChanged() {
    _status = _service.status.value;
    notifyListeners();
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _service.status.removeListener(_onStatusChanged);
    super.dispose();
  }
}
