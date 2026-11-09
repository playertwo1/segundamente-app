import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/agent/super_agent/subagent/super_agent_child.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/data/services/knowledge_insight_trigger_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/task_handlers/knowledge_insight_handler.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/insight_trigger.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalResources = KnowledgeInsightTaskDeps.resources;
  late AppDatabase db;
  late Directory tempRoot;
  late String userId;
  late LocalTaskExecutor executor;
  late KnowledgeInsightTriggerService trigger;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    userId = 'insight_trigger_${DateTime.now().microsecondsSinceEpoch}';
    await UserStorage.saveUser(userId);
    tempRoot = await Directory.systemTemp.createTemp('memex_insight_trigger_');
    await FileSystemService.init(tempRoot.path);
    executor = LocalTaskExecutor.forTesting(db: db);
    trigger = KnowledgeInsightTriggerService(
      executor: executor,
      debounce: Duration.zero,
    );
  });

  tearDown(() async {
    KnowledgeInsightTaskDeps.runChild = runSuperAgentChild;
    KnowledgeInsightTaskDeps.resources = originalResources;
    await executor.stop();
    for (var attempt = 0; await tempRoot.exists(); attempt++) {
      try {
        await tempRoot.delete(recursive: true);
      } on PathAccessException {
        if (attempt >= 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    await db.close();
  });

  var counter = 0;
  Future<String> saveRecord(
    String text, {
    List<UiConfig> ui = const [],
    List<String> tags = const ['obra'],
  }) async {
    final factId = '2026/11/05.md#ts_${++counter}';
    await FileSystemService.instance.safeWriteCardFile(
      userId,
      factId,
      CardData(
        factId: factId,
        timestamp: 1762300000 + counter,
        status: 'completed',
        tags: tags,
        uiConfigs: ui,
        fact: text,
      ),
    );
    return factId;
  }

  SystemEvent<UserInputSubmittedPayload> saved(String factId) => SystemEvent(
        type: SystemEventTypes.userInputSubmitted,
        source: 'test',
        payload: UserInputSubmittedPayload(
          factId: factId,
          assetPaths: const [],
          combinedText: '',
          markdownEntry: '',
          createdAtTs: 1762300000,
          pkmCreatedAtTs: 1762300000,
        ),
      );

  Future<List<Task>> insightTasks() =>
      (db.select(db.tasks)..where((t) => t.type.equals(insightTaskType))).get();

  List<String> idsOf(Task task) =>
      ((jsonDecode(task.payload!) as Map)['fact_ids'] as List).cast<String>();

  group('trigger after a confirmed save', () {
    test('a saved record queues one analysis and does no model work itself',
        () async {
      var ran = false;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        ran = true;
        throw StateError('must not run while queueing');
      };
      final id = await saveRecord('concreto da laje, 3 sacos');

      expect(await trigger.onRecordSaved(userId, saved(id)), isTrue);

      final tasks = await insightTasks();
      expect(tasks, hasLength(1));
      expect(tasks.single.status, 'pending');
      expect(idsOf(tasks.single), [id]);
      expect(ran, isFalse);
    });

    test('publishing the capture event on the bus queues the analysis',
        () async {
      final bus = GlobalEventBus.forTesting(executor);
      registerKnowledgeInsightTrigger(bus, service: trigger);
      final id = await saveRecord('cimento e areia para o reboco');
      final summary = await saveRecord(
        '',
        ui: const [UiConfig(templateId: 'insight_summary', data: {})],
        tags: const ['insight'],
      );

      await bus.publish(userId: userId, event: saved(id));
      await bus.publish(userId: userId, event: saved(summary));

      final tasks = await insightTasks();
      expect(tasks, hasLength(1));
      expect(idsOf(tasks.single), [id]);
    });

    test('a record that is not on disk queues nothing', () async {
      expect(
        await trigger.onRecordSaved(userId, saved('2026/11/05.md#ts_404')),
        isFalse,
      );
      expect(await insightTasks(), isEmpty);
    });

    test('a burst of records shares one task, each id once', () async {
      final a = await saveRecord('primeira parte da conversa');
      final b = await saveRecord('segunda parte da conversa');
      final c = await saveRecord('terceira parte da conversa');

      for (final id in [a, b, c, b]) {
        await trigger.onRecordSaved(userId, saved(id));
      }

      final tasks = await insightTasks();
      expect(tasks, hasLength(1));
      expect(idsOf(tasks.single), [a, b, c]);
    });

    test('a record is handed to an analysis at most once, even after it ran',
        () async {
      final id = await saveRecord('orcamento do pedreiro');
      await trigger.onRecordSaved(userId, saved(id));
      await (db.update(db.tasks)).write(
        const TasksCompanion(status: Value('completed')),
      );

      expect(await trigger.onRecordSaved(userId, saved(id)), isFalse);
      expect(await insightTasks(), hasLength(1));
    });

    test(
        'insight summaries, empty records and insight-tagged cards are ignored',
        () async {
      final summary = await saveRecord(
        '',
        ui: const [
          UiConfig(templateId: 'insight_summary', data: {'added': []}),
        ],
        tags: const ['insight'],
      );
      final tagged =
          await saveRecord('texto qualquer', tags: const ['insight']);
      final templated = await saveRecord(
        'resumo',
        ui: const [UiConfig(templateId: 'insight_summary', data: {})],
      );
      final empty = await saveRecord('   ');

      for (final id in [summary, tagged, templated, empty]) {
        expect(await trigger.onRecordSaved(userId, saved(id)), isFalse,
            reason: id);
      }
      expect(await insightTasks(), isEmpty);
    });
  });

  group('analysis task', () {
    SuperAgentChildResult result(SuperAgentChildStatus status) =>
        SuperAgentChildResult(
          childName: 'knowledge_insight_auto',
          status: status,
          summary: status.name,
          error: status == SuperAgentChildStatus.failed ? 'model down' : null,
        );

    void fakeModel() {
      KnowledgeInsightTaskDeps.resources = () async =>
          (client: _ToolCallClient.none(), model: ModelConfig(model: 'fake'));
    }

    test('with too few saved records the model is never called', () async {
      fakeModel();
      var calls = 0;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        calls++;
        return result(SuperAgentChildStatus.completed);
      };
      final one = await saveRecord('so um registro');
      final two = await saveRecord('outro registro');

      await handleKnowledgeInsightImpl(
        userId,
        {
          'fact_ids': [one, two]
        },
        TaskContext(taskId: 't', taskType: insightTaskType),
      );

      expect(calls, 0);
    });

    test(
        'with enough records it runs the insight skill read-only on the new ids',
        () async {
      fakeModel();
      SuperAgentChildConfig? seen;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        seen = config;
        return result(SuperAgentChildStatus.noOp);
      };
      await saveRecord('registro 1');
      await saveRecord('registro 2');
      final fresh = await saveRecord('registro 3');

      await handleKnowledgeInsightImpl(
        userId,
        {
          'fact_ids': [fresh]
        },
        TaskContext(taskId: 't', taskType: insightTaskType),
      );

      expect(seen, isNotNull);
      expect(seen!.toolProfile, ChildToolProfile.read);
      expect(seen!.skills.map((s) => s.name), ['update_knowledge_insight']);
      expect(seen!.taskBrief, contains(fresh));
      expect(seen!.taskBrief, contains('no_op'));
      expect(seen!.contextPacket['new_fact_ids'], [fresh]);
    });

    test('a failed run throws so the queue retries it', () async {
      fakeModel();
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async =>
          result(SuperAgentChildStatus.failed);
      await saveRecord('registro 1');
      await saveRecord('registro 2');
      final fresh = await saveRecord('registro 3');

      executor.registerHandler(insightTaskType, handleKnowledgeInsightImpl);
      await trigger.onRecordSaved(userId, saved(fresh));
      await executor.drainAvailableTasks(
        userId: userId,
        maxDuration: const Duration(seconds: 5),
      );

      final task = (await insightTasks()).single;
      expect(task.status, 'retrying');
      expect(task.retryCount, 1);
      expect(task.error, contains('model down'));
    });

    Future<Map<String, dynamic>> runAndReadResult(
      Map<String, dynamic> payload,
    ) async {
      final taskId = await executor.enqueueTask(
        userId: userId,
        taskType: insightTaskType,
        payload: payload,
      );
      await handleKnowledgeInsightImpl(
        userId,
        payload,
        TaskContext(taskId: taskId, taskType: insightTaskType),
      );
      final row = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
          .getSingle();
      return jsonDecode(row.result!) as Map<String, dynamic>;
    }

    test('the outcome is kept in the task result so the screen can say why',
        () async {
      fakeModel();
      final one = await saveRecord('so um registro');
      expect(
          await runAndReadResult({
            'fact_ids': [one]
          }),
          {'outcome': 'tooFewRecords', 'detail': '1'});

      await saveRecord('registro 2');
      await saveRecord('registro 3');
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async =>
          const SuperAgentChildResult(
            childName: 'knowledge_insight_auto',
            status: SuperAgentChildStatus.noOp,
            summary: 'no_op - so ha um registro sobre o Atlas.',
          );
      expect(
          await runAndReadResult({
            'fact_ids': [one]
          }),
          {
            'outcome': 'noPattern',
            'detail': 'so ha um registro sobre o Atlas.'
          });

      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async =>
          result(SuperAgentChildStatus.completed);
      expect(
          (await runAndReadResult({
            'fact_ids': [one]
          }))['outcome'],
          'saved');

      KnowledgeInsightTaskDeps.resources = () async => null;
      expect(
          (await runAndReadResult({
            'fact_ids': [one]
          }))['outcome'],
          'noModel');
      expect(
          (await runAndReadResult({
            'fact_ids': ['2026/11/05.md#ts_404']
          }))['outcome'],
          'noRecord');
    });

    test('the brief lists the latest records and a manual run says so',
        () async {
      fakeModel();
      final ids = [
        await saveRecord('cimento para a laje'),
        await saveRecord('areia para o reboco'),
        await saveRecord('tijolo para a parede'),
      ];
      String? brief;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        brief = config.taskBrief;
        return result(SuperAgentChildStatus.noOp);
      };

      await runAndReadResult({'fact_ids': ids, 'manual': true});

      expect(brief, contains('The user asked for an analysis'));
      expect(brief, contains('${Prompts.cardFileOfFact(ids.first)} |'));
      expect(brief, contains('cimento para a laje'));
    });
  });

  group('capture to insight', () {
    test('a saved record becomes an insight backed by its records, once',
        () async {
      final first = await saveRecord('concreto da laje: 12 sacos, R\$ 480');
      final second = await saveRecord('pedreiro cobrou R\$ 900 pela laje');
      final third = await saveRecord('ferragem da laje: R\$ 1.200');
      final scripted = _ToolCallClient(
        toolName: 'save_knowledge_insight_cards',
        arguments: {
          'cards': [
            {
              'id': 'custo_da_laje',
              'template_id': 'summary_card_v1',
              'title': 'Custo da laje',
              'insight': 'Três registros somam os gastos com a laje.',
              'type': 'add',
              'data': {'insight_title': 'Custo da laje'},
              'related_facts': [first, second, third],
              'tags': ['obra'],
            },
          ],
        },
      );
      KnowledgeInsightTaskDeps.resources =
          () async => (client: scripted, model: ModelConfig(model: 'fake'));
      executor.registerHandler(
        insightTaskType,
        handleKnowledgeInsightImpl,
        concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
      );

      // Capture finishes: three records saved, each announced.
      for (final id in [first, second, third]) {
        await trigger.onRecordSaved(userId, saved(id));
      }
      expect(await insightTasks(), hasLength(1));

      await executor.drainAvailableTasks(
        userId: userId,
        maxDuration: const Duration(seconds: 20),
      );

      final task = (await insightTasks()).single;
      expect(task.status, 'completed');

      final insight = await FileSystemService.instance
          .readKnowledgeInsightCard(userId, 'custo_da_laje');
      expect(insight, isNotNull);
      expect(insight!['related_facts'], [first, second, third]);

      // The announcement card was written, and it does not start anything.
      final timeline = await db.cardDao.getCards(tags: ['insight'], limit: 10);
      expect(timeline, hasLength(1));
      expect(
        await trigger.onRecordSaved(userId, saved(timeline.single.factId)),
        isFalse,
      );

      // The same records, announced again, are not analysed again.
      for (final id in [first, second, third]) {
        expect(await trigger.onRecordSaved(userId, saved(id)), isFalse);
      }
      expect(await insightTasks(), hasLength(1));
      expect(scripted.calls, 2); // one tool call + the closing message
    });

    test('with no evidence the run saves nothing and writes no summary',
        () async {
      await saveRecord('registro A');
      await saveRecord('registro B');
      final fresh = await saveRecord('registro C');
      final scripted = _ToolCallClient.none(finalText: 'no_op: nothing links');
      KnowledgeInsightTaskDeps.resources =
          () async => (client: scripted, model: ModelConfig(model: 'fake'));
      executor.registerHandler(insightTaskType, handleKnowledgeInsightImpl);
      await trigger.onRecordSaved(userId, saved(fresh));

      await executor.drainAvailableTasks(
        userId: userId,
        maxDuration: const Duration(seconds: 20),
      );

      expect((await insightTasks()).single.status, 'completed');
      expect(await FileSystemService.instance.listKnowledgeInsightCards(userId),
          isEmpty);
      expect(await db.cardDao.getCards(tags: ['insight'], limit: 10), isEmpty);
    });
  });

  group('manual analysis', () {
    Future<List<String>> latestIds(Task task) async =>
        ((jsonDecode(task.payload!) as Map)['fact_ids'] as List).cast<String>();

    test('queues the latest readable records at once, once at a time',
        () async {
      for (var i = 0; i < 25; i++) {
        await saveRecord('registro $i');
      }
      final summary = await saveRecord('',
          ui: const [UiConfig(templateId: 'insight_summary', data: {})],
          tags: const ['insight']);

      expect(await requestManualInsightAnalysis(userId, executor: executor),
          isTrue);
      final task = (await insightTasks()).single;
      expect((jsonDecode(task.payload!) as Map)['manual'], isTrue);
      final ids = await latestIds(task);
      expect(ids, hasLength(manualInsightRecords));
      expect(ids, isNot(contains(summary)));
      // No wait: it is due now (the debounce of an automatic run is not used).
      expect(task.scheduledAt ?? 0,
          lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch ~/ 1000));

      expect(await requestManualInsightAnalysis(userId, executor: executor),
          isFalse,
          reason: 'one is already waiting');
      expect(await insightTasks(), hasLength(1));
    });

    test('an active task belonging to another user does not block analysis',
        () async {
      await saveRecord('registro atual');
      await executor.enqueueTask(
        userId: 'another_user',
        taskType: insightTaskType,
        payload: const {},
        bizId: insightManualBatchKey('another_user'),
      );

      expect(
        await requestManualInsightAnalysis(userId, executor: executor),
        isTrue,
      );
      expect(await insightTasks(), hasLength(2));
    });

    test('a waiting automatic analysis for this user blocks a manual one',
        () async {
      await saveRecord('registro atual');
      await executor.enqueueTask(
        userId: userId,
        taskType: insightTaskType,
        payload: const {},
        bizId: insightBatchKey(userId),
      );

      expect(
        await requestManualInsightAnalysis(userId, executor: executor),
        isFalse,
      );
      expect(await insightTasks(), hasLength(1));
    });

    test('with no record it queues nothing', () async {
      expect(await requestManualInsightAnalysis(userId, executor: executor),
          isFalse);
      expect(await insightTasks(), isEmpty);
    });
  });

  group('periodic analysis', () {
    Future<void> lastRanAt(int seconds) async {
      final id = await executor.enqueueTask(
        userId: userId,
        taskType: insightTaskType,
        payload: const {},
        bizId: insightManualBatchKey(userId),
      );
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('completed'),
          completedAt: Value(seconds),
        ),
      );
    }

    test('runs when a week passed and records arrived since', () async {
      await saveRecord('registro');
      await lastRanAt(1762300000); // long ago; the record is newer
      expect(await requestPeriodicInsightAnalysis(userId, executor: executor),
          isTrue);
      final latest = (await insightTasks()).last;
      expect((jsonDecode(latest.payload!) as Map)['periodic'], isTrue);
    });

    test('waits when the last run is recent or nothing new arrived', () async {
      await saveRecord('registro');
      await lastRanAt(DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600);
      expect(await requestPeriodicInsightAnalysis(userId, executor: executor),
          isFalse);
      expect(await insightTasks(), hasLength(1));
    });

    test('does not run again for records already seen by the last run',
        () async {
      await saveRecord('registro'); // timestamp 1762300001
      await lastRanAt(1762300500); // a week+ ago, but after the record
      expect(await requestPeriodicInsightAnalysis(userId, executor: executor),
          isFalse);
    });
  });

  group('tags and rejections', () {
    test('tagsCanLinkRecords needs a tag (or its parent) on a second record',
        () {
      expect(
        tagsCanLinkRecords([
          ['a']
        ], [
          ['a'],
          ['b']
        ]),
        isFalse,
      );
      expect(
        tagsCanLinkRecords([
          ['a']
        ], [
          ['a'],
          ['a']
        ]),
        isTrue,
      );
      expect(
        tagsCanLinkRecords([
          ['area/obra']
        ], [
          ['area/obra'],
          ['area/casa']
        ]),
        isTrue,
        reason: 'they share the parent tag area',
      );
      expect(tagsCanLinkRecords([<String>[]], [<String>[], <String>[]]), isTrue,
          reason: 'untagged records are left to the model');
    });

    test('words in common are a second chance when the tags differ', () {
      expect(
        textsShareTerms(['Concreto armado da laje do prédio'],
            ['pedreiro cobrou o concreto armado da laje']),
        isTrue,
      );
      expect(
        textsShareTerms(['Concreto armado da laje do prédio'], ['passeio no parque']),
        isFalse,
      );
      expect(textsShareTerms(['laje'], ['laje']), isFalse,
          reason: 'one short word is not enough');
      expect(evidenceOverlap(['a', 'b', 'c'], ['a', 'b']), 1.0);
      expect(evidenceOverlap(['a', 'b'], ['b', 'c']), 0.5);
    });

    SuperAgentChildResult noOpResult() => const SuperAgentChildResult(
          childName: 'knowledge_insight_auto',
          status: SuperAgentChildStatus.noOp,
          summary: 'no_op',
        );

    Future<void> runAuto(List<String> ids) async {
      final taskId = await executor.enqueueTask(
          userId: userId, taskType: insightTaskType, payload: const {});
      await handleKnowledgeInsightImpl(
        userId,
        {'fact_ids': ids},
        TaskContext(taskId: taskId, taskType: insightTaskType),
      );
    }

    test('different tags but shared words still reach the model', () async {
      KnowledgeInsightTaskDeps.resources = () async =>
          (client: _ToolCallClient.none(), model: ModelConfig(model: 'fake'));
      var calls = 0;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        calls++;
        return noOpResult();
      };
      await saveRecord('concreto armado da laje', tags: const ['obra']);
      await saveRecord('pedreiro e concreto armado na laje', tags: const ['custos']);
      await saveRecord('passeio no parque', tags: const ['lazer']);
      final fresh = await saveRecord('ferragem, concreto armado e laje',
          tags: const ['material']);

      await runAuto([fresh]);

      expect(calls, 1);
    });

    test('evidence that disappeared is pruned; pinned and chat insights stay',
        () async {
      final live1 = await saveRecord('a');
      final live2 = await saveRecord('b');
      final fs = FileSystemService.instance;
      Future<void> put(String id, List<String> facts,
              {String? source, bool pinned = false}) =>
          fs.writeKnowledgeInsightCard(userId, id, {
            'id': id,
            'title': id,
            'template_id': 'summary_card_v1',
            'insight': 'x',
            'data': {'insight_title': id},
            'related_facts': facts,
            'pinned': pinned,
            if (source != null) 'source': source,
          });
      const gone = '2026/11/05.md#ts_404';
      await put('auto_dead', [live1, gone], source: 'auto');
      await put('auto_ok', [live1, live2, gone], source: 'auto');
      await put('auto_pinned', [live1, gone], source: 'auto', pinned: true);
      await put('chat_one', [live1, gone]);
      await put('chat_none', [gone]);

      expect(await pruneInsightEvidence(userId), 4);

      Future<dynamic> facts(String id) async =>
          (await fs.readKnowledgeInsightCard(userId, id))?['related_facts'];
      expect(await fs.readKnowledgeInsightCard(userId, 'auto_dead'), isNull);
      expect(await facts('auto_ok'), [live1, live2]);
      expect(await facts('auto_pinned'), [live1]);
      expect(await facts('chat_one'), [live1]);
      expect(await facts('chat_none'), [gone],
          reason: 'nothing to replace it with');
    });

    test('the brief shows what the user pinned', () async {
      KnowledgeInsightTaskDeps.resources = () async =>
          (client: _ToolCallClient.none(), model: ModelConfig(model: 'fake'));
      final ids = [
        await saveRecord('a'),
        await saveRecord('b'),
        await saveRecord('c'),
      ];
      await FileSystemService.instance
          .writeKnowledgeInsightCard(userId, 'fav', {
        'id': 'fav',
        'title': 'Meu favorito',
        'pinned': true,
        'related_facts': [ids[0]],
      });
      String? brief;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        brief = config.taskBrief;
        return noOpResult();
      };

      await runAuto(ids);

      expect(brief, contains('- Meu favorito'));
    });

    test('an unrelated new record ends without calling the model', () async {
      KnowledgeInsightTaskDeps.resources = () async =>
          (client: _ToolCallClient.none(), model: ModelConfig(model: 'fake'));
      var calls = 0;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        calls++;
        return const SuperAgentChildResult(
          childName: 'knowledge_insight_auto',
          status: SuperAgentChildStatus.noOp,
          summary: 'no_op',
        );
      };
      await saveRecord('a', tags: const ['obra']);
      await saveRecord('b', tags: const ['obra']);
      await saveRecord('c', tags: const ['obra']);
      final lone = await saveRecord('d', tags: const ['viagem']);
      final taskId = await executor.enqueueTask(
          userId: userId, taskType: insightTaskType, payload: const {});

      await handleKnowledgeInsightImpl(
        userId,
        {
          'fact_ids': [lone]
        },
        TaskContext(taskId: taskId, taskType: insightTaskType),
      );
      expect(calls, 0);

      // The user asking for it is not second-guessed.
      await handleKnowledgeInsightImpl(
        userId,
        {
          'fact_ids': [lone],
          'manual': true
        },
        TaskContext(taskId: taskId, taskType: insightTaskType),
      );
      expect(calls, 1);
    });

    test('the brief carries tags and what the user deleted', () async {
      KnowledgeInsightTaskDeps.resources = () async =>
          (client: _ToolCallClient.none(), model: ModelConfig(model: 'fake'));
      final ids = [
        await saveRecord('a', tags: const ['obra']),
        await saveRecord('b', tags: const ['obra']),
        await saveRecord('c', tags: const ['obra']),
      ];
      await FileSystemService.instance
          .addRejectedInsight(userId, 'x', 'Custo da laje');
      String? brief;
      KnowledgeInsightTaskDeps.runChild = ({
        required config,
        required client,
        required modelConfig,
        required userId,
      }) async {
        brief = config.taskBrief;
        return const SuperAgentChildResult(
          childName: 'knowledge_insight_auto',
          status: SuperAgentChildStatus.noOp,
          summary: 'no_op',
        );
      };
      final taskId = await executor.enqueueTask(
          userId: userId, taskType: insightTaskType, payload: const {});

      await handleKnowledgeInsightImpl(
        userId,
        {'fact_ids': ids},
        TaskContext(taskId: taskId, taskType: insightTaskType),
      );

      expect(brief, contains('#obra'));
      expect(brief, contains('- Custo da laje'));
    });
  });
}

/// Scripted model: optionally calls one tool, then answers [finalText].
class _ToolCallClient extends LLMClient {
  _ToolCallClient({required this.toolName, required this.arguments})
      : finalText = 'done';

  _ToolCallClient.none({this.finalText = 'done'})
      : toolName = null,
        arguments = const {};

  final String? toolName;
  final Map<String, dynamic> arguments;
  final String finalText;
  var calls = 0;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    calls++;
    if (toolName != null && calls == 1) {
      return ModelMessage(
        model: modelConfig.model,
        stopReason: 'tool_calls',
        functionCalls: [
          FunctionCall(
            id: 'call_1',
            name: toolName!,
            arguments: jsonEncode(arguments),
          ),
        ],
      );
    }
    return ModelMessage(
      model: modelConfig.model,
      stopReason: 'stop',
      textOutput: finalText,
    );
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    throw UnsupportedError('Streaming is not used by this test client.');
  }
}
