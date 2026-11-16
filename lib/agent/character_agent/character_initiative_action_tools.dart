// ignore_for_file: non_constant_identifier_names

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/domain/models/character_emoji.dart';
import 'package:memex/domain/models/character_message.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:uuid/uuid.dart';

abstract final class CharacterInitiativeActionTools {
  static List<Tool> build({
    required DateTime now,
    required void Function(
      List<CharacterOutgoingMessage> messages,
      DateTime wakeAt,
      String reason,
    ) onSpeak,
    required void Function(DateTime wakeAt, String reason) onSleepUntil,
    void Function(TodoProposal proposal)? onSuggestTask,
  }) {
    return [
      _speak(now, onSpeak),
      _sleepUntil(now, onSleepUntil),
      if (onSuggestTask != null) _suggestTask(onSuggestTask),
    ];
  }

  static Tool _speak(
    DateTime now,
    void Function(List<CharacterOutgoingMessage>, DateTime, String) onSpeak,
  ) {
    return Tool(
      name: 'Speak',
      description: 'Send one natural private-chat burst now and choose when '
          'you next want a chance to reconsider contact.',
      parameters: {
        'type': 'object',
        'properties': {
          'messages': {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
            'description': 'Optional exact text bubbles in send order. Keep '
                'standalone emoji out of this field.',
          },
          'emoji': {
            'type': 'string',
            'enum': CharacterEmoji.agentIds,
            'description': 'Optional standalone Fluent emoji gesture, sent '
                'after the text bubbles. Omit it when no gesture is natural.',
          },
          'next_wake_at': {
            'type': 'string',
            'format': 'date-time',
            'description': 'A future ISO 8601 timestamp with timezone.',
          },
          'next_wake_reason': {
            'type': 'string',
            'description': 'Why your future self may want to reconsider '
                'contact then. Never shown to the user.',
          },
        },
        'required': ['next_wake_at', 'next_wake_reason'],
      },
      executable: (
        List<dynamic>? messages,
        String? emoji,
        String next_wake_at,
        String next_wake_reason,
      ) {
        final normalized = parseCharacterOutgoingMessages(
          messages,
          emojiId: emoji,
        );
        final wake = _parseWake(
          now: now,
          wakeAtText: next_wake_at,
          reason: next_wake_reason,
        );
        onSpeak(normalized, wake.wakeAt, wake.reason);
        return AgentToolResult(
          content: TextPart('Private messages and next wake selected.'),
          stopFlag: true,
        );
      },
    );
  }

  static Tool _sleepUntil(
    DateTime now,
    void Function(DateTime, String) onSleepUntil,
  ) {
    return Tool(
      name: 'SleepUntil',
      description: 'Send nothing now and choose when you next want a chance '
          'to reconsider contact.',
      parameters: {
        'type': 'object',
        'properties': {
          'wake_at': {
            'type': 'string',
            'format': 'date-time',
            'description': 'A future ISO 8601 timestamp with timezone.',
          },
          'reason': {
            'type': 'string',
            'description': 'Why your future self may want to reconsider '
                'contact then. Never shown to the user.',
          },
        },
        'required': ['wake_at', 'reason'],
      },
      executable: (String wake_at, String reason) {
        final wake = _parseWake(
          now: now,
          wakeAtText: wake_at,
          reason: reason,
        );
        onSleepUntil(wake.wakeAt, wake.reason);
        return AgentToolResult(
          content: TextPart('Next wake selected.'),
          stopFlag: true,
        );
      },
    );
  }

  static Tool _suggestTask(void Function(TodoProposal) onSuggestTask) {
    return Tool(
      name: 'SuggestTask',
      description: 'Prepares a task suggestion to the owner as a proposal. '
          'Does not save a task directly; waits for owner approval.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'date_state': {
            'type': 'string',
            'enum': ['unspecified', 'explicit', 'ambiguous'],
          },
          'due_date': {
            'type': 'string',
            'description': 'YYYY-MM-DD, only for an explicit date.',
          },
          'date_phrase': {
            'type': 'string',
            'description': 'Original ambiguous date phrase, if any.',
          },
          'time_state': {
            'type': 'string',
            'enum': ['unspecified', 'explicit', 'ambiguous'],
          },
          'due_time': {
            'type': 'string',
            'description': 'HH:mm, only for an explicit time.',
          },
          'time_phrase': {
            'type': 'string',
            'description': 'Original ambiguous time phrase, if any.',
          },
        },
        'required': ['title', 'date_state', 'time_state'],
      },
      executable: (
        String title,
        String date_state,
        String time_state,
        String? due_date,
        String? date_phrase,
        String? due_time,
        String? time_phrase,
      ) {
        final proposal = TodoProposal(
          id: const Uuid().v4(),
          title: title,
          dateState: TodoProposalDateState.values.byName(date_state),
          dueDate: due_date,
          datePhrase: date_phrase,
          timeState: TodoProposalTimeState.values.byName(time_state),
          dueTime: due_time,
          timePhrase: time_phrase,
        );
        onSuggestTask(proposal);
        return AgentToolResult(
          content: TextPart(
            'Task proposal prepared. It is only a suggestion waiting for '
            'owner approval and has not been saved.',
          ),
          stopFlag: false,
        );
      },
    );
  }

  static ({DateTime wakeAt, String reason}) _parseWake({
    required DateTime now,
    required String wakeAtText,
    required String reason,
  }) {
    final wakeAt = DateTime.tryParse(wakeAtText);
    if (wakeAt == null || !wakeAt.isAfter(now)) {
      throw ArgumentError('wake_at must be a valid future timestamp.');
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError('reason must describe what you want to revisit.');
    }
    return (wakeAt: wakeAt, reason: normalizedReason);
  }
}
