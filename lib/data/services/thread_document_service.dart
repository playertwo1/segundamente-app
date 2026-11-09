import 'dart:convert';
import 'dart:io';

import 'package:memex/data/services/asset_reference_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/document_chart_renderer.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/session_report_export_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:memex/domain/models/thread_document.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;

/// Stores F10 documents as `<id>/document.json`. Writes go to a temporary file
/// and are renamed, a version is only ever appended, and edits on the same
/// document run one at a time so a stale edit is detected, not overwritten.
class ThreadDocumentService {
  ThreadDocumentService({
    FileSystemService? files,
    Future<ReportExportFonts> Function()? loadFonts,
  })  : _files = files ?? FileSystemService.instance,
        _loadFonts = loadFonts ?? loadReportExportFonts;

  final FileSystemService _files;
  final Future<ReportExportFonts> Function() _loadFonts;
  final _logger = getLogger('ThreadDocumentService');
  static final _locks = <String, Future<void>>{};

  Directory _dir(String userId, String id) {
    if (id.isEmpty ||
        id.contains('/') ||
        id.contains('\\') ||
        id.startsWith('.')) {
      throw ArgumentError.value(id, 'id', 'invalid document id');
    }
    return Directory(p.join(_files.getThreadDocumentsPath(userId), id));
  }

