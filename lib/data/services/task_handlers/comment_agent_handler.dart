import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/repositories/post_comment.dart';
import 'package:memex/data/services/character_selection_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/comment_settings_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/utils/mention_parser.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/time_context.dart';

final _logger = Logger('CommentAgentHandler');

Future<void> handleCommentAgentImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final factId = payload['fact_id'] as String;
  final combinedText = payload['combined_text'] as String;
  final inputDateTime = tryParseUnixSeconds(payload['created_at_ts']);
  final locationContextReminder =
      payload['location_context_reminder'] as String?;

  _logger.info(
    "Running Comment Agent selection for fact $factId, user $userId",
  );

  try {
    // Load per-user comment settings
    final settings = await CommentSettingsService.load(userId);

    // If character_id is explicitly provided in payload, use it (single
    // character). Also support lightweight @mentions in the input text.
    String? selectedCharId = payload['character_id'] as String?;
    selectedCharId ??= await _resolveMentionedCharacterId(
      userId: userId,
      content: combinedText,
    );
    final forceReply = selectedCharId != null;

    // Check if character comments are enabled. Directly mentioned characters
    // still answer because the user explicitly routed the turn to them.
    if (!forceReply && !settings.enableCharacterComment) {
      _logger.info(
        'Character comments disabled — skipping comment agent for $factId',
      );
      return;
    }

    // Skip if LLM is not configured.
    final llmConfig = await UserStorage.getAgentLLMConfig(
      AgentDefinitions.commentAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    if (!llmConfig.isValid) {
      _logger.info('No LLM configured — skipping comment agent for $factId');
      return;
    }

    if (selectedCharId != null) {
      // Explicit character — single comment
      _logger.info("Using explicitly routed character $selectedCharId");
      await processAICommentReply(
        cardId: factId,
        userId: userId,
        userContent: Prompts.commentAgentInitialCommentPrompt,
        characterId: selectedCharId,
        rawInputContent: combinedText,
        inputDateTime: inputDateTime,
        locationContextReminder: locationContextReminder,
        forceReply: forceReply,
      );
      return;
    }

    final maxChars = settings.maxCommentCharacters;

    if (maxChars <= 1) {
      // Single-character mode: keyword-based selection (no LLM call)
      final selectedChar = await CharacterSelectionService.selectCharacter(
        userId: userId,
        inputContent: combinedText,
        factId: factId,
      );

      if (selectedChar == null) {
        _logger.info("No clear character match, skipping comment agent");
        return;
      }

      _logger.info(
        "Selected character ${selectedChar.name} (${selectedChar.id}) for comment",
      );
      await processAICommentReply(
        cardId: factId,
        userId: userId,
        userContent: Prompts.commentAgentInitialCommentPrompt,
        characterId: selectedChar.id,
        rawInputContent: combinedText,
        inputDateTime: inputDateTime,
        locationContextReminder: locationContextReminder,
        forceReply: false,
      );
    } else {
      // Multi-character mode: LLM-based selection
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.commentAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );

      final selectedChars =
          await CharacterSelectionService.selectMultipleCharacters(
        userId: userId,
        inputContent: combinedText,
        factId: factId,
        client: resources.client,
        modelConfig: resources.modelConfig,
        maxCharacters: maxChars,
      );

      if (selectedChars.isEmpty) {
        _logger.info("No character selected, skipping comment agent");
        return;
      }

      // Process characters sequentially so later characters can see earlier comments
      for (final char in selectedChars) {
        _logger.info(
          "Processing comment from character ${char.name} (${char.id})",
        );
        await processAICommentReply(
          cardId: factId,
          userId: userId,
          userContent: Prompts.commentAgentInitialCommentPrompt,
          characterId: char.id,
          rawInputContent: combinedText,
          inputDateTime: inputDateTime,
          locationContextReminder: locationContextReminder,
          forceReply: false,
        );
      }
    }
  } catch (e, stack) {
    _logger.severe("CommentAgentHandler failed: $e", e, stack);
    rethrowIfNonRetryable(e);
  }
}

