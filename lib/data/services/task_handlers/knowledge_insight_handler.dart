import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/agent/skills/knowledge_insight/knowledge_insight_skill.dart';
import 'package:memex/agent/super_agent/subagent/super_agent_child.dart';
import 'package:memex/data/services/event_bus_service.dart';
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
    // A model chosen for Insights wins; otherwise the chat model, as before.
    final own = (await UserStorage.getAgentConfig(AgentDefinitions.insightAgent))
        .llmConfigKey;
    final agentId = own != null && own.isNotEmpty
        ? AgentDefinitions.insightAgent
        : AgentDefinitions.chatAgent;
    final config = await UserStorage.getAgentLLMConfig(
      agentId,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    if (!config.isValid) return null;
    final resolved = await UserStorage.getAgentLLMResources(
      agentId,
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
  final periodic = payload['periodic'] == true;
  final files = FileSystemService.instance;

  try {
    await pruneInsightEvidence(userId);
  } catch (e) {
    _logger.warning('Could not prune insight evidence: $e');
  }

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

  final savedRows = await _savedRecords();
  if (savedRows.length < minRecordsForInsights) {
    _logger.info(
      'Only ${savedRows.length} saved record(s), fewer than '
      '$minRecordsForInsights: no pattern can be supported yet',
    );
    await finish(InsightOutcome.tooFewRecords, '${savedRows.length}');
    return;
  }

  final index = await _recentRecordIndex(userId, savedRows);

  // A batch the user did not ask for must have a tag, or two words, in common
  // with another record; otherwise nothing can be compared and the model call
  // is wasted.
  if (!manual && !periodic) {
    final newTags = <List<String>>[];
    final newTexts = <String>[];
    for (final id in factIds) {
      final card = await files.readCardFile(userId, id);
      newTags.add(card?.tags ?? const []);
      newTexts.add('${card?.title ?? ''} ${card?.fact ?? ''}');
    }
    final linked = tagsCanLinkRecords(newTags, savedRows.map((r) => r.tags)) ||
        textsShareTerms(newTexts,
            [for (final e in index) if (!factIds.contains(e.factId)) e.text]);
    if (!linked) {
      _logger.info('Nothing links the new records to earlier ones, skipping');
      await finish(InsightOutcome.noPattern);
      return;
    }
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
        recentIndex: index.map((e) => e.line).join('\n'),
        manual: manual,
        periodic: periodic,
        valuedTitles: [
          for (final c in await files.listKnowledgeInsightCards(userId))
            if (c['pinned'] == true && '${c['title'] ?? ''}'.isNotEmpty)
              '${c['title']}',
        ],
        rejectedTitles: [
          for (final r in await files.readRejectedInsights(userId))
            if ((r['title'] ?? '').isNotEmpty) r['title']!,
        ],
      ),
      contextPacket: {
        'new_fact_ids': factIds,
        'trigger': manual
            ? 'manual'
            : periodic
                ? 'periodic'
                : 'record_saved',
      },
      skills: [KnowledgeInsightSkill(forceActivate: true, auto: true)],
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

/// The latest records as `path | date | title | tags` lines, so the agent
/// picks what to read (and groups by tag) instead of searching for it. [text]
/// is what the cheap link check compares.
Future<List<({String factId, String line, String text})>> _recentRecordIndex(
  String userId,
  List<({String factId, int timestamp, List<String> tags})> saved,
) async {
  final files = FileSystemService.instance;
  final out = <({String factId, String line, String text})>[];
  for (final row in saved.take(40)) {
    final card = await files.readCardFile(userId, row.factId);
    if (card == null) continue;
    final title = (card.title ?? card.fact ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final day = DateTime.fromMillisecondsSinceEpoch(row.timestamp * 1000)
        .toIso8601String()
        .substring(0, 10);
    out.add((
      factId: row.factId,
      text: '${card.title ?? ''} ${card.fact ?? ''}',
      line: '${Prompts.cardFileOfFact(row.factId)} | $day | '
          '${title.length > 80 ? '${title.substring(0, 80)}...' : title}'
          '${row.tags.isEmpty ? '' : ' | ${row.tags.map((t) => '#$t').join(' ')}'}',
    ));
  }
  return out;
}

/// Takes out evidence ids whose records are gone. An insight the engine made
/// (`source: auto`), not pinned, left with fewer than two records is removed:
/// it no longer rests on a pattern. Returns how many insights changed.
Future<int> pruneInsightEvidence(String userId) async {
  final files = FileSystemService.instance;
  var changed = 0;
  for (final card in await files.listKnowledgeInsightCards(userId)) {
    final facts = (card['related_facts'] as List?)?.map((e) => '$e').toList();
    if (facts == null || facts.isEmpty) continue;
    final alive = [
      for (final f in facts)
        if (await files.readCardFile(userId, f) != null) f,
    ];
    if (alive.length == facts.length) continue;
    final id = '${card['id']}';
    if (card['source'] == 'auto' &&
        card['pinned'] != true &&
        alive.length < minRecordsForInsightEvidence) {
      if (await files.deleteKnowledgeInsightCard(userId, id)) changed++;
      continue;
    }
    if (alive.isEmpty) continue; // nothing to replace the old list with
    card['related_facts'] = alive;
    card['updated_at'] = DateTime.now().toIso8601String();
    await files.writeKnowledgeInsightCard(userId, id, card);
    changed++;
  }
  if (changed > 0) {
    EventBusService.instance.emitEvent(NewInsightMessage(insightId: '', html: ''));
  }
  return changed;
}

/// Saved records (newest first) that are not insight announcements.
Future<List<({String factId, int timestamp, List<String> tags})>>
    _savedRecords() async {
  final rows = await AppDatabase.instance.cardDao.getCards(limit: 200);
  final out = <({String factId, int timestamp, List<String> tags})>[];
  for (final row in rows) {
    var tags = <String>[];
    try {
      tags = (jsonDecode(row.tags) as List).map((t) => '$t').toList();
    } on FormatException {
      // Unreadable tags only mean the record has none to compare.
    }
    if (tags.contains('insight')) continue;
    out.add((factId: row.factId, timestamp: row.timestamp, tags: tags));
  }
  return out;
}
