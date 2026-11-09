import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/agent/skills/knowledge_insight/knowledge_insight_skill.dart';
import 'package:memex/agent/super_agent/subagent/super_agent_child.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/insight_trigger.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('KnowledgeInsightHandler');

typedef InsightChildRunner = Future<SuperAgentChildResult> Function({
  required SuperAgentChildConfig config,
  required LLMClient client,
  required ModelConfig modelConfig,
  required String userId,
});

typedef InsightModelResources = Future<({LLMClient client, ModelConfig model})?>
    Function();

/// Seams for tests: the child runner and the model the user configured.
class KnowledgeInsightTaskDeps {
  KnowledgeInsightTaskDeps._();

  static InsightChildRunner runChild = runSuperAgentChild;

  static InsightModelResources resources = () async {
    final config = await UserStorage.getAgentLLMConfig(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    if (!config.isValid) return null;
    final resolved = await UserStorage.getAgentLLMResources(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    return (client: resolved.client, model: resolved.modelConfig);
  };
}

/// Runs the automatic insight analysis for a batch of saved records.
///
/// The worker gets only the insight skill and read-only file tools: it cannot
/// save a timeline card, so nothing it does can publish a new capture event
/// and start another analysis. Writes go through `KnowledgeInsightSkill`'s
/// managed save tool, which keeps `related_facts` and announces the change to
/// the screens. A failed run throws so the queue retries it.
Future<void> handleKnowledgeInsightImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final requested = (payload['fact_ids'] as List?)?.cast<String>() ?? const [];
  final manual = payload['manual'] == true;
  final files = FileSystemService.instance;

  Future<void> finish(InsightOutcome outcome, [String detail = '']) =>
      LocalTaskExecutor.instance.updateTaskResult(
        context.taskId,
        jsonEncode({'outcome': outcome.name, 'detail': detail}),
      );

  final factIds = <String>[];
  for (final id in requested) {
    final card = await files.readCardFile(userId, id);
    if (card != null && startsInsightAnalysis(card)) factIds.add(id);
  }
  if (factIds.isEmpty) {
    _logger.info('No readable new record for the insight analysis, skipping');
    await finish(InsightOutcome.noRecord);
    return;
  }

  final saved = await _savedRecordCount();
  if (saved < minRecordsForInsights) {
    _logger.info(
      'Only $saved saved record(s), fewer than $minRecordsForInsights: '
      'no pattern can be supported yet',
    );
    await finish(InsightOutcome.tooFewRecords, '$saved');
    return;
  }

  final model = await KnowledgeInsightTaskDeps.resources();
  if (model == null) {
    _logger.info('No LLM configured, skipping the insight analysis');
    await finish(InsightOutcome.noModel);
    return;
  }

  final result = await KnowledgeInsightTaskDeps.runChild(
    config: SuperAgentChildConfig(
      childName: 'knowledge_insight_auto',
      taskBrief: Prompts.knowledgeInsightAutoTaskBrief(
        factIds,
        recentIndex: await _recentRecordIndex(userId),
        manual: manual,
      ),
      contextPacket: {
        'new_fact_ids': factIds,
        'trigger': manual ? 'manual' : 'record_saved',
      },
      skills: [KnowledgeInsightSkill(forceActivate: true)],
      toolProfile: ChildToolProfile.read,
    ),
    client: model.client,
    modelConfig: model.model,
    userId: userId,
  );

  if (result.status == SuperAgentChildStatus.failed) {
    throw StateError(
      'Insight analysis failed: ${result.error ?? result.summary}',
    );
  }
  _logger.info('Insight analysis ${result.status.name} for $factIds');
  await finish(
    result.status == SuperAgentChildStatus.completed
        ? InsightOutcome.saved
        : InsightOutcome.noPattern,
    insightReason(result.summary),
  );
}

/// The latest records as `path | date | title` lines, so the agent picks what
/// to read instead of searching the workspace for it.
Future<String> _recentRecordIndex(String userId) async {
  final files = FileSystemService.instance;
  final rows = await AppDatabase.instance.cardDao.getCards(limit: 40);
  final lines = <String>[];
  for (final row in rows) {
    final card = await files.readCardFile(userId, row.factId);
    if (card == null || isInsightSummaryCard(card)) continue;
    final title = (card.title ?? card.fact ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final day = DateTime.fromMillisecondsSinceEpoch(row.timestamp * 1000)
        .toIso8601String()
        .substring(0, 10);
    lines.add(
      '${Prompts.cardFileOfFact(row.factId)} | $day | '
      '${title.length > 80 ? '${title.substring(0, 80)}...' : title}',
    );
  }
  return lines.join('\n');
}

/// Saved records that are not insight announcements.
Future<int> _savedRecordCount() async {
  final cards = await AppDatabase.instance.cardDao.getCards(limit: 200);
  return cards.where((c) => !c.tags.contains('"insight"')).length;
}
