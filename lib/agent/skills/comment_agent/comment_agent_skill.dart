import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/character_agent/character_workspace_tools.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/agent/skills/character_tools_factory.dart';
import 'package:memex/agent/skills/comment_agent/tools/comment_tools.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/utils/tavern_macro.dart';
import 'package:memex/utils/user_storage.dart';

/// Skill for in-character responses to the user's private timeline entries.
class CommentAgentSkill extends Skill {
  CommentAgentSkill({
    CharacterModel? character,
    required String factId,
    required String workingDirectory,
    required String userId,
    String userName = '',
    String? forcedReplyToId,
    bool forceReply = false,
    super.forceActivate,
  }) : super(
          name: "persona_comment",
          description: Prompts.commentAgentSkillDescription,
          systemPrompt: _buildSystemPrompt(
            character: character,
            userName: userName,
            forceReply: forceReply,
          ),
          tools: _buildTools(
            userId: userId,
            workingDirectory: workingDirectory,
            factId: factId,
            characterId: character?.id,
            forcedReplyToId: forcedReplyToId,
            forceReply: forceReply,
          ),
        );

  static String _buildSystemPrompt({
    CharacterModel? character,
    required String userName,
    required bool forceReply,
  }) {
    StringBuffer personaBuffer = StringBuffer();
    if (character != null) {
      final charName = character.name;
      String m(String text) =>
          TavernMacro.resolve(text, userName: userName, charName: charName);
      personaBuffer.writeln("Name: $charName");
      personaBuffer.writeln("Tags: ${character.tags.join(', ')}");
      personaBuffer.writeln("### Persona: \n${m(character.persona)}");
    }
    String persona = personaBuffer.toString();

    final systemPrompt = Prompts.commentSkillSystemPrompt(
      persona,
      UserStorage.l10n.commentLanguageInstruction,
      forceReply: forceReply,
    );

    final b = StringBuffer();

    // systemPromptOverride takes highest priority — prepend before skill prompt.
    if (character != null &&
        character.systemPromptOverride != null &&
        character.systemPromptOverride!.trim().isNotEmpty) {
      final charName = character.name;
      b.writeln(
        TavernMacro.resolve(
          character.systemPromptOverride!,
          userName: userName,
          charName: charName,
        ),
      );
      b.writeln('');
    }

    b.write(systemPrompt);
    b.writeln('');
    b.writeln('## Todo proposals');
    b.writeln(
      'When the owner explicitly expresses a task intention, you may use '
      '`ProposeTodo` to attach a review card to your comment. This saves only '
      'the comment and proposal; the Todo task is created only after the '
      'owner confirms it. Treat weekday-only dates such as "sexta" as '
      'ambiguous and never invent a date or hour. Use unspecified time when '
      'none was stated.',
    );

    if (character != null) {
      b.writeln('');
      b.writeln('## Character Continuity');
      b.writeln(
        'Start from `/Identity.md`; search `/PKM`, `/Journal`, and `/World` '
        'progressively only when this entry makes something relevant. Your '
        'workspace is your durable perspective. Do not assume access to a '
        'global user profile or re-read unrelated raw records.',
      );
    }

    if (character != null &&
        character.mesExample != null &&
        character.mesExample!.trim().isNotEmpty) {
      final charName = character.name;
      b.writeln('');
      b.writeln('## Style Examples');
      b.writeln(
        TavernMacro.resolve(
          character.mesExample!,
          userName: userName,
          charName: charName,
        ),
      );
    }

    final postHistoryInstructions = character?.postHistoryInstructions?.trim();
    if (character != null && postHistoryInstructions?.isNotEmpty == true) {
      b.writeln('');
      b.writeln('<character_post_history_instructions>');
      b.writeln(
        TavernMacro.resolve(
          postHistoryInstructions!,
          userName: userName,
          charName: character.name,
        ),
      );
      b.writeln('</character_post_history_instructions>');
    }

    return b.toString();
  }

  static List<Tool> _buildTools({
    required String userId,
    required String workingDirectory,
    required String factId,
    String? characterId,
    String? forcedReplyToId,
    required bool forceReply,
  }) {
    if (characterId != null) {
      final commentFactory = CommentToolFactory(
        userId: userId,
        cardId: factId,
        characterId: characterId,
        forcedReplyToId: forcedReplyToId,
      );
      return [
        ...CharacterWorkspaceMemoryTools(
          userId: userId,
          characterId: characterId,
        ).build(),
        commentFactory.buildSaveCommentTool(),
        commentFactory.buildTodoProposalTool(),
        if (!forceReply) commentFactory.buildSkipCommentTool(),
      ];
    }
    return CharacterToolsFactory.buildCommentTools(
      userId: userId,
      workingDirectory: workingDirectory,
      factId: factId,
      characterId: characterId,
      forcedReplyToId: forcedReplyToId,
      includeSkipCommentTool: !forceReply,
    );
  }
}