/// Handler for process_ai_reply task
Future<void> handleProcessAiReplyImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final cardId = payload['card_id'] as String;
  final content = payload['content'] as String;
  final commentId = payload['comment_id'] as String?;
  final replyToId = payload['reply_to_id'] as String?;
  final inputDateTime = tryParseUnixSeconds(payload['created_at_ts']);
  final locationContextReminder =
      payload['location_context_reminder'] as String?;

  _logger.info(
    'HandleProcessAiReply: Processing AI reply for card $cardId, user $userId',
  );

  // If the user replied to a specific comment, resolve the target character
  String? targetCharacterId;
  if (replyToId != null) {
    try {
      final cardData = await FileSystemService.instance.readCardFile(
        userId,
        cardId,
      );
      if (cardData != null) {
        targetCharacterId = resolveReplyTargetCharacterId(
          cardData.comments,
          replyToId,
        );
        if (targetCharacterId != null) {
          _logger.info(
            'User replied to comment $replyToId, routing to character $targetCharacterId',
          );
        }
      }
    } catch (e) {
      _logger.warning('Failed to resolve reply target character: $e');
    }
  }
  var routedByMention = false;
  if (targetCharacterId == null) {
    targetCharacterId = await _resolveMentionedCharacterId(
      userId: userId,
      content: content,
    );
    routedByMention = targetCharacterId != null;
  }

  await processAICommentReply(
    cardId: cardId,
    userId: userId,
    userContent: content,
    userCommentId: commentId,
    characterId: targetCharacterId,
    inputDateTime: inputDateTime,
    locationContextReminder: locationContextReminder,
    withMemoryManagement: true,
    forceReply: targetCharacterId != null,
    readAttachedPdfs: true,
  );

  // An @mention calls exactly one persona; otherwise others may join in (F10-01).
  if (!routedByMention) {
    await _debateAfterReply(userId: userId, cardId: cardId);
  }
}

/// Best-effort: the user's reply is already answered, so a failure here must
/// not make the task retry and answer it twice.
Future<void> _debateAfterReply({
  required String userId,
  required String cardId,
}) async {
  try {
    final settings = await CommentSettingsService.load(userId);
    if (!settings.enableCharacterComment ||
        settings.maxCommentCharacters <= 1) {
      return;
    }
    final turns = await runPersonaDebate(
      loadComments: () async =>
          (await FileSystemService.instance.readCardFile(userId, cardId))
              ?.comments ??
          const [],
      loadCharacters: () => CharacterService.instance.getAllCharacters(userId),
      speak: (next, replyToId) => processAICommentReply(
        cardId: cardId,
        userId: userId,
        userContent: Prompts.personaDebatePrompt(replyToId),
        characterId: next.id,
        withMemoryManagement: true,
        readAttachedPdfs: true,
      ),
    );
    _logger.info('Persona debate on $cardId added $turns turn(s)');
  } catch (e, stack) {
    _logger.warning('Persona debate failed for $cardId: $e', e, stack);
  }
}

Future<String?> _resolveMentionedCharacterId({
  required String userId,
  required String content,
}) async {
  if (!content.contains('@')) return null;

  try {
    final characters = await CharacterService.instance.getAllCharacters(userId);
    final candidates = <({String id, String token, int index})>[];

    for (final character in characters) {
      for (final token in {character.id, character.name}) {
        final trimmed = token.trim();
        if (trimmed.isEmpty) continue;
        final mention = '@$trimmed';
        final index = indexOfStandaloneMention(content, mention);
        if (index >= 0) {
          candidates.add((id: character.id, token: mention, index: index));
        }
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final indexCompare = a.index.compareTo(b.index);
      if (indexCompare != 0) return indexCompare;
      return b.token.length.compareTo(a.token.length);
    });
    final selected = candidates.first;
    _logger.info(
      'Resolved character mention ${selected.token} to ${selected.id}',
    );
    return selected.id;
  } catch (e) {
    _logger.warning('Failed to resolve character mention: $e');
    return null;
  }
}