  Future<T> _exclusive<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key] ?? Future<void>.value();
    final done = previous.then((_) => action());
    _locks[key] = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<ThreadDocument?> load(String userId, String id) async {
    final file = File(p.join(_dir(userId, id).path, 'document.json'));
    if (!await file.exists()) return null;
    try {
      return ThreadDocument.fromJson(jsonDecode(await file.readAsString()));
    } on FormatException catch (e, st) {
      _logger.severe('Unreadable document $id', e, st);
      final bad = File(
        '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
      );
      await file.rename(bad.path);
      return null;
    }
  }

  Future<List<ThreadDocument>> listAll(String userId) async {
    final root = Directory(_files.getThreadDocumentsPath(userId));
    if (!await root.exists()) return const [];
    final docs = <ThreadDocument>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final doc = await load(userId, p.basename(entity.path));
      if (doc != null) docs.add(doc);
    }
    docs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return docs;
  }

  Future<List<ThreadDocument>> listForCard(
    String userId,
    String cardId,
  ) async =>
      [
        for (final d in await listAll(userId))
          if (d.cardId == cardId) d
      ];

  /// Creates the first version. A repeated [requestId] (a retry after a
  /// restart) returns the document already made instead of a second one.
  Future<ThreadDocument> create({
    required String userId,
    required String requestId,
    required String cardId,
    required String title,
    required String content,
    required DateTime now,
    String? instruction,
    List<String> sourceCommentIds = const [],
    List<String> warnings = const [],
  }) {
    return _exclusive('$userId/create', () async {
      for (final d in await listAll(userId)) {
        if (d.requestId == requestId) return d;
      }
      final doc = ThreadDocument(
        id: 'doc_${now.microsecondsSinceEpoch}',
        requestId: requestId,
        cardId: cardId,
        title: title,
        createdAt: now.toIso8601String(),
        versions: [
          DocumentVersion(
            number: 1,
            author: DocumentAuthor.model,
            content: content,
            createdAt: now.toIso8601String(),
            instruction: instruction,
            sourceCommentIds: sourceCommentIds,
            warnings: warnings,
          ),
        ],
      );
      await _write(userId, doc);
      return doc;
    });
  }

  /// Appends a version made from [expectedLatest]. If another edit got there
  /// first, nothing is written and [StaleDocumentEdit] is thrown.
  Future<ThreadDocument> addVersion({
    required String userId,
    required String id,
    required int expectedLatest,
    required DocumentAuthor author,
    required String content,
    required DateTime now,
    String? instruction,
    List<String> sourceCommentIds = const [],
    List<String> warnings = const [],
  }) {
    return _exclusive('$userId/$id', () async {
      final doc = await load(userId, id);
      if (doc == null) throw StateError('document missing');
      if (doc.latest.number != expectedLatest) {
        throw StaleDocumentEdit(expectedLatest, doc.latest.number);
      }
      final next = doc.withVersion(
        DocumentVersion(
          number: expectedLatest + 1,
          author: author,
          content: content,
          createdAt: now.toIso8601String(),
          instruction: instruction,
          sourceCommentIds: sourceCommentIds,
          warnings: warnings,
        ),
      );
      await _write(userId, next);
      return next;
    });
  }

  /// The record was deleted but the user kept the documents.
  Future<void> markOriginDeleted(String userId, String cardId) async {
    for (final doc in await listForCard(userId, cardId)) {
      await _exclusive('$userId/${doc.id}', () async {
        final fresh = await load(userId, doc.id);
        if (fresh != null) await _write(userId, fresh.withOriginDeleted());
      });
    }
  }

  /// The record is being deleted: keep its documents (marked as orphaned) or
  /// delete them with it.
  Future<void> resolveOrigin(
    String userId,
    String cardId, {
    required bool keep,
  }) async {
    if (keep) return markOriginDeleted(userId, cardId);
    for (final doc in await listForCard(userId, cardId)) {
      await delete(userId, doc.id);
    }
  }

  Future<void> delete(String userId, String id) =>
      _exclusive('$userId/$id', () async {
        final dir = _dir(userId, id);
        if (await dir.exists()) await dir.delete(recursive: true);
      });

  /// The document text with its charts and record photos drawn in.
  ///
  /// With [cardId], a `[c:ID]` citation reads as who said it instead of the
  /// raw comment id; the stored version keeps the id.
  Future<String> render(
    String userId,
    String markdown, {
    String? cardId,
  }) async =>
      expandDocument(
        await _nameCitations(userId, cardId, markdown),
        readImage: (asset) async {
          if (!await _files.isUserImageAsset(
              userId: userId, relativePath: asset)) {
            return null;
          }
          return _files.readUserImageAssetBytes(
              userId: userId, relativePath: asset);
        },
      );

  /// Photos of the record a document may place, as paths inside the user's
  /// assets. A card holds `![image](fs://name.jpg)` markers; a plain relative
  /// path is accepted too.
  Future<List<String>> recordPhotos(String userId, CardData card) async {
    const photoExtensions = {'.jpg', '.jpeg', '.png'};
    final found = <String>[];
    for (final entry in card.assets) {
      final ref = await AssetReferenceService.resolveExisting(
        userId: userId,
        reference: entry,
      );
      final path = ref != null && ref.type == AssetReferenceType.image
          ? _files.toRelativePath(ref.absolutePath)
          : entry;
      if (photoExtensions.contains(p.extension(path).toLowerCase()) &&
          await _files.isUserImageAsset(userId: userId, relativePath: path)) {
        found.add(path);
      }
    }
    return found;
  }

  /// An id the record does not hold stays as written, so a citation the
  /// sources cannot back is still visible as one.
  Future<String> _nameCitations(
    String userId,
    String? cardId,
    String markdown,
  ) async {
    if (cardId == null || !markdown.contains('[c:')) return markdown;
    CardData? card;
    try {
      card = await _files.readCardFile(userId, cardId);
    } catch (_) {} // a record that cannot be read leaves the ids as written
    if (card == null) return markdown;
    var names = <String, String>{};
    try {
      names = {
        for (final c
            in await CharacterService.instance.getAllCharacters(userId))
          c.id: c.name,
      };
    } catch (_) {} // no character list: the id of the persona is shown
    final byId = {for (final c in card.comments) c.id: c};
    return markdown.replaceAllMapped(RegExp(r'\[c:([^\]]+)\]'), (m) {
      final c = byId[m[1]!.trim()];
      if (c == null) return m[0]!;
      if (!c.isAi) return '[${UserStorage.l10n.documentCitationYou}]';
      final who = names[c.characterId] ?? c.characterId ?? 'IA';
      return '[${UserStorage.l10n.documentCitationFrom(who)}]';
    });
  }

  ExportMeta _exportMeta(String createdAt, int version, {bool draft = false}) {
    final pt = UserStorage.localeNotifier.value.languageCode == 'pt';
    final at = DateTime.tryParse(createdAt)?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return ExportMeta(
      kindLabel: pt ? 'Documento' : 'Document',
      date: at == null
          ? null
          : pt
              ? '${two(at.day)}/${two(at.month)}/${at.year}'
              : '${at.year}-${two(at.month)}-${two(at.day)}',
      version: pt ? 'versão $version' : 'version $version',
      draftLabel: draft ? (pt ? 'Rascunho' : 'Draft') : null,
    );
  }

  /// Writes one version in Markdown, PDF or DOCX. The same text goes to every
  /// format, and an older version can be exported as long as it is named.
  Future<File> export({
    required String userId,
    required String id,
    required int version,
    required ReportExportFormat format,
    bool draft = false,
  }) async {
    final doc = await load(userId, id);
    final v = doc?.version(version);
    if (doc == null || v == null) throw StateError('version missing');
    final bytes = await exportMarkdownBytes(
      markdown: await render(userId, v.content, cardId: doc.cardId),
      format: format,
      fonts: format == ReportExportFormat.pdf ? await _loadFonts() : null,
      languageCode: UserStorage.localeNotifier.value.languageCode,
      meta: _exportMeta(v.createdAt, version, draft: draft),
    );
    final ext = const {
      ReportExportFormat.markdown: 'md',
      ReportExportFormat.pdf: 'pdf',
      ReportExportFormat.docx: 'docx',
    }[format]!;
    // Named after the document so the copy a user finds in Downloads says what it is.
    var name = doc.title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    if (name.length > 60) name = name.substring(0, 60);
    if (name.isEmpty) name = 'documento';
    final file = File(
      p.join(_dir(userId, id).path, 'exports', '$name-v$version.$ext'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _write(String userId, ThreadDocument doc) async {
    final dir = _dir(userId, doc.id);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'document.json'));
    final temp =
        File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temp.writeAsString(doc.toJsonString(), flush: true);
    await temp.rename(file.path);
  }
}
