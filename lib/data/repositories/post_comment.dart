import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/comment_agent/comment_agent.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/data/services/card_pdf_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/character_execution_coordinator.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/time_context.dart';

final _logger = Logger('PostCommentEndpoint');
FileSystemService get _fileSystemService => FileSystemService.instance;

/// Post comment (AI reply handled async)
///
/// Args:
///   cardId: card ID (fact_id)
///   userId: user ID
///   content: comment content
///   replyToId: optional, ID of the comment being replied to
///
/// Returns:
///   Map with user comment info (AI reply is async)
Future<Map<String, dynamic>> postCommentEndpoint(
  String cardId,
  String userId,
  String content, {
  String? replyToId,
}) async {
  _logger.info(
    'PostCommentEndpoint: postComment called: cardId=$cardId, userId=$userId',
  );

  try {
    // Read card file
    final cardData = await _fileSystemService.readCardFile(userId, cardId);
    if (cardData == null) {
      throw Exception('Card not found: $cardId');
    }

    // Save user comment to card (persist immediately)
    final commentId = const Uuid().v4();
    final commentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _fileSystemService.updateCardFile(userId, cardId, (card) {
      final newComment = CardComment(
        id: commentId,
        content: content,
        isAi: false,
        timestamp: commentTimestamp,
        replyToId: replyToId,
      );
      return card.copyWith(comments: [...card.comments, newComment]);
    });

    _logger.info('User comment saved for card $cardId, comment_id: $commentId');

    // Log event
    try {
      final cardPath = _fileSystemService.getCardPath(userId, cardId);
      final workspacePath = _fileSystemService.getWorkspacePath(userId);
      final relativePath = _fileSystemService.toRelativePath(
        cardPath,
        rootPath: workspacePath,
      );
      await _fileSystemService.eventLogService.logFileModified(
        userId: userId,
        filePath: relativePath,
        description: 'User posted comment to card',
        metadata: {
          'card_id': cardId,
          'comment_id': commentId,
          'content': content,
        },
      );
    } catch (e) {
      // Event logging failure should not break comment posting
    }

    String? locationContextReminder;
    try {
      final locationContext =
          await LocationContextService.instance.getCurrentContext();
      locationContextReminder = locationContext.toAgentSystemReminderContent();
    } catch (e) {
      _logger.warning('Failed to decorate comment with location context: $e');
    }

    // Publish domain event and let event subscribers enqueue persistent tasks.
    await GlobalEventBus.instance.publish(
      userId: userId,
      event: SystemEvent(
        type: SystemEventTypes.cardCommentPosted,
        source: 'post_comment.postCommentEndpoint',
        payload: CardCommentPostedPayload(
          cardId: cardId,
          content: content,
          commentId: commentId,
          createdAtTs: commentTimestamp,
          replyToId: replyToId,
          locationContextReminder: locationContextReminder,
        ),
      ),
    );

    // Return user comment info immediately
    return {
      'comment_id': commentId,
      'status': 'pending',
      'message': 'Comment submitted, AI is replying...',
    };
  } catch (e) {
    _logger.severe('Failed to post comment for card $cardId: $e');
    rethrow;
  }
}

