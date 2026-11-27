import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:memex/data/services/esp32_ble_bridge_service.dart';

/// Character options available on the ESP32-S3 AMOLED firmware (`0..3`).
const List<String> kEsp32CharacterNames = <String>[
  'Mochi',
  'Sprout',
  'Peach',
  'Nimbus',
];

/// State controller for [Esp32BoardPage] (F16).
class Esp32BoardViewModel extends ChangeNotifier {
  Esp32BoardViewModel({Esp32BleBridgeService? service})
      : _service = service ?? Esp32BleBridgeService();

  final Esp32BleBridgeService _service;
  StreamSubscription<bool>? _connSub;

  /// Poll interval while waiting for the Bluetooth permission dialog.
  @visibleForTesting
  Duration permissionPollInterval = const Duration(milliseconds: 500);

  bool _connected = false;
  bool _paired = false;
  bool _hasBlePermissions = true;
  bool _hasNotificationAccess = false;
  bool _busy = false;
  String? _statusMessage;
  bool _pairCodeRequested = false;
  int _selectedCharIdx = 0;
  int _pendingTasksCount = 0;
  int _lastSyncedRemoteCount = 0;
  Set<String> _allowedApps = Set<String>.from(kEsp32DefaultAllowedApps);

  bool get connected => _connected;
  bool get paired => _paired;
  bool get hasBlePermissions => _hasBlePermissions;
  bool get hasNotificationAccess => _hasNotificationAccess;
  bool get busy => _busy;
  String? get statusMessage => _statusMessage;
  bool get pairCodeRequested => _pairCodeRequested;
  int get selectedCharIdx => _selectedCharIdx;
  int get pendingTasksCount => _pendingTasksCount;
  int get lastSyncedRemoteCount => _lastSyncedRemoteCount;
  Set<String> get allowedApps => Set<String>.unmodifiable(_allowedApps);

  Future<void> initialize() async {
    _connSub?.cancel();
    _connSub = _service.connectionStream.listen((value) {
      _connected = value;
      notifyListeners();
    });
    await refreshState();
  }

  Future<void> refreshState() async {
    try {
      _connected = await _service.isConnected();
      _paired = await _service.isPaired();
      _hasBlePermissions = await _service.hasBlePermissions();
      _hasNotificationAccess = await _service.hasNotificationAccess();
      _allowedApps = await _service.loadAllowedApps();
      _pendingTasksCount = (await _service.loadPendingTasks()).length;
    } catch (e) {
      _statusMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> requestPermissions() async {
    _hasBlePermissions = await _service.requestBlePermissions();
    notifyListeners();
  }

  Future<void> openNotificationAccessSettings() =>
      _service.openNotificationAccessSettings();

  Future<void> connect() async {
    await _runBusy(() async {
      _statusMessage = null;
      if (!_hasBlePermissions || !await _service.hasBlePermissions()) {
        _hasBlePermissions = await _service.requestBlePermissions();
        // The native request is asynchronous (system dialog): wait for the answer.
        for (var i = 0; i < 40 && !_hasBlePermissions; i++) {
          await Future<void>.delayed(permissionPollInterval);
          _hasBlePermissions = await _service.hasBlePermissions();
        }
        notifyListeners();
        if (!_hasBlePermissions) {
          _statusMessage = 'ble_permission_required';
          return;
        }
      }
      try {
        _statusMessage = 'connecting';
        notifyListeners();
        final ok = await _service.connect();
        _connected = ok;
        _statusMessage = ok ? 'connected' : 'connect_failed';
        _pendingTasksCount = (await _service.loadPendingTasks()).length;
      } catch (e) {
        // Native errors (scan_timeout, bluetooth_disabled, gatt_status_*...)
        // arrive as PlatformException; surface them instead of failing silently.
        _connected = false;
        _statusMessage = 'connect_failed: ${_describeError(e)}';
      }
    });
  }

  String _describeError(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    return e.toString();
  }

  Future<void> disconnect() async {
    await _runBusy(() async {
      await _service.disconnect();
      _connected = false;
      _statusMessage = 'disconnected';
    });
  }

  Future<void> startPairing() async {
    await _runBusy(() async {
      final ok = await _service.startPairing();
      _pairCodeRequested = ok;
      _statusMessage = ok ? 'pair_code_requested' : 'pair_start_failed';
    });
  }

  Future<bool> confirmPairing(String code) async {
    var success = false;
    await _runBusy(() async {
      success = await _service.confirmPairing(code);
      if (success) {
        _paired = true;
        _pairCodeRequested = false;
        _statusMessage = 'paired';
      } else {
        _statusMessage = 'pair_invalid_code';
      }
    });
    return success;
  }

  Future<void> revokePairing() async {
    await _runBusy(() async {
      await _service.revokePairing();
      _paired = false;
      _pairCodeRequested = false;
      _statusMessage = 'revoked';
    });
  }

  Future<void> syncTasks() async {
    await _runBusy(() async {
      try {
        _lastSyncedRemoteCount = await _service.syncWithTodoService();
        _pendingTasksCount = (await _service.loadPendingTasks()).length;
        _statusMessage = 'sync_ok';
      } catch (e) {
        _statusMessage = 'sync_failed: $e';
      }
    });
  }

  Future<void> toggleAllowedApp(String app, bool enabled) async {
    final next = Set<String>.from(_allowedApps);
    if (enabled) {
      next.add(app);
    } else {
      next.remove(app);
    }
    _allowedApps = next;
    notifyListeners();
    await _service.saveAllowedApps(next);
  }

  void selectCharacter(int index) {
    if (index < 0 || index > 3) return;
    _selectedCharIdx = index;
    notifyListeners();
  }

  Future<bool> sendConfig({String? ssid, String? pass, String? city}) async {
    var ok = false;
    await _runBusy(() async {
      ok = await _service.configureBoard(
        ssid: ssid,
        pass: pass,
        city: city,
        charIdx: _selectedCharIdx,
      );
      _statusMessage = ok ? 'config_ok' : 'config_failed';
    });
    return ok;
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
    _connSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
