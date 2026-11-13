import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'todo-undo-integration-user';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalPathProvider;
  MemexRouter? router;

  setUp(() async {
    AppFlavor.init('global');
    root = await Directory.systemTemp.createTemp('memex_todo_undo_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(root.path);
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
    await FileSystemService.init(root.path);
    router = MemexRouter();
    await router!.ensureInitialized().timeout(const Duration(seconds: 30));
    await UserStorage.saveUser(_userId);
  });

  tearDown(() async {
    router?.dispose();
    await LocalTaskExecutor.instance.stop();
    await LocalAssetServer.stopServer();
    PathProviderPlatform.instance = originalPathProvider;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('undo restores the same Todo through ViewModel and storage layers',
      () async {
    final viewModel = TodoViewModel(router: router!);
    addTearDown(viewModel.dispose);
    await viewModel.add(text: 'Revisar proposta', due: '');
    final created = viewModel.allItems.single;

    expect(await viewModel.remove(created), isTrue);
    expect(viewModel.allItems, isEmpty);

    expect(await viewModel.restore(created), isTrue);
    final restored = viewModel.allItems.single;
    expect(restored.id, created.id);
    expect(restored.isTombstoned, isFalse);
    expect(restored.version, created.version + 2);
  });
}

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
