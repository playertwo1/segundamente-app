import 'dart:convert';

import 'package:memex/domain/models/document_chart.dart';
import 'package:memex/domain/models/pdf_pages.dart';

/// Documents the user asks for inside a comment thread (F10-03/04). A version
/// is never changed after it is saved; a revision or a manual edit adds one.

const threadDocumentSchemaVersion = 1;

enum DocumentAuthor { model, user }

class DocumentVersion {
  const DocumentVersion({
    required this.number,
    required this.author,
    required this.content,
    required this.createdAt,
    this.instruction,
    this.sourceCommentIds = const [],
    this.warnings = const [],
  });

  final int number;
  final DocumentAuthor author;

  /// Markdown. Facts cite `[p.N]` (PDF page) or `[c:ID]` (a comment).
  final String content;
  final String createdAt;
  final String? instruction;

  /// The comments the model saw; new messages never enter a finished draft.
  final List<String> sourceCommentIds;

  /// Citations that could not be checked against the sources.
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'number': number,
        'author': author.name,
        'content': content,
        'created_at': createdAt,
        if (instruction != null) 'instruction': instruction,
        'source_comment_ids': sourceCommentIds,
        'warnings': warnings,
      };

  static DocumentVersion fromJson(Map<String, dynamic> json) => DocumentVersion(
        number: json['number'] as int,
        author: DocumentAuthor.values.byName(json['author'] as String),
        content: json['content'] as String,
        createdAt: json['created_at'] as String,
        instruction: json['instruction'] as String?,
        sourceCommentIds: [
          for (final id in json['source_comment_ids'] as List? ?? const [])
            id as String,
        ],
        warnings: [
          for (final w in json['warnings'] as List? ?? const []) w as String,
        ],
      );
}

class ThreadDocument {
  ThreadDocument({
    required this.id,
    required this.requestId,
    required this.cardId,
    required this.title,
    required this.createdAt,
    required List<DocumentVersion> versions,
    this.originDeleted = false,
  }) : versions = List.unmodifiable(versions);

  final String id;

  /// Identifies the user's request, so a retry never creates a second document.
  final String requestId;
  final String cardId;
  final String title;
  final String createdAt;
  final List<DocumentVersion> versions;
  final bool originDeleted;

  DocumentVersion get latest => versions.last;

  DocumentVersion? version(int number) {
    for (final v in versions) {
      if (v.number == number) return v;
    }
    return null;
  }

  ThreadDocument withVersion(DocumentVersion v) => ThreadDocument(
        id: id,
        requestId: requestId,
        cardId: cardId,
        title: title,
        createdAt: createdAt,
        versions: [...versions, v],
        originDeleted: originDeleted,
      );

  ThreadDocument withOriginDeleted() => ThreadDocument(
        id: id,
        requestId: requestId,
        cardId: cardId,
        title: title,
        createdAt: createdAt,
        versions: versions,
        originDeleted: true,
      );

  String toJsonString() => const JsonEncoder.withIndent('  ').convert({
        'schema_version': threadDocumentSchemaVersion,
        'id': id,
        'request_id': requestId,
        'card_id': cardId,
        'title': title,
        'created_at': createdAt,
        'origin_deleted': originDeleted,
        'versions': [for (final v in versions) v.toJson()],
      });

  static ThreadDocument fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('document is not an object');
    }
    if (json['schema_version'] != threadDocumentSchemaVersion) {
      throw FormatException('unknown schema ${json['schema_version']}');
    }
    final raw = json['versions'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('document has no versions');
    }
    final versions = [
      for (final v in raw) DocumentVersion.fromJson(v as Map<String, dynamic>),
    ];
    for (var i = 0; i < versions.length; i++) {
      if (versions[i].number != i + 1) {
        throw const FormatException('version numbers out of order');
      }
    }
    return ThreadDocument(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      cardId: json['card_id'] as String,
      title: json['title'] as String,
      createdAt: json['created_at'] as String,
      originDeleted: json['origin_deleted'] as bool? ?? false,
      versions: versions,
    );
  }
}

/// The edit was made on a version that is no longer the latest.
class StaleDocumentEdit implements Exception {
  const StaleDocumentEdit(this.expected, this.actual);

  final int expected;
  final int actual;

  @override
  String toString() => 'StaleDocumentEdit(expected $expected, latest $actual)';
}

final _citation = RegExp(r'\[(p\.\d+|c:[^\]\s]+)\]');

/// Citations in [markdown] that the sources cannot back: a page the PDF does
/// not have (or no PDF at all) and a comment outside the snapshot.
List<String> unverifiedCitations(
  String markdown, {
  required Set<String> commentIds,
  PdfPages? pages,
}) {
  final pageLabels = {
    if (pages != null)
      for (final s in pages.toSegments()) s.clock,
  };
  final bad = <String>[];
  for (final m in _citation.allMatches(markdown)) {
    final ref = m.group(1)!;
    final ok = ref.startsWith('p.')
        ? pageLabels.contains(ref)
        : commentIds.contains(ref.substring(2));
    if (!ok && !bad.contains(ref)) bad.add(ref);
  }
  return bad;
}

/// Warnings for a manual edit. Photos are checked again against the record;
/// a citation or chart number flagged in [previous] stays flagged while it is
/// still in the text, since the edit has no sources to clear it.
List<String> userEditWarnings(
  String markdown, {
  required List<String> previous,
  required Set<String> recordImages,
}) {
  final charts = findChartBlocks(markdown);
  final chartValues = {
    for (final b in charts)
      if (b.chart != null)
        for (final v in b.chart!.values) formatValue(v),
  };
  final kept = <String>{
    for (final w in previous)
      if (w.startsWith('chart:')
          ? w != 'chart:invalid' && chartValues.contains(w.substring(6))
          : !w.startsWith('image:') && markdown.contains('[$w]'))
        w,
    if (charts.any((b) => b.chart == null)) 'chart:invalid',
    ...unverifiedImages(markdown, recordImages),
  };
  return kept.toList();
}
