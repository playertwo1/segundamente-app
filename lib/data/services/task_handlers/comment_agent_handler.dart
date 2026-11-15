import 'package:dart_agent_core/dart_agent_core.dart';
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

    // Explicit single-character override from payload (e.g. direct retry/ask)
    final explicitCharId = payload['character_id'] as String?;
    final allCharacters =
        await CharacterService.instance.getAllCharacters(userId);

    if (explicitCharId != null) {
      final llmConfig = await UserStorage.getAgentLLMConfig(
        AgentDefinitions.commentAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      if (!llmConfig.isValid) {
        _logger.info('No LLM configured — skipping comment agent for $factId');
        return;
      }
      _logger.info("Using explicitly routed character $explicitCharId");
      await processAICommentReply(
        cardId: factId,
        userId: userId,
        userContent: Prompts.commentAgentInitialCommentPrompt,
        characterId: explicitCharId,
        rawInputContent: combinedText,
        inputDateTime: inputDateTime,
        locationContextReminder: locationContextReminder,
        forceReply: true,
      );
      return;
    }

    // Support multiple @mentions in the post text (even if auto comments are off)
    final mentionedChars = resolveMentionedCharacters(combinedText, allCharacters);
    final hasExplicitMention = mentionedChars.isNotEmpty;

    if (!hasExplicitMention && !settings.enableCharacterComment) {
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

    final wave1Queue = <({CharacterModel character, bool forceReply})>[
      for (final char in mentionedChars) (character: char, forceReply: true),
    ];

    final maxChars = settings.maxCommentCharacters;
    ({LLMClient client, ModelConfig modelConfig})? cachedResources;
    Future<({LLMClient client, ModelConfig modelConfig})> ensureResources() async =>
        cachedResources ??= await UserStorage.getAgentLLMResources(
          AgentDefinitions.commentAgent,
          defaultClientKey: LLMConfig.defaultClientKey,
        );

    if (settings.enableCharacterComment) {
      if (maxChars <= 1 && !hasExplicitMention) {
        // Single-character mode: keyword-based selection (no LLM call)
        final selectedChar = await CharacterSelectionService.selectCharacter(
          userId: userId,
          inputContent: combinedText,
          factId: factId,
        );
        if (selectedChar != null) {
          wave1Queue.add((character: selectedChar, forceReply: false));
        }
      } else if (maxChars > mentionedChars.length) {
        // Multi-character mode: LLM-based selection for remaining slots
        final resources = await ensureResources();
        final selectedChars =
            await CharacterSelectionService.selectMultipleCharacters(
          userId: userId,
          inputContent: combinedText,
          factId: factId,
          client: resources.client,
          modelConfig: resources.modelConfig,
          maxCharacters: maxChars - mentionedChars.length,
          excludeCharacters: mentionedChars,
        );
        for (final char in selectedChars) {
          wave1Queue.add((character: char, forceReply: false));
        }
      }
    }

    if (wave1Queue.isEmpty) {
      _logger.info("No character selected, skipping comment agent");
      return;
    }

    // Process Wave 1 sequentially so each persona sees prior comments immediately
    final wave1Comments = <CardComment>[];
    final spokenIds = <String>{};
    for (final item in wave1Queue) {
      _logger.info(
        "Processing comment from character ${item.character.name} (${item.character.id})",
      );
      final created = await processAICommentReply(
        cardId: factId,
        userId: userId,
        userContent: Prompts.commentAgentInitialCommentPrompt,
        characterId: item.character.id,
        rawInputContent: combinedText,
        inputDateTime: inputDateTime,
        locationContextReminder: locationContextReminder,
        forceReply: item.forceReply,
      );
      if (created != null) {
        wave1Comments.add(created);
        spokenIds.add(item.character.id);
      }
    }

    // Wave 2: Live cross-persona replies & counterpoints
    final crossBudget =
        (maxChars - wave1Comments.length).clamp(0, maxCrossTalkRepliesPerWave);
    if (settings.enableCharacterComment &&
        maxChars > 1 &&
        crossBudget > 0 &&
        wave1Comments.isNotEmpty) {
      final resources = await ensureResources();
      await _runCrossTalkWave(
        userId: userId,
        cardId: factId,
        postContent: combinedText,
        wave1Comments: wave1Comments,
        initialSpokenIds: spokenIds,
        allCharacters: allCharacters,
        resources: resources,
        maxCrossTalkReplies: crossBudget,
        maxTotalTurns: maxChars.clamp(1, maxGroupPersonaTurnsPerUserMessage),
        checkUserTurnBudget: false,
        inputDateTime: inputDateTime,
        locationContextReminder: locationContextReminder,
        withMemoryManagement: false,
        readAttachedPdfs: false,
      );
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

  final settings = await CommentSettingsService.load(userId);
  final llmConfig = await UserStorage.getAgentLLMConfig(
    AgentDefinitions.commentAgent,
    defaultClientKey: LLMConfig.defaultClientKey,
  );
  if (!llmConfig.isValid) {
    _logger.info('No LLM configured — skipping process_ai_reply for $cardId');
    return;
  }

  final cardData = await FileSystemService.instance.readCardFile(
    userId,
    cardId,
  );
  if (cardData == null) {
    _logger.warning('Card $cardId not found — skipping process_ai_reply');
    return;
  }

  final resources = await UserStorage.getAgentLLMResources(
    AgentDefinitions.commentAgent,
    defaultClientKey: LLMConfig.defaultClientKey,
  );
  final allCharacters =
      await CharacterService.instance.getAllCharacters(userId);

  final selectedReplies = await CharacterSelectionService.selectReplyCharacters(
    userId: userId,
    postContent: cardData.fact ?? cardData.title ?? '',
    userComment: content,
    existingComments: cardData.comments,
    replyToId: replyToId,
    enableCharacterComment: settings.enableCharacterComment,
    maxCharacters: settings.maxCommentCharacters,
    client: resources.client,
    modelConfig: resources.modelConfig,
    charactersOverride: allCharacters,
  );

  if (selectedReplies.isEmpty) {
    _logger.info('No reply persona selected for card $cardId');
    return;
  }

  final normalizedCommentId =
      (commentId != null && commentId.trim().isNotEmpty)
          ? commentId.trim()
          : null;
  final normalizedReplyToId =
      (replyToId != null && replyToId.trim().isNotEmpty)
          ? replyToId.trim()
          : null;

  final wave1Comments = <CardComment>[];
  final spokenIds = <String>{};
  for (var i = 0; i < selectedReplies.length; i++) {
    final target = selectedReplies[i];
    final created = await processAICommentReply(
      cardId: cardId,
      userId: userId,
      userContent: content,
      userCommentId: i == 0 ? normalizedCommentId : null,
      fallbackReplyToId: i == 0
          ? normalizedReplyToId
          : (normalizedCommentId ?? normalizedReplyToId),
      characterId: target.character.id,
      inputDateTime: inputDateTime,
      locationContextReminder: locationContextReminder,
      withMemoryManagement: true,
      forceReply: target.forceReply,
      readAttachedPdfs: true,
    );
    if (created != null) {
      wave1Comments.add(created);
      spokenIds.add(target.character.id);
    }
  }

  // Wave 2: live cross-talk between personas (explicit @mentions + coordinator)
  if (settings.enableCharacterComment &&
      settings.maxCommentCharacters > 1 &&
      wave1Comments.isNotEmpty) {
    await _runCrossTalkWave(
      userId: userId,
      cardId: cardId,
      postContent: cardData.fact ?? cardData.title ?? '',
      wave1Comments: wave1Comments,
      initialSpokenIds: spokenIds,
      allCharacters: allCharacters,
      resources: resources,
      maxCrossTalkReplies: maxCrossTalkRepliesPerWave,
      maxTotalTurns: maxGroupPersonaTurnsPerUserMessage,
      checkUserTurnBudget: true,
      inputDateTime: inputDateTime,
      locationContextReminder: locationContextReminder,
      withMemoryManagement: true,
      readAttachedPdfs: true,
    );
  }
}

/// Best-effort: Wave 1 replies are already saved, so an error in Wave 2 must
/// not cause `LocalTaskExecutor` to retry the whole task and duplicate Wave 1.
Future<void> _runCrossTalkWave({
  required String userId,
  required String cardId,
  required String postContent,
  required List<CardComment> wave1Comments,
  required Set<String> initialSpokenIds,
  required List<CharacterModel> allCharacters,
  required ({LLMClient client, ModelConfig modelConfig}) resources,
  required int maxCrossTalkReplies,
  required int maxTotalTurns,
  required bool checkUserTurnBudget,
  required DateTime? inputDateTime,
  required String? locationContextReminder,
  required bool withMemoryManagement,
  required bool readAttachedPdfs,
}) async {
  try {
    final turns = await runCrossPersonaFollowupWave(
      wave1Comments: wave1Comments,
      initialSpokenIds: initialSpokenIds,
      allCharacters: allCharacters,
      maxCrossTalkReplies: maxCrossTalkReplies,
      maxTotalTurns: maxTotalTurns,
      checkUserTurnBudget: checkUserTurnBudget,
      loadComments: () async =>
          (await FileSystemService.instance.readCardFile(userId, cardId))
              ?.comments ??
          const [],
      selectCoordinatorFollowups: ({
        required List<CharacterModel> candidates,
        required List<CardComment> existingComments,
        required int maxCharacters,
      }) async {
        try {
          return await CharacterSelectionService.selectGroupFollowupCharacters(
            candidates: candidates,
            postContent: postContent,
            existingComments: existingComments,
            client: resources.client,
            modelConfig: resources.modelConfig,
            maxCharacters: maxCharacters,
          );
        } catch (e) {
          _logger.warning('Coordinator follow-up failed for $cardId: $e');
          final fallback = pickNextDebater(candidates, existingComments);
          return fallback == null ? const [] : [fallback];
        }
      },
      speak: ({
        required CharacterModel character,
        required String fallbackReplyToId,
        required bool forceReply,
      }) =>
          processAICommentReply(
        cardId: cardId,
        userId: userId,
        userContent: Prompts.personaDebatePrompt(fallbackReplyToId),
        characterId: character.id,
        fallbackReplyToId: fallbackReplyToId,
        inputDateTime: inputDateTime,
        locationContextReminder: locationContextReminder,
        withMemoryManagement: withMemoryManagement,
        forceReply: forceReply,
        readAttachedPdfs: readAttachedPdfs,
      ),
    );
    _logger.info('Live group cross-talk on $cardId added $turns turn(s)');
  } catch (e, stack) {
    _logger.warning('Live group cross-talk failed for $cardId: $e', e, stack);
  }
}

/// Resolves all `@mentioned` characters in [content] in order of appearance,
/// supporting `@id`, full `@name`, diacritic/case folding, and unique
/// `@first_name` (>= 3 chars), while ignoring email addresses.
@visibleForTesting
List<CharacterModel> resolveMentionedCharacters(
  String content,
  List<CharacterModel> characters,
) {
  return extractAllMentions<CharacterModel>(
    content,
    characters,
    idOf: (c) => c.id,
    nameOf: (c) => c.name,
  );
}

/// Total AI turns allowed per user message across Wave 1 and Wave 2.
const maxGroupPersonaTurnsPerUserMessage = 15;

/// Maximum cross-persona follow-up replies allowed in Wave 2 per trigger.
const maxCrossTalkRepliesPerWave = 5;

/// Coordinates Wave 2 cross-persona replies:
/// 1) Wakes any enabled persona `@mentioned` inside [wave1Comments] (forced reply).
/// 2) Asks the coordinator which remaining personas have a non-repetitive
///    counterpoint, question, or complement within budget.
@visibleForTesting
Future<int> runCrossPersonaFollowupWave({
  required List<CardComment> wave1Comments,
  required Set<String> initialSpokenIds,
  required List<CharacterModel> allCharacters,
  required int maxCrossTalkReplies,
  required int maxTotalTurns,
  required Future<List<CardComment>> Function() loadComments,
  required Future<List<CharacterModel>> Function({
    required List<CharacterModel> candidates,
    required List<CardComment> existingComments,
    required int maxCharacters,
  }) selectCoordinatorFollowups,
  required Future<CardComment?> Function({
    required CharacterModel character,
    required String fallbackReplyToId,
    required bool forceReply,
  }) speak,
  bool checkUserTurnBudget = true,
}) async {
  if (wave1Comments.isEmpty || maxCrossTalkReplies <= 0) {
    return 0;
  }

  final enabledCharacters =
      allCharacters.where((c) => c.enabled).toList(growable: false);
  if (enabledCharacters.isEmpty) {
    return 0;
  }

  final mentionQueue = <({CharacterModel character, String replyToId})>[];
  final crossWokenIds = <String>{};
  final wokenIdsAll = <String>{...initialSpokenIds};

  for (final comment in wave1Comments) {
    if (!comment.isAi || comment.content.trim().isEmpty) continue;
    final mentioned =
        resolveMentionedCharacters(comment.content, enabledCharacters);
    for (final target in mentioned) {
      if (target.id == comment.characterId) continue;
      if (!crossWokenIds.add(target.id)) continue;
      mentionQueue.add((character: target, replyToId: comment.id));
    }
  }

  var turns = 0;

  // Phase 2A: wake explicitly cross-mentioned personas
  for (final item in mentionQueue) {
    if (turns >= maxCrossTalkReplies) {
      return turns;
    }
    if (checkUserTurnBudget) {
      final comments = await loadComments();
      if (remainingPersonaTurns(comments, max: maxTotalTurns) <= 0) {
        return turns;
      }
    }
    wokenIdsAll.add(item.character.id);
    final created = await speak(
      character: item.character,
      fallbackReplyToId: item.replyToId,
      forceReply: true,
    );
    if (created != null) {
      turns++;
    }
  }

  // Phase 2B: coordinator-selected counterpoints among remaining personas
  var remainingCross = maxCrossTalkReplies - turns;
  if (remainingCross <= 0) {
    return turns;
  }

  var latestComments = await loadComments();
  if (checkUserTurnBudget) {
    final userRemaining =
        remainingPersonaTurns(latestComments, max: maxTotalTurns);
    if (userRemaining <= 0) {
      return turns;
    }
    if (userRemaining < remainingCross) {
      remainingCross = userRemaining;
    }
  }

  final coordinatorCandidates = enabledCharacters
      .where((c) => !wokenIdsAll.contains(c.id))
      .toList(growable: false);
  if (coordinatorCandidates.isEmpty) {
    return turns;
  }

  final selectedFollowups = await selectCoordinatorFollowups(
    candidates: coordinatorCandidates,
    existingComments: latestComments,
    maxCharacters: remainingCross,
  );
  if (selectedFollowups.isEmpty) {
    return turns;
  }

  var skips = 0;
  for (final candidate in selectedFollowups) {
    if (!candidate.enabled) continue;
    if (!wokenIdsAll.add(candidate.id)) continue;
    if (turns >= maxCrossTalkReplies) break;

    latestComments = await loadComments();
    if (checkUserTurnBudget &&
        remainingPersonaTurns(latestComments, max: maxTotalTurns) <= 0) {
      break;
    }

    final fallbackTarget = latestComments.lastWhere(
      (c) => c.isAi,
      orElse: () => wave1Comments.last,
    );
    final created = await speak(
      character: candidate,
      fallbackReplyToId: fallbackTarget.id,
      forceReply: false,
    );
    if (created == null) {
      skips++;
      if (skips >= maxPersonaSkipsPerDebate) {
        break;
      }
      continue;
    }
    turns++;
  }

  return turns;
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
