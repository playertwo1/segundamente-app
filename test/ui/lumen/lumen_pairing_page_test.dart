import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/lumen_pairing_service.dart';
import 'package:memex/data/services/settings_registry.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/lumen/view_models/lumen_pairing_viewmodel.dart';
import 'package:memex/ui/lumen/widgets/lumen_pairing_page.dart';
import 'package:memex/ui/settings/widgets/settings_page.dart';
import 'package:memex/utils/user_storage.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProvider(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getTemporaryPath() async => rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;

  @override
  Future<String?> getExternalStoragePath() async => rootPath;
}

class _InMemoryLumenSecretStore implements LumenSecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FailingLumenSecretStore implements LumenSecretStore {
  @override
  Future<String?> read(String key) async {
    throw const LumenSecretStoreException('secret_raw_leak_do_not_expose');
  }

  @override
  Future<void> write(String key, String value) async {
    throw const LumenSecretStoreException('secret_raw_leak_do_not_expose');
  }

  @override
  Future<void> delete(String key) async {
    throw const LumenSecretStoreException('secret_raw_leak_do_not_expose');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomA = 'oKGio6SlpqeoqaqrrK2urw';
  final keyA = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i));
  final accessA = encodeBase64UrlNoPad(List<int>.generate(32, (i) => i + 32));
  final fingerprint = List<String>.filled(64, 'a').join();
  const token = 'tok_0123456789abcdef';
  const fixedDeviceId = '550e8400-e29b-41d4-a716-446655440000';
  const desktopName = 'Lumen Desktop';

  String buildPairUri({String name = desktopName}) {
    final encodedName = Uri.encodeQueryComponent(name);
    return 'coucou://pair?v=1&host=192.0.2.10&port=38443&fp=$fingerprint'
        '&token=$token&name=$encodedName'
        '&relay=wss%3A%2F%2Frelay.example.workers.dev'
        '&room=$roomA&key=$keyA&access=$accessA';
  }

  void expectNoSecretsRendered(WidgetTester tester) {
    expect(find.textContaining(keyA), findsNothing);
    expect(find.textContaining(accessA), findsNothing);
    expect(find.textContaining(token), findsNothing);
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      final rendered = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      expect(rendered, isNot(contains(keyA)));
      expect(rendered, isNot(contains(accessA)));
      expect(rendered, isNot(contains(token)));
    }
  }

  late _InMemoryLumenSecretStore store;
  late MemexRouter router;
  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues(<String, Object>{'language': 'pt'});
    await UserStorage.initL10n();
    tempRoot = await Directory.systemTemp.createTemp('lumen_pairing_page_test_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(tempRoot.path);
    await FileSystemService.init(tempRoot.path);
    router = MemexRouter();
    await router.ensureInitialized();
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPathProvider;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues(<String, Object>{'language': 'pt'});
    await UserStorage.initL10n();
    store = _InMemoryLumenSecretStore();
    router.setLumenPairingServiceForTesting(
      LumenPairingService(
        secretStore: store,
        httpClient: MockClient((_) async => http.Response('{"revoked":true}', 200)),
        deviceIdGenerator: () => fixedDeviceId,
      ),
    );
  });

  tearDown(() {
    router.setLumenPairingServiceForTesting(
      LumenPairingService(
        secretStore: _InMemoryLumenSecretStore(),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        deviceIdGenerator: () => fixedDeviceId,
      ),
    );
  });

  Future<LumenPairingViewModel> pumpPairingPage(
    WidgetTester tester, {
    Widget Function(BuildContext context, ValueChanged<String> onDetect)?
        qrScannerBuilder,
  }) async {
    final viewModel = LumenPairingViewModel(router: router);
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LumenPairingPage(
          viewModel: viewModel,
          qrScannerBuilder: qrScannerBuilder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return viewModel;
  }

  testWidgets('renders unpaired state with 8-char device ID prefix',
      (tester) async {
    await pumpPairingPage(tester);

    expect(find.text(UserStorage.l10n.lumenPairingStatusUnpaired), findsOneWidget);
    expect(
      find.text(UserStorage.l10n.lumenPairingStatusHintUnpaired),
      findsOneWidget,
    );
    expect(find.text('550e8400'), findsOneWidget);
    expect(find.text(fixedDeviceId), findsNothing);
    expect(find.byKey(const ValueKey('lumen-scan-qr-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('lumen-paste-link-button')),
      findsOneWidget,
    );
  });

  testWidgets(
      'keeps the first ViewModel when the route rebuilds with a fresh, never-loaded one',
      (tester) async {
    await pumpPairingPage(tester);
    expect(find.text(UserStorage.l10n.lumenPairingStatusUnpaired), findsOneWidget);

    final rebuilt = LumenPairingViewModel(router: router);
    addTearDown(rebuilt.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LumenPairingPage(viewModel: rebuilt),
      ),
    );
    await tester.pump();

    expect(find.text(UserStorage.l10n.lumenPairingLoading), findsNothing);
    expect(find.text(UserStorage.l10n.lumenPairingStatusUnpaired), findsOneWidget);
  });

  testWidgets(
      'pasting valid pairing link switches to paired state without exposing secrets',
      (tester) async {
    await pumpPairingPage(tester);

    await tester.tap(find.byKey(const ValueKey('lumen-paste-link-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('lumen-paste-input')),
      buildPairUri(),
    );
    await tester.tap(find.byKey(const ValueKey('lumen-paste-confirm-button')));
    await tester.pumpAndSettle();

    expect(
      find.text(UserStorage.l10n.lumenPairingStatusPaired(desktopName)),
      findsOneWidget,
    );
    expect(find.text('relay.example.workers.dev'), findsOneWidget);
    expect(find.text('192.0.2.10:38443'), findsOneWidget);
    expect(find.text('550e8400'), findsOneWidget);
    expect(find.text(UserStorage.l10n.lumenPairingPairedSuccess), findsOneWidget);
    expect(find.byKey(const ValueKey('lumen-repair-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('lumen-unlink-button')), findsOneWidget);
    expectNoSecretsRendered(tester);
  });

  testWidgets('pasting invalid link shows validation error and stays unpaired',
      (tester) async {
    await pumpPairingPage(tester);

    await tester.tap(find.byKey(const ValueKey('lumen-paste-link-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('lumen-paste-input')),
      'https://invalid.example.com/not-lumen',
    );
    await tester.tap(find.byKey(const ValueKey('lumen-paste-confirm-button')));
    await tester.pumpAndSettle();

    expect(
      find.text(UserStorage.l10n.lumenPairingInvalidQrError),
      findsOneWidget,
    );
    expect(find.text(UserStorage.l10n.lumenPairingStatusUnpaired), findsOneWidget);
  });

  testWidgets('scanning QR via builder pairs, closes scanner, and ignores duplicates',
      (tester) async {
    var scanCount = 0;
    await pumpPairingPage(
      tester,
      qrScannerBuilder: (_, onDetect) {
        return Center(
          child: ElevatedButton(
            key: const ValueKey('mock-qr-trigger'),
            onPressed: () {
              scanCount++;
              onDetect('   ');
              onDetect(buildPairUri());
              onDetect(buildPairUri(name: 'Ignored Second Desktop'));
            },
            child: const Text('Mock Scan'),
          ),
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('lumen-scan-qr-button')));
    await tester.pumpAndSettle();

    expect(
      find.text(UserStorage.l10n.lumenPairingScannerTitle),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mock-qr-trigger')));
    await tester.pumpAndSettle();

    expect(scanCount, 1);
    expect(find.text(UserStorage.l10n.lumenPairingScannerTitle), findsNothing);
    expect(
      find.text(UserStorage.l10n.lumenPairingStatusPaired(desktopName)),
      findsOneWidget,
    );
    expect(find.text(UserStorage.l10n.lumenPairingPairedSuccess), findsOneWidget);
    expectNoSecretsRendered(tester);
  });

  testWidgets(
      'unlink with confirmation when relay returns 200 clears pairing and preserves device_id',
      (tester) async {
    await pumpPairingPage(tester);

    await tester.tap(find.byKey(const ValueKey('lumen-paste-link-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lumen-paste-input')),
      buildPairUri(),
    );
    await tester.tap(find.byKey(const ValueKey('lumen-paste-confirm-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lumen-unlink-button')));
    await tester.pumpAndSettle();

    expect(
      find.text(UserStorage.l10n.lumenPairingUnlinkConfirmTitle),
      findsOneWidget,
    );
    expect(
      find.text(UserStorage.l10n.lumenPairingUnlinkConfirmBody),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('lumen-unlink-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.text(UserStorage.l10n.lumenPairingStatusUnpaired), findsOneWidget);
    expect(
      find.text(UserStorage.l10n.lumenPairingUnlinkedSuccess),
      findsOneWidget,
    );
    expect(
      store.values.containsKey(LumenPairingService.pairingStorageKey),
      isFalse,
    );
    expect(
      store.values[LumenPairingService.deviceIdStorageKey],
      fixedDeviceId,
    );
  });

  testWidgets(
      'unlink with confirmation when relay fails still clears locally and shows local-only warning',
      (tester) async {
    router.setLumenPairingServiceForTesting(
      LumenPairingService(
        secretStore: store,
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
        deviceIdGenerator: () => fixedDeviceId,
      ),
    );
    await pumpPairingPage(tester);

    await tester.tap(find.byKey(const ValueKey('lumen-paste-link-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lumen-paste-input')),
      buildPairUri(),
    );
    await tester.tap(find.byKey(const ValueKey('lumen-paste-confirm-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lumen-unlink-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lumen-unlink-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.text(UserStorage.l10n.lumenPairingStatusUnpaired), findsOneWidget);
    expect(
      find.text(UserStorage.l10n.lumenPairingUnlinkedLocalOnlyWarning),
      findsOneWidget,
    );
    expect(
      store.values.containsKey(LumenPairingService.pairingStorageKey),
      isFalse,
    );
    expect(
      store.values[LumenPairingService.deviceIdStorageKey],
      fixedDeviceId,
    );
  });

  testWidgets(
      'keystore read failure shows localized error without exposing raw exception',
      (tester) async {
    router.setLumenPairingServiceForTesting(
      LumenPairingService(secretStore: _FailingLumenSecretStore()),
    );
    await pumpPairingPage(tester);

    expect(find.text(UserStorage.l10n.loadFailed), findsOneWidget);
    expect(find.textContaining('secret_raw_leak'), findsNothing);
  });

  testWidgets('repair action opens scan and paste options sheet',
      (tester) async {
    await pumpPairingPage(tester);

    await tester.tap(find.byKey(const ValueKey('lumen-paste-link-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lumen-paste-input')),
      buildPairUri(),
    );
    await tester.tap(find.byKey(const ValueKey('lumen-paste-confirm-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lumen-repair-button')));
    await tester.pumpAndSettle();

    expect(find.text(UserStorage.l10n.lumenPairingScanQr), findsOneWidget);
    expect(find.text(UserStorage.l10n.lumenPairingPasteLink), findsOneWidget);
  });

  testWidgets('SettingsRegistry registers settings.lumen_pairing',
      (tester) async {
    final item = SettingsRegistry.allItems.firstWhere(
      (entry) => entry.id == 'settings.lumen_pairing',
    );
    late Widget targetPage;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            targetPage = item.navigationTarget.pageBuilder(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(item.title, UserStorage.l10n.lumenPairingTitle);
    expect(item.keywords, contains('lumen'));
    expect(targetPage, isA<LumenPairingPage>());
  });

  testWidgets('SettingsPage entry navigates to LumenPairingPage',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('lumen-pairing-settings'));
    await tester.scrollUntilVisible(entry, 250);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(LumenPairingPage), findsOneWidget);
    expect(find.text(UserStorage.l10n.lumenPairingStatusUnpaired), findsOneWidget);
  });
}
