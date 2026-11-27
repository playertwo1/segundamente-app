import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_notification_forwarder.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_task_sync.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/esp32/view_models/esp32_board_viewmodel.dart';
import 'package:memex/ui/esp32/widgets/esp32_board_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/esp32_mqtt/fake_esp32_mqtt_transport.dart';

class _FakeNotifSource implements Esp32NotificationSource {
  bool access = false;

  @override
  Future<bool> hasNotificationAccess() async => access;

  @override
  Future<void> openNotificationAccessSettings() async {}

  @override
  void setOnNotification(
    void Function(String app, String title, String body)? handler,
  ) {}
}

class _MemoryMetaStore implements Esp32TaskMetaStore {
  @override
  Future<Map<String, Esp32TaskMeta>> load() async => <String, Esp32TaskMeta>{};

  @override
  Future<void> save(Map<String, Esp32TaskMeta> metas) async {}
}

Future<void> _setLanguage(String code) async {
  SharedPreferences.setMockInitialValues(<String, Object>{'language': code});
  await UserStorage.initL10n();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEsp32MqttTransport transport;
  late MemoryEsp32MqttSecretStore store;
  late FakeEsp32MqttTimers timers;
  late Esp32MqttService service;
  late _FakeNotifSource source;
  late Esp32MqttNotificationForwarder forwarder;
  late Esp32MqttTaskSync taskSync;

  setUp(() async {
    await _setLanguage('pt');
    transport = FakeEsp32MqttTransport();
    store = MemoryEsp32MqttSecretStore();
    timers = FakeEsp32MqttTimers();
    service = Esp32MqttService(
      transportFactory: () => transport,
      secretStore: store,
      random: Random(7),
      timerFactory: timers.create,
    );
    source = _FakeNotifSource();
    forwarder = Esp32MqttNotificationForwarder(
      service: service,
      source: source,
      timerFactory: timers.create,
    );
    taskSync = Esp32MqttTaskSync(
      service: service,
      todoService: TodoService(),
      userIdProvider: () async => null,
      metaStore: _MemoryMetaStore(),
      timerFactory: timers.create,
    );
  });

  tearDown(() async {
    await taskSync.stop();
    await forwarder.stop();
    service.dispose();
    await transport.close();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    String locale = 'pt',
    Widget Function(BuildContext, ValueChanged<String>)? scanner,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vm = Esp32BoardViewModel(
      service: service,
      taskSync: taskSync,
      forwarder: forwarder,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Esp32BoardPage(viewModel: vm, qrScannerBuilder: scanner),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pairSilently() async {
    expect(await service.pairFromCode(kFakeQrJson), isNull);
  }

  /// The fake broker delivers with `Future.delayed`, which only runs outside
  /// the fake clock of [testWidgets], hence `runAsync`.
  Future<void> injectFromBoard(
    WidgetTester tester,
    String topic,
    Uint8List payload, {
    bool retained = false,
  }) async {
    await tester.runAsync(
      () => transport.inject(topic, payload, retained: retained),
    );
  }

  String pasteText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('esp32-paste-code-input')))
      .controller!
      .text;

  void expectNoCredentialsRendered(WidgetTester tester) {
    expect(find.textContaining(kFakeRoomKey), findsNothing);
    expect(find.textContaining('synthetic-pass'), findsNothing);
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      final rendered = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      expect(rendered, isNot(contains(kFakeRoomKey)));
      expect(rendered, isNot(contains('synthetic-pass')));
    }
  }

  void expectNoWifiCityOrCharacter() {
    for (final text in const [
      'Wi-Fi',
      'SSID',
      'Senha',
      'Cidade',
      'Personagem',
      'Mochi',
    ]) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
  }

  group('not paired', () {
    testWidgets('shows scan and paste actions, without Wi-Fi, city or character',
        (tester) async {
      await pumpPage(tester);

      expect(find.text('Não pareado'), findsOneWidget);
      expect(find.text('Ler QR da placa'), findsOneWidget);
      expect(find.text('Colar código'), findsOneWidget);
      expect(find.text('Esquecer placa'), findsNothing);
      expectNoWifiCityOrCharacter();
    });

    testWidgets('pasting an invalid code shows the pairing error',
        (tester) async {
      await pumpPage(tester);

      await tester.enterText(
        find.byKey(const ValueKey('esp32-paste-code-input')),
        'isto nao e um codigo',
      );
      await tester.tap(find.byKey(const ValueKey('esp32-paste-pair-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Este texto não é um código da placa.'), findsOneWidget);
      expect(find.text('Não pareado'), findsOneWidget);
      expect(service.status.value.paired, isFalse);
    });

    testWidgets('pasting the board code pairs, shows connected and hides the key',
        (tester) async {
      await pumpPage(tester);

      await tester.enterText(
        find.byKey(const ValueKey('esp32-paste-code-input')),
        kFakeQrJson,
      );
      await tester.tap(find.byKey(const ValueKey('esp32-paste-pair-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Conectado'), findsOneWidget);
      expect(find.text('Esquecer placa'), findsOneWidget);
      expect(find.text('Ler QR da placa'), findsNothing);
      expectNoCredentialsRendered(tester);
    });

    testWidgets('a scanned code is delivered to the page and pairs',
        (tester) async {
      await pumpPage(
        tester,
        scanner: (_, onDetect) => Center(
          child: ElevatedButton(
            key: const ValueKey('mock-qr-trigger'),
            onPressed: () => onDetect(kFakeQrJson),
            child: const Text('Mock scan'),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('esp32-scan-qr-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mock-qr-trigger')));
      await tester.pumpAndSettle();

      expect(find.text('Conectado'), findsOneWidget);
      expect(find.text('Esquecer placa'), findsOneWidget);
      expect(store.data, isNotEmpty);
      expectNoCredentialsRendered(tester);
    });
  });

  group('paired', () {
    testWidgets('forget asks first, then returns to not paired and clears the field',
        (tester) async {
      await pairSilently();
      await pumpPage(tester);
      expect(find.text('Esquecer placa'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('esp32-forget-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Esquecer a placa?'), findsOneWidget);
      await tester.tap(find.text(UserStorage.l10n.cancel));
      await tester.pumpAndSettle();
      expect(store.data, isNotEmpty);

      await tester.tap(find.byKey(const ValueKey('esp32-forget-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('esp32-forget-confirm-btn')));
      await tester.pumpAndSettle();

      expect(store.data, isEmpty);
      expect(find.text('Não pareado'), findsOneWidget);
      expect(find.text('Ler QR da placa'), findsOneWidget);
      expect(find.text('Esquecer placa'), findsNothing);
      expect(pasteText(tester), isEmpty);
    });

    testWidgets('shows the board presence and the sync button', (tester) async {
      await pairSilently();
      await pumpPage(tester);

      expect(find.text('Placa offline'), findsOneWidget);
      await injectFromBoard(
        tester,
        'sm/$kFakeRoom/presenca/placa',
        Uint8List.fromList(utf8.encode('1')),
        retained: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('Placa online'), findsOneWidget);
      expect(find.text('Sincronizar agora'), findsOneWidget);
    });

    testWidgets('a key the board rejects asks for the new QR code',
        (tester) async {
      await pairSilently();
      await pumpPage(tester);

      await injectFromBoard(
        tester,
        'sm/$kFakeRoom/tarefas/esp-1',
        Uint8List.fromList(
          utf8.encode(
            Esp32RoomCrypto('ff' * 32, random: Random(3))
                .seal(from: kEsp32FromBoard, plaintext: '{"x":1}'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('A placa trocou a chave. Leia o QR novo.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('esp32-key-rescan-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('esp32-scan-qr-btn')), findsOneWidget);
    });

    testWidgets('bad credentials show a warning and a connect button',
        (tester) async {
      transport.nextConnectResult = Esp32MqttConnectResult.badCredentials;
      await pairSilently();
      await pumpPage(tester);

      expect(
        find.text('O servidor MQTT recusou o usuário ou a senha.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('esp32-connect-btn')), findsOneWidget);
    });

    testWidgets('switching an app saves it', (tester) async {
      await pairSilently();
      await pumpPage(tester);

      final switchFinder = find.byKey(const ValueKey('esp32-notif-msg'));
      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      final saved = await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getStringList(kEsp32NotifAllowedAppsPrefsKey);
      });
      expect(saved, contains('msg'));
    });

    testWidgets('access granted in Android settings is seen on resume',
        (tester) async {
      await pairSilently();
      await pumpPage(tester);
      expect(find.text('Habilitar acesso a notificações'), findsOneWidget);

      source.access = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Habilitar acesso a notificações'), findsNothing);
    });
  });

  group('language', () {
    testWidgets('shows Portuguese texts', (tester) async {
      await _setLanguage('pt');
      await pumpPage(tester);

      expect(find.text('Placa ESP32-S3'), findsOneWidget);
      expect(find.text('Ler QR da placa'), findsOneWidget);
      expect(find.text('Colar código'), findsOneWidget);
      expect(find.text('Notificações encaminhadas'), findsOneWidget);
    });

    testWidgets('shows English texts', (tester) async {
      await _setLanguage('en');
      await pumpPage(tester, locale: 'en');

      expect(find.text('ESP32-S3 board'), findsOneWidget);
      expect(find.text('Scan board QR code'), findsOneWidget);
      expect(find.text('Paste code'), findsOneWidget);
      expect(find.text('Forwarded notifications'), findsOneWidget);
    });
  });
}