/// Process AI comment reply (async task)
///
/// Args:
///   cardId: card ID (fact_id)
///   userId: user ID
///   userContent: user comment or prompt
///   userCommentId: optional, for reply scenario
///   characterId: optional, from existing comment if not provided
///   rawInputContent: optional, read from file if not provided
///   sendEventBus: whether to send event bus update (default true)
Future<void> processAICommentReply({
  required String cardId,
  required String userId,
  required String userContent,
  String? userCommentId,
  String? characterId,
  String? rawInputContent,
  String? locationContextReminder,
  bool sendEventBus = true,
  DateTime? inputDateTime,
  bool withMemoryManagement = false,
  bool forceReply = false,
  bool readAttachedPdfs = false,
}) async {
  _logger.info(
    'PostCommentEndpoint: processAICommentReply called: cardId=$cardId, userId=$userId',
  );

  try {
    // 1. Read card file
    final cardData = await _fileSystemService.readCardFile(userId, cardId);
    if (cardData == null) {
      _logger.warning('Card not found for AI reply: $cardId');
      return;
    }

    final initialInsight = cardData.insight?.text;

    // Location for the comment: prefer the caller-supplied device location
    // (e.g. a live user reply). When absent (e.g. a new card created through
    // SuperAgent re-publishes userInputSubmitted without device location),
    // fall back to the card's own place — where the recorded moment happened.
    // Card display priority: user-marked address first, then address.
    var effectiveLocationReminder = locationContextReminder?.trim();
    if (effectiveLocationReminder == null ||
        effectiveLocationReminder.isEmpty) {
      final cardPlace = (cardData.userFixedAddress?.trim().isNotEmpty ?? false)
          ? cardData.userFixedAddress!.trim()
          : (cardData.address?.trim().isNotEmpty ?? false)
              ? cardData.address!.trim()
              : null;
      if (cardPlace != null) {
        effectiveLocationReminder = 'Recorded location: $cardPlace';
      }
    }

    // 2. Character ID Fallback
    // When no explicit characterId: pick the most recent AI commenter
    // (the character most recently active in the conversation).
    // Falls back to the insight character if no AI comments exist.
    if (characterId == null) {
      for (final c in cardData.comments.reversed) {
        if (c.isAi && c.characterId != null) {
          characterId = c.characterId;
          _logger.info('Using most recent AI commenter $characterId');
          break;
        }
      }
      if (characterId == null && cardData.insight != null) {
        characterId = cardData.insight!.characterId;
        if (characterId != null) {
          _logger.info('Using character_id $characterId from insight data');
        }
      }
    }

    // 3. Raw Input Content
    // The card's own `fact` field is the source-of-truth original input
    // (including any image/audio content the user captured); use it when the
    // caller did not pass rawInputContent explicitly.
    String contentToUse = rawInputContent ?? '';
    if (contentToUse.isEmpty) {
      contentToUse = cardData.fact ?? '';
    }

    // Entry time comes from the card's own timestamp (content/creation time).
    final entryDateTime = cardData.timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(cardData.timestamp * 1000)
        : null;

    // 4. PKM Context
    // CommentAgent.run handles searching PKM context if not passed.

    // 5. Initialize Agent
    // 5. Initialize Agent (Default to Responses for Comments)
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.commentAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    final client = resources.client;
    final modelConfig = resources.modelConfig;

    // 6. Build existing comments context for multi-character interaction
    String existingCommentsContext = '';
    if (cardData.comments.isNotEmpty) {
      final buf = StringBuffer();
      buf.writeln('\n<existing_comments>');
      for (final c in cardData.comments) {
        final author = c.isAi
            ? (c.characterId ?? UserStorage.l10n.commentAuthorAi)
            : UserStorage.l10n.commentAuthorUser;
        final replyInfo =
            c.replyToId != null ? ' (replying to ${c.replyToId})' : '';
        final commentTime = formatLocalDateTimeWithZone(
          DateTime.fromMillisecondsSinceEpoch(c.timestamp * 1000),
        );
        buf.writeln(
          '- [$author] (id: ${c.id}, time: $commentTime)$replyInfo: ${c.content}',
        );
      }
      buf.writeln('</existing_comments>');
      existingCommentsContext = buf.toString();
    }

    if (readAttachedPdfs) {
      existingCommentsContext +=
          await _attachedPdfContext(userId, cardData, resources);
    }

    // 7. Run the comment agent. Failures must propagate so LocalTaskExecutor
    // retries process_ai_reply / comment_agent_task instead of marking success.
    Future<void> runComment() async {
      await CommentAgent.runWithContent(
        userContent,
        client: client,
        modelConfig: modelConfig,
        userId: userId,
        factId: cardId,
        rawInputContent: contentToUse,
        initialInsight: initialInsight,
        existingCommentsContext: existingCommentsContext,
        characterId: characterId,
        forcedReplyToId: userCommentId,
        currentTime: inputDateTime ?? DateTime.now(),
        entryTime: entryDateTime,
        locationContextReminder: effectiveLocationReminder,
        withMemoryManagement: withMemoryManagement,
        forceReply: forceReply,
      );
    }

    if (characterId == null) {
      await runComment();
    } else {
      await CharacterExecutionCoordinator.instance.run(
        userId: userId,
        characterId: characterId,
        action: runComment,
      );
    }

    // 8. EventBus Update
    if (sendEventBus) {
      EventBusService.instance.emitEvent(
        CardDetailUpdatedMessage(cardId: cardId),
      );
    }
  } catch (e) {
    _logger.severe('Failed to process AI comment reply for card $cardId: $e');
    rethrowIfNonRetryable(e);
  }
}

/// Page text of the record's PDFs for the agent (F10-02): cached after the
/// first model call, a stated limit when the model cannot read the file.
Future<String> _attachedPdfContext(
  String userId,
  CardData card,
  ({LLMClient client, ModelConfig modelConfig}) resources,
) async {
  final service = CardPdfService();
  final results = <CardPdfResult>[];
  for (final asset in await service.pdfAssets(userId, card)) {
    try {
      results.add(
        await service.ensurePages(
          userId: userId,
          asset: asset,
          modelReadsPdf: modelCarriesPdf(resources.client),
          confirmedLarge: false,
          askPdf: (system, pdf) => askModelForPdfPages(resources, system, pdf),
        ),
      );
    } catch (e) {
      _logger.warning('PDF pages unavailable for $asset: $e');
      results.add(CardPdfResult(asset, CardPdfStatus.failed));
    }
  }
  return pdfContextBlock(results);
}
