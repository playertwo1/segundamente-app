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

/// Different records an automatic insight must cite.
const minRecordsForInsightEvidence = 2;

/// A fresh look at the latest records when none ran for this long and new
/// records arrived since.
const insightPeriodicInterval = Duration(days: 7);

/// A tag and the tags above it: `area/obra` -> `area/obra`, `area`.
Set<String> _tagWithParents(String tag) {
  final parts = tag.split('/');
  return {
    for (var i = 1; i <= parts.length; i++) parts.take(i).join('/'),
  };
}

/// False only when the new records are tagged and none of their tags (or a
/// parent tag) sits on a second saved record: nothing could be compared, so
/// the model is not called. Untagged records are left to the model.
/// [savedTags] holds the tag list of every saved record, new ones included.
bool tagsCanLinkRecords(
  Iterable<List<String>> newTags,
  Iterable<List<String>> savedTags,
) {
  final wanted = {for (final t in newTags.expand((l) => l)) ..._tagWithParents(t)};
  if (wanted.isEmpty) return true;
  final counts = <String, int>{};
  for (final list in savedTags) {
    for (final t in {for (final t in list) ..._tagWithParents(t)}) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  return wanted.any((t) => (counts[t] ?? 0) >= 2);
}

Set<String> _terms(String text) => RegExp(r'[a-zà-ÿ]{5,}')
    .allMatches(text.toLowerCase())
    .map((m) => m[0]!)
    .toSet();

/// True when some record in [otherTexts] shares at least two words (five
/// letters or more) with the new records. Cheap second chance for records
/// about the same subject that carry different tags.
bool textsShareTerms(Iterable<String> newTexts, Iterable<String> otherTexts) {
  final wanted = newTexts.expand(_terms).toSet();
  if (wanted.isEmpty) return false;
  return otherTexts.any((o) => _terms(o).intersection(wanted).length >= 2);
}

String _norm(String s) => s.trim().toLowerCase();

/// Share of the smaller list that the two lists have in common (0 to 1).
double evidenceOverlap(Iterable<String> a, Iterable<String> b) {
  final x = a.toSet(), y = b.toSet();
  if (x.isEmpty || y.isEmpty) return 0;
  return x.intersection(y).length / (x.length < y.length ? x.length : y.length);
}

/// An automatic insight resting on this share of another one's records (or
/// more) repeats it.
const duplicateEvidenceShare = 0.8;

/// The rejected entry (`{id, title}`) that [id] or [title] brings back, or null.
Map<String, String>? rejectedMatch(
  Iterable<Map<String, String>> rejected,
  String id,
  String title,
) {
  for (final r in rejected) {
    if (_norm(r['id'] ?? '') == _norm(id) && id.trim().isNotEmpty) return r;
    if ((r['title'] ?? '').trim().isNotEmpty &&
        _norm(r['title']!) == _norm(title)) {
      return r;
    }
  }
  return null;
}

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
