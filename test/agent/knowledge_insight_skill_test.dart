import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/knowledge_insight/knowledge_insight_skill.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KnowledgeInsightSkill', () {
    late AppDatabase db;
    late Directory tempRoot;
    late String userId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);

      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      userId = 'knowledge_insight_${DateTime.now().microsecondsSinceEpoch}';
      await UserStorage.saveUser(userId);

      tempRoot = await Directory.systemTemp.createTemp('memex_insight_skill_');
      await FileSystemService.init(tempRoot.path);
      EventBusService.instance.clearHandlers();
      await EventBusService.instance.connect();
    });

    tearDown(() async {
      EventBusService.instance.clearHandlers();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
      await db.close();
    });

    Future<String> record(String day, int n) async {
      final factId = '2026/06/$day.md#ts_$n';
      await FileSystemService.instance.safeWriteCardFile(
        userId,
        factId,
        CardData(
          factId: factId,
          timestamp: 1782000000 + n,
          status: 'completed',
          tags: const ['obra'],
          uiConfigs: const [],
          fact: 'registro $day/$n',
        ),
      );
      return factId;
    }

    Map<String, dynamic> addCard(String id, List<String> facts,
            {String title = 'Weekly focus'}) =>
        {
          'id': id,
          'template_id': 'summary_card_v1',
          'title': title,
          'insight': 'The week centered on project work.',
          'type': 'add',
          'data': {'insight_title': title},
          'related_facts': facts,
          'tags': ['weekly'],
        };

    Tool saveTool({bool auto = false}) => KnowledgeInsightSkill(
            forceActivate: true, auto: auto)
        .tools!
        .singleWhere((tool) => tool.name == 'save_knowledge_insight_cards');

    test('cited records must exist, and the automatic run needs two', () async {
      final a = await record('20', 1);
      final b = await record('21', 1);
      final meta = {'userId': userId};

      var r = await _runToolCall(
          tool: saveTool(),
          arguments: {
            'cards': [addCard('ghost', ['2026/06/30.md#ts_9'])]
          },
          metadata: meta);
      expect(r.isError, isTrue);
      expect(_text(r), contains('do not exist'));

      r = await _runToolCall(
          tool: saveTool(auto: true),
          arguments: {
            'cards': [addCard('one', [a, a])]
          },
          metadata: meta);
      expect(r.isError, isTrue);
      expect(_text(r), contains('at least 2'));

      r = await _runToolCall(
          tool: saveTool(auto: true),
          arguments: {
            'cards': [addCard('two', [a, b])]
          },
          metadata: meta);
      expect(r.isError, isFalse);
      expect(
          await FileSystemService.instance
              .readKnowledgeInsightCard(userId, 'two'),
          isNotNull);
    });

    test('a new insight needs title, explanation and data', () async {
      final a = await record('20', 1);
      final b = await record('21', 1);
      final bare = addCard('bare', [a, b])..remove('insight');

      final r = await _runToolCall(
          tool: saveTool(),
          arguments: {
            'cards': [bare]
          },
          metadata: {'userId': userId});

      expect(r.isError, isTrue);
      expect(_text(r), contains('needs title, insight'));
    });

    test('the auto run refuses a near-duplicate and marks what it creates',
        () async {
      final a = await record('20', 1);
      final b = await record('21', 1);
      final c = await record('22', 1);
      final meta = {'userId': userId};
      var r = await _runToolCall(
          tool: saveTool(auto: true),
          arguments: {
            'cards': [addCard('first', [a, b])]
          },
          metadata: meta);
      expect(r.isError, isFalse, reason: _text(r));
      expect(
          (await FileSystemService.instance
              .readKnowledgeInsightCard(userId, 'first'))?['source'],
          'auto');

      r = await _runToolCall(
          tool: saveTool(auto: true),
          arguments: {
            'cards': [addCard('again', [a, b], title: 'Outro titulo')]
          },
          metadata: meta);
      expect(r.isError, isTrue);
      expect(_text(r), contains('type "update"'));

      r = await _runToolCall(
          tool: saveTool(auto: true),
          arguments: {
            'cards': [addCard('other', [a, c], title: 'Outro ponto')]
          },
          metadata: meta);
      expect(r.isError, isFalse, reason: 'half the records differ');
    });

    test('an insight the user deleted is not created again by the auto run',
        () async {
      final a = await record('20', 1);
      final b = await record('21', 1);
      await FileSystemService.instance
          .addRejectedInsight(userId, 'custo_laje.yaml', 'Custo da laje');

      final r = await _runToolCall(
          tool: saveTool(auto: true),
          arguments: {
            'cards': [addCard('outro_id', [a, b], title: ' custo da LAJE ')]
          },
          metadata: {'userId': userId});

      expect(r.isError, isTrue);
      expect(_text(r), contains('deleted'));
      expect(
          await FileSystemService.instance.listKnowledgeInsightCards(userId),
          isEmpty);
    });

    test('the list of existing cards is compact; an id returns the full card',
        () async {
      final a = await record('20', 1);
      final b = await record('21', 1);
      await _runToolCall(
          tool: saveTool(),
          arguments: {
            'cards': [addCard('c1', [a, b])]
          },
          metadata: {'userId': userId});
      final list = KnowledgeInsightSkill(forceActivate: true)
          .tools!
          .singleWhere((t) => t.name == 'get_exists_knowledge_insight_cards');

      final compact = await _runToolCall(
          tool: list, arguments: {}, metadata: {'userId': userId});
      expect(_text(compact), isNot(contains('insight_title')));
      expect(_text(compact), contains('"id":"c1"'));

      final full = await _runToolCall(
          tool: list, arguments: {'id': 'c1'}, metadata: {'userId': userId});
      expect(_text(full), contains('insight_title'));
    });

    test('several discoveries in one day share one timeline announcement',
        () async {
      final a = await record('20', 1);
      final b = await record('21', 1);
      final meta = {'userId': userId};
      await _runToolCall(
          tool: saveTool(),
          arguments: {
            'cards': [addCard('c1', [a, b], title: 'Primeiro')]
          },
          metadata: meta);
      await _runToolCall(
          tool: saveTool(),
          arguments: {
            'cards': [addCard('c2', [a, b], title: 'Segundo')]
          },
          metadata: meta);

      final summaries =
          await AppDatabase.instance.cardDao.getCards(tags: ['insight']);
      expect(summaries, hasLength(1));
      final card = await FileSystemService.instance
          .readCardFile(userId, summaries.single.factId);
      expect(
        (card!.uiConfigs.single.data['added_insight_cards'] as List)
            .map((e) => (e as Map)['id']),
        ['c1', 'c2'],
      );
    });

    test('saving insight cards creates and publishes timeline summary card',
        () async {
      final first = await record('20', 1);
      final messages = <EventBusMessage>[];
      EventBusService.instance.addHandler(
        EventBusMessageType.cardAdded,
        messages.add,
      );

      final tool = KnowledgeInsightSkill(forceActivate: true)
          .tools!
          .singleWhere((tool) => tool.name == 'save_knowledge_insight_cards');

      final result = await _runToolCall(
        tool: tool,
        arguments: {
          'cards': [
            {
              'id': 'weekly_focus',
              'template_id': 'summary_card_v1',
              'title': 'Weekly focus',
              'insight': 'The week centered on project work.',
              'type': 'add',
              'data': {'insight_title': 'Weekly focus'},
              'related_facts': [first],
              'tags': ['weekly'],
            }
          ],
        },
        metadata: {'userId': userId},
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.isError, isFalse, reason: _text(result));

      final insight = await FileSystemService.instance
          .readKnowledgeInsightCard(userId, 'weekly_focus');
      expect(insight, isNotNull);
      expect(insight?['title'], 'Weekly focus');

      expect(messages, hasLength(1));
      expect(messages.single, isA<CardAddedMessage>());
      final message = messages.single as CardAddedMessage;
      expect(message.title, UserStorage.l10n.knowledgeNewDiscovery);
      expect(message.tags, ['insight']);
      expect(message.uiConfigs.single.templateId, 'insight_summary');
      expect(
        message.uiConfigs.single.data['added_insight_cards'],
        [
          {'id': 'weekly_focus', 'title': 'Weekly focus'}
        ],
      );

      final summaryCard =
          await FileSystemService.instance.readCardFile(userId, message.id);
      expect(summaryCard, isNotNull);
      expect(summaryCard?.uiConfigs.single.templateId, 'insight_summary');
    });

    test('an update that changes nothing writes nothing and adds no summary',
        () async {
      await record('20', 1);
      await record('21', 1);
      final messages = <EventBusMessage>[];
      EventBusService.instance.addHandler(
        EventBusMessageType.cardAdded,
        messages.add,
      );
      EventBusService.instance.addHandler(
        EventBusMessageType.cardUpdated,
        messages.add,
      );
      final changes = <EventBusMessage>[];
      EventBusService.instance.addHandler(
        EventBusMessageType.newInsight,
        changes.add,
      );
      final tool = KnowledgeInsightSkill(forceActivate: true)
          .tools!
          .singleWhere((tool) => tool.name == 'save_knowledge_insight_cards');
      Map<String, dynamic> card(String type, {String title = 'Weekly focus'}) =>
          {
            'id': 'weekly_focus',
            'template_id': 'summary_card_v1',
            'title': title,
            'insight': 'The week centered on project work.',
            'type': type,
            'data': {'insight_title': title},
            'related_facts': ['2026/06/20.md#ts_1', '2026/06/21.md#ts_1'],
            'tags': ['weekly'],
          };

      await _runToolCall(
        tool: tool,
        arguments: {
          'cards': [card('add')]
        },
        metadata: {'userId': userId},
      );
      await Future<void>.delayed(Duration.zero);
      final stored = await FileSystemService.instance
          .readKnowledgeInsightCard(userId, 'weekly_focus');
      messages.clear();
      changes.clear();

      await _runToolCall(
        tool: tool,
        arguments: {
          'cards': [card('update')]
        },
        metadata: {'userId': userId},
      );
      await Future<void>.delayed(Duration.zero);

      final same = await FileSystemService.instance
          .readKnowledgeInsightCard(userId, 'weekly_focus');
      expect(same?['updated_at'], stored?['updated_at']);
      expect(messages, isEmpty);
      expect(changes, isEmpty);

      await _runToolCall(
        tool: tool,
        arguments: {
          'cards': [card('update', title: 'Weekly focus, revised')]
        },
        metadata: {'userId': userId},
      );
      await Future<void>.delayed(Duration.zero);

      final revised = await FileSystemService.instance
          .readKnowledgeInsightCard(userId, 'weekly_focus');
      expect(revised?['title'], 'Weekly focus, revised');
      expect(messages, hasLength(1));
      expect(changes, hasLength(1));
    });
  });
}

