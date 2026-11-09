import 'dart:convert';

import 'package:memex/domain/models/card_model.dart';

/// Task that analyses newly saved records and, only with evidence across
/// records, creates or updates Knowledge Insights.
const insightTaskType = 'knowledge_insight_task';

/// One waiting task per user; every record saved while it waits joins it, so a
/// chat, a transcript or a batch import costs one analysis, not one per card.
String insightBatchKey(String userId) => 'knowledge_insight:$userId';

String insightManualBatchKey(String userId) =>
    'knowledge_insight_manual:$userId';

List<String> insightTaskBizIds(String userId) => [
      insightBatchKey(userId),
      insightManualBatchKey(userId),
    ];

/// How long a batch waits for more records before it runs.
const insightDebounce = Duration(minutes: 2);

/// Fewer saved records than this cannot show a pattern across records, so the
/// analysis ends without calling the model.
const minRecordsForInsights = 3;

const _insightSummaryTemplate = 'insight_summary';
const _insightTag = 'insight';

/// True for the timeline card the insight skill writes to announce its own
/// work. It must never start another analysis.
bool isInsightSummaryCard(CardData card) =>
    card.uiConfigs.any((ui) => ui.templateId == _insightSummaryTemplate) ||
    card.tags.contains(_insightTag);

/// Whether a saved record may start an analysis: it holds text or a title the
/// analysis can read, and is not an insight summary.
bool startsInsightAnalysis(CardData card) {
  if (isInsightSummaryCard(card)) return false;
  final text = '${card.fact ?? ''}${card.title ?? ''}'.trim();
  return text.isNotEmpty;
}

/// [existing] followed by the ids of [added] that are not in it yet.
List<String> mergeFactIds(Iterable<String> existing, Iterable<String> added) {
  final merged = <String>[...existing];
  for (final id in added) {
    if (id.isNotEmpty && !merged.contains(id)) merged.add(id);
  }
  return merged;
}

/// How many of the latest records a manual analysis hands to the agent.
const manualInsightRecords = 20;

/// Why an analysis ended, kept in the task result so the Insights screen can
/// say what happened when nothing new appeared.
enum InsightOutcome { saved, noPattern, tooFewRecords, noModel, noRecord }

/// The latest analysis as the screen shows it.
class InsightRunStatus {
  const InsightRunStatus({
    this.running = false,
    this.failed = false,
    this.outcome,
    this.detail = '',
    this.at,
  });

  /// An analysis is waiting or running.
  final bool running;

  /// The latest one ended with an error (the queue gave up retrying).
  final bool failed;

  /// Null while the latest one has not finished, or when none ever ran.
  final InsightOutcome? outcome;

  /// The agent's own short reason (only for [InsightOutcome.noPattern]).
  final String detail;
  final DateTime? at;

  /// [status] and [resultJson] are the `status` and `result` of a task row.
  factory InsightRunStatus.fromTask({
    required String status,
    String? resultJson,
    int? completedAt,
  }) {
    final running = status != 'completed' && status != 'failed';
    InsightOutcome? outcome;
    var detail = '';
    if (resultJson != null) {
      try {
        final map = jsonDecode(resultJson) as Map;
        outcome = InsightOutcome.values
            .where((o) => o.name == map['outcome'])
            .firstOrNull;
        detail = '${map['detail'] ?? ''}';
      } on FormatException {
        // An unreadable result only means there is no reason to show.
      }
    }
    return InsightRunStatus(
      running: running,
      failed: status == 'failed',
      outcome: outcome,
      detail: detail,
      at: completedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(completedAt * 1000),
    );
  }
}

/// The agent answers `no_op` and one sentence; the sentence is the reason.
String insightReason(String summary) => summary
    .trim()
    .replaceFirst(
        RegExp(r'^`?no_op`?\s*[-–—:.,]*\s*', caseSensitive: false), '')
    .trim();
