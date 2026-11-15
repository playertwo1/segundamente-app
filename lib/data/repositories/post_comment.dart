import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/comment_agent/comment_agent.dart';
import 'package:memex/agent/skills/comment_agent/tools/comment_tools.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/data/services/card_pdf_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/character_workspace_service.dart';
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

/// Formats the full group discussion thread showing comment IDs, author
/// names + `@id` handles, and parent reply targets.
String formatGroupCommentsContext(
  List<CardComment> comments,
  Map<String, String> characterNamesById, {
  String? userLabel,
  String? fallbackAiLabel,
}) {
  if (comments.isEmpty) return '';
  final resolvedUserLabel = userLabel ?? 'Usuário';
  final resolvedAiFallback = fallbackAiLabel ?? 'AI';
  final byId = {for (final c in comments) c.id: c};

  final buf = StringBuffer();
  buf.writeln('\n<existing_comments>');
  for (final c in comments) {
    final charId = c.characterId;
    final author = c.isAi
        ? '${charId != null ? (characterNamesById[charId] ?? charId) : resolvedAiFallback} (@${charId ?? 'ai'})'
        : '$resolvedUserLabel (@user)';
    final parent = c.replyToId != null ? byId[c.replyToId!] : null;
    final parentAuthor = parent == null
        ? null
        : (parent.isAi
            ? (parent.characterId != null
                ? (characterNamesById[parent.characterId!] ??
                    parent.characterId!)
                : resolvedAiFallback)
            : resolvedUserLabel);
    final replyInfo = parent != null
        ? ' (em resposta a [${parent.id}] $parentAuthor)'
        : (c.replyToId != null ? ' (replying to ${c.replyToId})' : '');
    final commentTime = formatLocalDateTimeWithZone(
      DateTime.fromMillisecondsSinceEpoch(c.timestamp * 1000),
    );
    buf.writeln(
      '- [${c.id}] $author$replyInfo ($commentTime): ${c.content}',
    );
  }
  buf.writeln('</existing_comments>');
  return buf.toString();
}

/// Process AI comment reply (async task).
///
/// Returns the newly created [CardComment] if a visible comment was saved, or
/// `null` if the character skipped commenting.
Future<CardComment?> processAICommentReply({
  required String cardId,
  required String userId,
  required String userContent,
  String? userCommentId,
  String? fallbackReplyToId,
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
      return null;
    }

    final initialCount = cardData.comments.length;
    final initialInsight = cardData.insight?.text;

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
    String contentToUse = rawInputContent ?? '';
    if (contentToUse.isEmpty) {
      contentToUse = cardData.fact ?? '';
    }

    final entryDateTime = cardData.timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(cardData.timestamp * 1000)
        : null;

    // 4-5. Initialize Agent
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.commentAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    final client = resources.client;
    final modelConfig = resources.modelConfig;

    // 6. Build existing comments context for live group-chat interaction
    final allCharacters = await CharacterService.instance.getAllCharacters(userId);
    final characterNamesById = {
      for (final c in allCharacters) c.id: c.name,
    };
    String existingCommentsContext = formatGroupCommentsContext(
      cardData.comments,
      characterNamesById,
      userLabel: UserStorage.l10n.commentAuthorUser,
      fallbackAiLabel: UserStorage.l10n.commentAuthorAi,
    );

    if (readAttachedPdfs) {
      existingCommentsContext +=
          await _attachedPdfContext(userId, cardData, resources);
    }

    // 7. Run the comment agent. Failures must propagate so LocalTaskExecutor
    // retries process_ai_reply / comment_agent_task instead of marking success.
    var textOutput = '';
    Future<void> runComment() async {
      textOutput = await CommentAgent.runWithContent(
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
        fallbackReplyToId: fallbackReplyToId,
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

    // Check if tool saved a comment; if model answered in plain text without
    // calling SaveComment when forced (or emitted [REPLY:]/[MEMORY:]), persist
    // cleanly while stripping tags.
    var latestCard = await _fileSystemService.readCardFile(userId, cardId);
    CardComment? createdComment;
    if (latestCard != null && latestCard.comments.length > initialCount) {
      createdComment = latestCard.comments.last;
    } else if (textOutput.trim().isNotEmpty) {
      final parsed = parseGroupCommentOutput(textOutput);
      final upper = parsed.content.toUpperCase();
      final isSkipText =
          !forceReply && (upper == '[SKIP]' || upper == 'SKIP' || upper.contains('[SKIP]'));
      if (!isSkipText &&
          parsed.content.isNotEmpty &&
          (forceReply ||
              parsed.replyToId != null ||
              parsed.memoryNotes.isNotEmpty)) {
        if (parsed.memoryNotes.isNotEmpty &&
            characterId != null &&
            characterId.isNotEmpty) {
          for (final note in parsed.memoryNotes) {
            try {
              await CharacterWorkspaceService.instance.appendLivingMemory(
                userId,
                characterId,
                note,
              );
            } catch (e) {
              _logger.warning('Failed to append fallback memory: $e');
            }
          }
        }
        final activeChars = allCharacters.where((c) => c.enabled).toList();
        final newCommentId = const Uuid().v4();
        final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final updated = await _fileSystemService.updateCardFile(
          userId,
          cardId,
          (card) {
            final replyTo = CommentToolFactory.resolveEffectiveReplyToId(
              card: card,
              characterId: characterId,
              cleanContent: parsed.content,
              fixedReplyTarget: userCommentId?.trim().isNotEmpty == true
                  ? userCommentId!.trim()
                  : null,
              tagReplyToId: parsed.replyToId,
              fallbackReplyTarget: fallbackReplyToId?.trim().isNotEmpty == true
                  ? fallbackReplyToId!.trim()
                  : null,
              activeCharacters: activeChars,
            );
            final entry = CardComment(
              id: newCommentId,
              content: parsed.content,
              isAi: true,
              timestamp: nowTs,
              characterId: characterId,
              replyToId: replyTo,
            );
            createdComment = entry;
            return card.copyWith(comments: [...card.comments, entry]);
          },
        );
        latestCard = updated;
      }
    }

    // 8. EventBus Update
    if (sendEventBus) {
      EventBusService.instance.emitEvent(
        CardDetailUpdatedMessage(cardId: cardId),
      );
    }

    return createdComment;
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
