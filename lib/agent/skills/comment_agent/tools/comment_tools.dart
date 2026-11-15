// ignore_for_file: non_constant_identifier_names

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/character_workspace_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/mention_parser.dart';
import 'package:uuid/uuid.dart';

/// Parsed result of a persona group-chat comment output, separating clean
/// visible text from `[REPLY:id]` routing and `[MEMORY: ...]` notes.
class ParsedGroupCommentOutput {
  final String content;
  final String? replyToId;
  final List<String> memoryNotes;

  const ParsedGroupCommentOutput({
    required this.content,
    this.replyToId,
    this.memoryNotes = const [],
  });
}

/// Extracts `[MEMORY: ...]` and `[REPLY:id]` control tags from [raw] so they
/// never leak into visible comments, compatible with Lumen group comment tags.
ParsedGroupCommentOutput parseGroupCommentOutput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const ParsedGroupCommentOutput(content: '');
  }

  final memExtracted = _extractAllTags(trimmed, 'MEMORY');
  final replyExtracted = _extractAllTags(memExtracted.cleaned, 'REPLY');

  final cleanReply = _cleanReplyTagId(replyExtracted.values.firstOrNull);
  final normalizedContent = replyExtracted.cleaned
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r' {2,}'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  return ParsedGroupCommentOutput(
    content: normalizedContent,
    replyToId: cleanReply,
    memoryNotes: memExtracted.values,
  );
}

({List<String> values, String cleaned}) _extractAllTags(
  String text,
  String tag,
) {
  final prefix = '[$tag:';
  final lowerPrefix = prefix.toLowerCase();
  final values = <String>[];
  final remaining = StringBuffer();
  var rest = text;

  while (true) {
    final pos = rest.toLowerCase().indexOf(lowerPrefix);
    if (pos < 0) break;
    remaining.write(rest.substring(0, pos));
    final afterPrefix = rest.substring(pos + prefix.length);
    final close = afterPrefix.indexOf(']');
    if (close < 0) {
      remaining.write(rest.substring(pos));
      rest = '';
      break;
    }
    final val = afterPrefix.substring(0, close).trim();
    if (val.isNotEmpty) {
      values.add(val);
    }
    rest = afterPrefix.substring(close + 1);
  }
  remaining.write(rest);
  return (values: values, cleaned: remaining.toString().trim());
}

String? _cleanReplyTagId(String? raw) {
  if (raw == null) return null;
  var cleaned = raw.trim();
  if (cleaned.startsWith('#')) {
    cleaned = cleaned.substring(1).trim();
  }
  if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
      (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
    if (cleaned.length >= 2) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
  }
  return cleaned.isEmpty ? null : cleaned;
}

class CommentToolFactory {
  final String userId;
  final String cardId;
  final String? characterId;
  final String? forcedReplyToId;
  final String? fallbackReplyToId;
  final List<CharacterModel> activeCharacters;

  CommentToolFactory({
    required this.userId,
    required this.cardId,
    this.characterId,
    this.forcedReplyToId,
    this.fallbackReplyToId,
    this.activeCharacters = const [],
  });