Future<FunctionExecutionResult> _runToolCall({
  required Tool tool,
  required Map<String, dynamic> arguments,
  Map<String, dynamic> metadata = const {},
}) async {
  final client = _SingleToolCallClient(
    toolName: tool.name,
    arguments: arguments,
  );
  final state = AgentState(
    sessionId:
        'knowledge_insight_test_${DateTime.now().microsecondsSinceEpoch}',
    metadata: Map<String, dynamic>.from(metadata),
  );
  final agent = StatefulAgent(
    name: 'knowledge_insight_test_agent',
    client: client,
    modelConfig: ModelConfig(model: 'test-model'),
    state: state,
    tools: [tool],
    withGeneralPrinciples: false,
    maxTurns: 3,
  );

  await agent.run([UserMessage.text('run the tool')], useStream: false);

  final resultMessage =
      state.history.messages.whereType<FunctionExecutionResultMessage>().single;
  return resultMessage.results.single;
}

class _SingleToolCallClient extends LLMClient {
  _SingleToolCallClient({
    required this.toolName,
    required this.arguments,
  });

  final String toolName;
  final Map<String, dynamic> arguments;
  var _callCount = 0;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    _callCount += 1;
    if (_callCount == 1) {
      return ModelMessage(
        model: modelConfig.model,
        stopReason: 'tool_calls',
        functionCalls: [
          FunctionCall(
            id: 'call_1',
            name: toolName,
            arguments: jsonEncode(arguments),
          ),
        ],
      );
    }
    return ModelMessage(
      model: modelConfig.model,
      stopReason: 'stop',
      textOutput: 'done',
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

String _text(FunctionExecutionResult r) =>
    r.content.whereType<TextPart>().map((p) => p.text).join();
