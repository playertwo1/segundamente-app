import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_ble_bridge_service.dart';
import 'package:memex/ui/esp32/view_models/esp32_board_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements Esp32SecretStore {
  final Map<String, String> _v = <String, String>{};
  @override
  Future<void> delete(String key) async => _v.remove(key);
  @override
  Future<String?> read(String key) async => _v[key];
  @override
  Future<void> write(String key, String value) async => _v[key] = value;
}

class _Transport implements Esp32BleTransport {
  _Transport({this.perms = true, this.connectError});
  bool perms;
  bool grantOnRequest = false;
  PlatformException? connectError;

  @override
  void setCallbacks({
    void Function(String line)? onBleLine,
    void Function(bool connected)? onConnectionChanged,
    void Function(Map<String, String> notification)? onNotification,
  }) {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> hasBlePermissions() async => perms;
  @override
  Future<bool> hasNotificationAccess() async => true;
  @override
  Future<bool> isConnected() async => false;
  @override
  Future<void> openNotificationAccessSettings() async {}
  @override
  Future<String?> readStatus() async => null;
  @override
  Future<bool> requestBlePermissions() async {
    if (grantOnRequest) perms = true;
    return perms;
  }

  @override
  Future<bool> scanAndConnect({int timeoutMs = 10000}) async {
    if (connectError != null) throw connectError!;
    return true;
  }

  @override
  Future<bool> writeJson(String payload) async => true;
}

Esp32BoardViewModel _vm(_Transport t) {
  final vm = Esp32BoardViewModel(
    service: Esp32BleBridgeService(transport: t, secretStore: _Store()),
  );
  vm.permissionPollInterval = const Duration(milliseconds: 1);
  return vm;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('connect surfaces native errors instead of failing silently', () async {
    final vm = _vm(_Transport(
      connectError: PlatformException(code: 'ble_connect', message: 'scan_timeout'),
    ));
    await vm.refreshState();
    await vm.connect();
    expect(vm.connected, isFalse);
    expect(vm.statusMessage, 'connect_failed: scan_timeout');
    expect(vm.busy, isFalse);
  });

  test('connect waits for the permission dialog then connects', () async {
    final t = _Transport(perms: false)..grantOnRequest = true;
    final vm = _vm(t);
    await vm.refreshState();
    await vm.connect();
    expect(vm.connected, isTrue);
    expect(vm.statusMessage, 'connected');
  });

  test('connect reports denied permission', () async {
    final vm = _vm(_Transport(perms: false));
    await vm.refreshState();
    await vm.connect();
    expect(vm.statusMessage, 'ble_permission_required');
  });
}
