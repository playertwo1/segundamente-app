import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/card_pdf_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/data/services/thread_document_service.dart';
import 'package:memex/data/services/thread_document_writer.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/pdf_pages.dart';
import 'package:memex/domain/models/thread_document.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = Logger('ThreadDocumentHandler');

const threadDocumentTaskType = 'thread_document';

/// Drafts (no `doc_id`) or revises (`doc_id` + `expected_latest`) a document.
/// The task is retried after a restart, so both paths are idempotent: a draft
/// is keyed by `request_id`, and a revision that is already the latest
/// version counts as done.
Future<void> handleThreadDocumentImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final cardId = payload['card_id'] as String;
  final requestId = payload['request_id'] as String;
  final instruction = payload['instruction'] as String;
  final snapshot = {
    for (final id in payload['comment_ids'] as List) id as String,
  };
  final docId = payload['doc_id'] as String?;
  final expectedLatest = payload['expected_latest'] as int?;

  try {
    final card = await FileSystemService.instance.readCardFile(userId, cardId);
    if (card == null) {
      _logger.warning('Record $cardId is gone; document request dropped');
      return;
    }
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );

    PdfPages? pages;
    final pdfService = CardPdfService();
    final pdfs = await pdfService.pdfAssets(userId, card);
    if (pdfs.isNotEmpty) {
      try {
        pages = (await pdfService.ensurePages(
          userId: userId,
          asset: pdfs.first,
          modelReadsPdf: modelCarriesPdf(resources.client),
          confirmedLarge: false,
          askPdf: (system, pdf) => askModelForPdfPages(resources, system, pdf),
        ))
            .pages;
      } catch (e) {
        _logger.warning('PDF text unavailable for document on $cardId: $e');
      }
    }

    final sources = DocumentSources(
      cardId: cardId,
      cardText: card.fact ?? card.title ?? '',
      comments: [for (final c in card.comments) if (snapshot.contains(c.id)) c],
      pages: pages,
      imageAssets: await ThreadDocumentService().recordPhotos(userId, card),
      related: await _relatedRecords(
        userId,
        [for (final id in payload['related_ids'] as List? ?? const []) '$id'],
      ),
    );
    Future<String> ask(String system, String user) async {
      final response = await resources.client.generate(
        [
          SystemMessage(system),
          UserMessage([TextPart(user)]),
        ],
        modelConfig: resources.modelConfig,
      );
      return response.textOutput ?? '';
    }

    final writer = ThreadDocumentWriter();
    final language = UserStorage.l10n.commentLanguageInstruction;
    if (docId == null) {
      await writer.create(
        userId: userId,
        requestId: requestId,
        instruction: instruction,
        sources: sources,
        languageInstruction: language,
        ask: ask,
      );
    } else {
      try {
        await writer.revise(
          userId: userId,
          id: docId,
          expectedLatest: expectedLatest!,
          instruction: instruction,
          sources: sources,
          languageInstruction: language,
          ask: ask,
        );
      } on StaleDocumentEdit {
        final doc = await ThreadDocumentService().load(userId, docId);
        final applied = doc != null &&
            doc.latest.number > expectedLatest! &&
            doc.latest.instruction == instruction;
        // Someone edited meanwhile: retrying cannot succeed, so drop it and
        // let the user ask again from the new version.
        if (!applied) {
          _logger.warning('Revision of $docId dropped: the document changed');
        }
      }
    }
    EventBusService.instance.emitEvent(CardDetailUpdatedMessage(cardId: cardId));
  } catch (e, stack) {
    _logger.severe('Thread document task failed: $e', e, stack);
    rethrowIfNonRetryable(e);
  }
}

/// Records the user ticked in the confirmation; at most three, trimmed.
Future<List<RelatedRecord>> _relatedRecords(
  String userId,
  List<String> ids,
) async {
  final related = <RelatedRecord>[];
  for (final id in ids.take(3)) {
    final card = await FileSystemService.instance.readCardFile(userId, id);
    if (card == null) continue;
    final text = (card.fact ?? card.title ?? '').trim();
    related.add(RelatedRecord(
      id: id,
      title: card.title ?? id,
      text: text.length > 2000 ? text.substring(0, 2000) : text,
    ));
  }
  return related;
}