  Tool buildSaveCommentTool() {
    final fixedReplyTarget = _normalizedReplyToId(forcedReplyToId);
    return Tool(
      name: 'SaveComment',
      description: fixedReplyTarget == null
          ? 'Saves your comment to the current raw input or reply.'
          : 'Saves your comment as a reply to the current user comment. '
              'The reply_to_id parameter is fixed by the system for this task.',
      parameters: {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': 'The content of your comment.',
          },
          'reply_to_id': {
            'type': 'string',
            'description':
                'Optional. The ID of the comment you are replying to (another persona or user). Leave empty for a top-level comment.',
          },
        },
        'required': ['content'],
      },
      executable: (String content, String? reply_to_id) => _saveComment(
        content: content,
        replyToId: reply_to_id,
      ),
    );
  }

  Tool buildTodoProposalTool() => Tool(
        name: 'ProposeTodo',
        description:
            'Saves a persona comment with an editable Todo proposal. The task '
            'is not saved until the owner confirms it.',
        parameters: {
          'type': 'object',
          'properties': {
            'content': {'type': 'string'},
            'title': {'type': 'string'},
            'date_state': {
              'type': 'string',
              'enum': ['unspecified', 'explicit', 'ambiguous'],
            },
            'due_date': {'type': 'string'},
            'date_phrase': {'type': 'string'},
            'time_state': {
              'type': 'string',
              'enum': ['unspecified', 'explicit', 'ambiguous'],
            },
            'due_time': {'type': 'string'},
            'time_phrase': {'type': 'string'},
          },
          'required': ['content', 'title', 'date_state', 'time_state'],
        },
        executable: (
          String content,
          String title,
          String dateState,
          String timeState,
          String? dueDate,
          String? datePhrase,
          String? dueTime,
          String? timePhrase,
        ) async {
          final proposal = TodoProposal(
            id: const Uuid().v4(),
            title: title,
            dateState: TodoProposalDateState.values.byName(dateState),
            dueDate: dueDate,
            datePhrase: datePhrase,
            timeState: TodoProposalTimeState.values.byName(timeState),
            dueTime: dueTime,
            timePhrase: timePhrase,
          );
          return _saveComment(
            content: content,
            replyToId: forcedReplyToId,
            todoProposal: proposal,
          );
        },
      );

  Future<AgentToolResult> _saveComment({
    required String content,
    String? replyToId,
    TodoProposal? todoProposal,
  }) async {
    final parsed = parseGroupCommentOutput(content);
    if (parsed.content.isEmpty) {
      throw ArgumentError('Comment content cannot be empty.');
    }

    if (forcedReplyToId == null && parsed.content.toUpperCase() == '[SKIP]') {
      return AgentToolResult(
        content: TextPart('Comment skipped.'),
        stopFlag: true,
      );
    }

    if (parsed.memoryNotes.isNotEmpty &&
        characterId != null &&
        characterId!.isNotEmpty) {
      for (final note in parsed.memoryNotes) {
        try {
          await CharacterWorkspaceService.instance.appendLivingMemory(
            userId,
            characterId!,
            note,
          );
        } catch (e) {
          getLogger('CommentTool').warning(
            'Failed to append living memory for $characterId: $e',
          );
        }
      }
    }

    try {
      final fileSystemService = FileSystemService.instance;
      final commentId = const Uuid().v4();
      final now = DateTime.now();
      final fixedReplyTarget = _normalizedReplyToId(forcedReplyToId);
      final defaultReplyTarget = _normalizedReplyToId(fallbackReplyToId);
      final updatedCardData = await fileSystemService.updateCardFile(
        userId,
        cardId,
        (card) {
          final normalizedReplyTo = resolveEffectiveReplyToId(
            card: card,
            characterId: characterId,
            cleanContent: parsed.content,
            fixedReplyTarget: fixedReplyTarget,
            explicitToolReplyToId: _normalizedReplyToId(replyToId),
            tagReplyToId: _normalizedReplyToId(parsed.replyToId),
            fallbackReplyTarget: defaultReplyTarget,
            activeCharacters: activeCharacters,
          );
          final newComment = CardComment(
            id: commentId,
            content: parsed.content,
            isAi: true,
            timestamp: now.millisecondsSinceEpoch ~/ 1000,
            characterId: characterId,
            replyToId: normalizedReplyTo,
            todoProposal: todoProposal,
          );
          return card.copyWith(comments: [...card.comments, newComment]);
        },
      );

      if (updatedCardData == null) {
        throw StateError('Card not found: $cardId');
      }

      try {
        final cardPath = fileSystemService.getCardPath(userId, cardId);
        final workspacePath = fileSystemService.getWorkspacePath(userId);
        final relativePath = fileSystemService.toRelativePath(
          cardPath,
          rootPath: workspacePath,
        );
        await fileSystemService.eventLogService.logFileModified(
          userId: userId,
          filePath: relativePath,
          description: 'AI comment added to card via tool',
          metadata: {
            'card_id': cardId,
            'comment_id': commentId,
            'character_id': characterId,
            'content': parsed.content,
          },
        );
      } catch (e) {
        getLogger('CommentTool').warning('Failed to log event: $e');
      }

      EventBusService.instance.emitEvent(
        CardDetailUpdatedMessage(cardId: cardId),
      );

      return AgentToolResult(
        content: TextPart(todoProposal == null
            ? 'Comment saved successfully.'
            : 'Comment and Todo proposal saved. The task itself is still '
                'waiting for owner confirmation.'),
        stopFlag: true,
      );
    } catch (e, st) {
      getLogger('CommentTool').severe('Error saving comment', e, st);
      rethrow;
    }
  }

  /// Resolves `replyToId` with fixed routing priority, `[REPLY:id]` validation,
  /// `@mention` target lookup against earlier comments, and safe fallback.
  static String? resolveEffectiveReplyToId({
    required CardData card,
    required String? characterId,
    required String cleanContent,
    String? fixedReplyTarget,
    String? explicitToolReplyToId,
    String? tagReplyToId,
    String? fallbackReplyTarget,
    List<CharacterModel> activeCharacters = const [],
  }) {
    if (fixedReplyTarget != null && fixedReplyTarget.isNotEmpty) {
      return fixedReplyTarget;
    }

    CardComment? findTargetComment(String candidateId) {
      final lower = candidateId.toLowerCase();
      for (final existing in card.comments) {
        if (existing.id.toLowerCase() == lower) {
          return existing;
        }
      }
      return null;
    }

    bool isSelfReply(CardComment existing) =>
        characterId != null &&
        existing.isAi &&
        existing.characterId == characterId;

    if (explicitToolReplyToId != null && explicitToolReplyToId.isNotEmpty) {
      final match = findTargetComment(explicitToolReplyToId);
      if (match != null) {
        return isSelfReply(match) ? null : match.id;
      }
      return explicitToolReplyToId;
    }

    if (tagReplyToId != null && tagReplyToId.isNotEmpty) {
      final match = findTargetComment(tagReplyToId);
      if (match != null && !isSelfReply(match)) {
        return match.id;
      }
    }

    if (activeCharacters.isNotEmpty && card.comments.isNotEmpty) {
      final otherCharacters = activeCharacters
          .where((c) => c.id != characterId)
          .toList(growable: false);
      final mentioned = extractAllMentions<CharacterModel>(
        cleanContent,
        otherCharacters,
        idOf: (c) => c.id,
        nameOf: (c) => c.name,
      );
      for (final targetChar in mentioned) {
        for (final existing in card.comments.reversed) {
          if (existing.isAi && existing.characterId == targetChar.id) {
            return existing.id;
          }
        }
      }
    }

    if (fallbackReplyTarget != null && fallbackReplyTarget.isNotEmpty) {
      final match = findTargetComment(fallbackReplyTarget);
      if (match != null && !isSelfReply(match)) {
        return match.id;
      }
    }

    return null;
  }

  Tool buildSkipCommentTool() {
    return Tool(
      name: 'SkipComment',
      description:
          'Skips leaving a visible comment when the current entry is outside '
          'the character comment policy or a response would feel forced.',
      parameters: {
        'type': 'object',
        'properties': {
          'reason': {
            'type': 'string',
            'description':
                'A brief internal reason for skipping the visible comment.',
          },
        },
        'required': ['reason'],
      },
      executable: (String reason) async {
        getLogger('CommentTool').info(
          'Skipped AI comment for card $cardId, character=$characterId: $reason',
        );
        return AgentToolResult(
          content: TextPart('Comment skipped.'),
          stopFlag: true,
        );
      },
    );
  }

  static String? _normalizedReplyToId(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