/// Walks `reply_to_id` until it finds an AI comment with a character.
/// Direct replies to an AI comment still resolve in one hop; a reply to a
/// user comment in that thread walks up to the character that owns it.
@visibleForTesting
String? resolveReplyTargetCharacterId(
  List<CardComment> comments,
  String replyToId,
) {
  final byId = {for (final comment in comments) comment.id: comment};
  CardComment? current = byId[replyToId];
  final seen = <String>{};
  while (current != null && seen.add(current.id)) {
    if (current.isAi && current.characterId != null) {
      return current.characterId;
    }
    final nextId = current.replyToId;
    if (nextId == null || nextId.isEmpty) {
      break;
    }
    current = byId[nextId];
  }
  return null;
}

/// Most persona turns allowed after one user message, replies included (D-037).
const maxPersonaTurnsPerUserMessage = 4;

/// How many more persona turns may follow the latest comment (F10-01).
///
/// Personas only talk to each other after the user has answered: a thread
/// without a user comment (the initial persona comment) allows none. Every AI
/// comment after the user's last message counts, the direct reply included.
int remainingPersonaTurns(
  List<CardComment> comments, {
  int max = maxPersonaTurnsPerUserMessage,
}) {
  final lastUser = comments.lastIndexWhere((c) => !c.isAi);
  if (lastUser < 0) return 0;
  final spoken = comments.length - 1 - lastUser;
  return spoken >= max ? 0 : max - spoken;
}

/// Next persona for the debate: most relevant to the latest user message,
/// then the one with the fewest comments in the thread (ties by id).
/// A persona that has not spoken in the thread joins only when it has
/// affinity with the user's message, so unrelated voices don't cost a call.
CharacterModel? pickNextDebater(
  List<CharacterModel> characters,
  List<CardComment> comments,
) {
  final last = comments.isEmpty ? null : comments.last;
  final lastSpeaker = last != null && last.isAi ? last.characterId : null;
  final lastUserIndex = comments.lastIndexWhere((comment) => !comment.isAi);
  final latestUserContent =
      lastUserIndex < 0 ? '' : comments[lastUserIndex].content;
  final spoken = <String, int>{};
  for (final c in comments) {
    final id = c.characterId;
    if (c.isAi && id != null) spoken[id] = (spoken[id] ?? 0) + 1;
  }
  final scored = [
    for (final c in characters)
      if (c.enabled && c.id != lastSpeaker)
        (
          character: c,
          score: CharacterSelectionService.scoreAffinity(c, latestUserContent),
          count: spoken[c.id] ?? 0,
        ),
  ].where((e) => e.count > 0 || e.score > 0).toList()
    ..sort((a, b) {
      final byRelevance = b.score.compareTo(a.score);
      if (byRelevance != 0) return byRelevance;
      final byCount = a.count.compareTo(b.count);
      return byCount != 0 ? byCount : a.character.id.compareTo(b.character.id);
    });
  return scored.isEmpty ? null : scored.first.character;
}

/// How many personas may pass in one debate before it ends (each pass costs a
/// model call).
const maxPersonaSkipsPerDebate = 2;

/// Lets other personas answer each other after the user's reply, at most
/// [remainingPersonaTurns] times. A persona with nothing to add is passed over
/// and another one is tried, up to [maxPersonaSkipsPerDebate] passes. Stops
/// when no other persona is available or the last comment is not from a
/// persona. Returns how many turns were added.
Future<int> runPersonaDebate({
  required Future<List<CardComment>> Function() loadComments,
  required Future<List<CharacterModel>> Function() loadCharacters,
  required Future<void> Function(CharacterModel next, String replyToId) speak,
}) async {
  var turns = 0;
  final passed = <String>{};
  while (true) {
    final comments = await loadComments();
    if (comments.isEmpty || !comments.last.isAi) break;
    if (remainingPersonaTurns(comments) <= 0) break;
    final candidates =
        (await loadCharacters()).where((c) => !passed.contains(c.id)).toList();
    final next = pickNextDebater(candidates, comments);
    if (next == null) break;
    await speak(next, comments.last.id);
    if ((await loadComments()).length <= comments.length) {
      passed.add(next.id);
      if (passed.length >= maxPersonaSkipsPerDebate) break;
      continue;
    }
    turns++;
  }
  return turns;
}
