import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_ble_bridge_service.dart';
import 'package:memex/ui/esp32/view_models/esp32_board_viewmodel.dart';
import 'package:memex/ui/esp32/widgets/esp32_board_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSecretStore implements Esp32SecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

class _TestBleTransport implements Esp32BleTransport {
  bool connected = true;
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  void Function(String line)? _onBleLine;

  @override
  void setCallbacks({
    void Function(String line)? onBleLine,
    void Function(bool connected)? onConnectionChanged,
    void Function(Map<String, String> notification)? onNotification,
  }) {
    _onBleLine = onBleLine;
  }

  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<bool> hasBlePermissions() async => true;

  @override
  Future<bool> hasNotificationAccess() async => true;

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<void> openNotificationAccessSettings() async {}

  @override
  Future<String?> readStatus() async => '{"ok":true,"paired":false}';

  @override
  Future<bool> requestBlePermissions() async => true;

  @override
  Future<bool> scanAndConnect({int timeoutMs = 10000}) async => true;

  @override
  Future<bool> writeJson(String payload) async {
    final map = (jsonDecode(payload) as Map).cast<String, dynamic>();
    sent.add(map);
    final reply = switch (map['type']) {
      'pair_start' => <String, dynamic>{'type': 'pair_code', 'ok': true},
      'pair_confirm' => <String, dynamic>{
          'type': 'pair_ok',
          'ok': map['code'] == '123456',
          'key':
              'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        },
      'config' => <String, dynamic>{'type': 'config', 'ok': true},
      _ => <String, dynamic>{'type': map['type'], 'ok': true},
    };
    Future<void>.microtask(() => _onBleLine?.call(jsonEncode(reply)));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Esp32BoardPage pairs, toggles filter, and submits config',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 3200);
    addTearDown(tester.view.reset);
    final transport = _TestBleTransport();
    final service = Esp32BleBridgeService(
      transport: transport,
      secretStore: _TestSecretStore(),
      replyTimeout: const Duration(milliseconds: 500),
    );
    final vm = Esp32BoardViewModel(service: service);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const <Locale>[Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Esp32BoardPage(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Placa ESP32-S3 (BLE)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('esp32-pair-start-btn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('esp32-pair-code-input')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('esp32-pair-confirm-btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('esp32-revoke-btn')), findsOneWidget);

    // Toggle SMS notification filter on.
    final smsSwitch = find.byKey(const ValueKey('esp32-notif-msg'));
    await tester.ensureVisible(smsSwitch);
    await tester.tap(smsSwitch);
    await tester.pumpAndSettle();
    expect((await service.loadAllowedApps()).contains('msg'), isTrue);

    // Select Peach character (index 2) and send config.
    await tester.ensureVisible(find.byKey(const ValueKey('esp32-char-2')));
    await tester.tap(find.byKey(const ValueKey('esp32-char-2')));
    await tester.enterText(
      find.byKey(const ValueKey('esp32-city-input')),
      'São Paulo',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('esp32-save-config-btn')),
    );
    await tester.tap(find.byKey(const ValueKey('esp32-save-config-btn')));
    await tester.pumpAndSettle();

    final cfgCmd = transport.sent.lastWhere((e) => e['type'] == 'config');
    expect(cfgCmd['char_idx'], 2);
    expect(cfgCmd['city'], 'São Paulo');
  });
}
