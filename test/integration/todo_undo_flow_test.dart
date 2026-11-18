import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/propose_todo/todo_proposal_skill.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/use_cases/card_task_extractor.dart';
import 'package:memex/ui/timeline/view_models/card_tasks_viewmodel.dart';
import 'package:memex/ui/todo/view_models/todo_proposal_viewmodel.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/utils/result.dart';
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

  test('a confirmed timeline task appears in the Todo list with its subtasks',
      () async {
    final detail = CardDetailModel(
      id: 'task-record',
      title: 'Preparar a apresentação',
      timestamp: DateTime(2026, 11, 18),
      address: '',
      tags: const [],
      rawContent: 'Preparar a apresentação',
      insight:
          InsightData(text: '', relatedCards: const [], comments: const []),
      assets: const [],
      uiConfigs: const [
        UiConfig(templateId: 'task', data: {
          'title': 'Preparar a apresentação',
          'subtasks': [
            {'title': 'Reunir os exemplos', 'completed': true},
            {'title': 'Revisar os slides'},
          ],
        }),
      ],
    );
    final cardTasks = CardTasksViewModel(
      router: router!,
      cardId: detail.id,
      candidates: extractCardTaskCandidates(detail),
    );
    final todo = TodoViewModel(router: router!);
    addTearDown(cardTasks.dispose);
    addTearDown(todo.dispose);

    await cardTasks.load();
    await todo.load();
    expect(todo.allItems, isEmpty);

    expect(await cardTasks.addSelected(), isTrue);
    await todo.load();
    final task = todo.allItems.single;
    expect(task.text, detail.title);
    expect(task.dueDate, isNull);
    expect(todo.allSections.single.items.single.id, task.id);
    expect(task.subtasks.map((item) => (item.text, item.done)), [
      ('Reunir os exemplos', true),
      ('Revisar os slides', false),
    ]);

    await cardTasks.load();
    expect(cardTasks.phase, CardTasksPhase.added);
    expect(await cardTasks.addSelected(), isFalse);
    expect((await router!.loadTodos()).valueOrThrow, hasLength(1));
  });

  test('AI proposal writes a task only after confirmation reaches storage',
      () async {
    final tool = TodoProposalSkill().tools!.single;
    final proposalResult = await Function.apply(tool.executable!, [
      'Preparar apresentação',
      'ambiguous',
      'unspecified',
      null,
      'sexta',
      null,
      null,
    ]) as AgentToolResult;
    final collector = ChatTurnArtifactCollector(sourceRunId: 'turn-1');
    final artifacts = collector.addFromToolResult(
      metadata: proposalResult.metadata,
      sourceToolCallId: 'todo-call-1',
      createdAt: DateTime.utc(2026, 11, 13),
    );
    final proposal = artifacts.single.todoProposal!;

    expect(proposal.dateState, TodoProposalDateState.ambiguous);
    expect(proposal.datePhrase, 'sexta');
    expect(proposal.dueDate, isNull);
    expect((await router!.loadTodos()).valueOrThrow, isEmpty);

    final viewModel = TodoProposalViewModel(router: router!);
    addTearDown(viewModel.dispose);
    await viewModel.load();
    final result = await viewModel.confirm(
      proposal: proposal,
      text: proposal.title,
      due: '2026-11-20',
      priority: TodoPriority.normal,
      subtasks: const [],
      alertMinutes: 20,
    );

    expect(result.isOk, isTrue);
    final stored = (await router!.loadTodos()).valueOrThrow;
    expect(stored, hasLength(1));
    expect(stored.single.id, proposal.id);
    expect(stored.single.dueDate, '2026-11-20');
    expect(stored.single.dueTime, isNull);
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
