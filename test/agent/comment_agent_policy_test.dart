import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/agent/skills/comment_agent/comment_agent_skill.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/l10n/app_localizations_ext_en.dart';
import 'package:memex/l10n/app_localizations_ext_pt.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('CommentAgent policy routing', () {
    late Directory tempRoot;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      tempRoot = await Directory.systemTemp.createTemp('memex_comment_policy_');
      await FileSystemService.init(tempRoot.path);
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('normal mode exposes SaveComment and SkipComment', () {
      final skill = _buildSkill(forceReply: false, tempRoot: tempRoot);
      final toolNames = _toolNames(skill);

      expect(
        toolNames,
        containsAll(['SaveComment', 'SkipComment', 'ProposeTodo']),
      );
      expect(skill.systemPrompt, contains('Comment Policy'));
      expect(skill.systemPrompt, contains('SkipComment'));
      expect(skill.systemPrompt, contains('Todo proposals'));
      expect(skill.systemPrompt, contains('exactly one completion tool'));
    });

    test('force reply mode removes SkipComment and requires SaveComment', () {
      final skill = _buildSkill(forceReply: true, tempRoot: tempRoot);
      final toolNames = _toolNames(skill);

      expect(toolNames, containsAll(['SaveComment', 'ProposeTodo']));
      expect(toolNames, isNot(contains('SkipComment')));
      expect(skill.systemPrompt, contains('must leave a visible'));
      expect(skill.systemPrompt, contains('SaveComment'));
      expect(skill.systemPrompt, isNot(contains('call `SkipComment`')));
    });

    test('substantive entries get a fuller first comment', () {
      final skill = _buildSkill(forceReply: false, tempRoot: tempRoot);

      expect(skill.systemPrompt, contains('including the first one'));
      expect(skill.systemPrompt, contains('about 3-6 sentences'));
    });

    test('every default persona includes a comment policy', () {
      final defaults = UserStorage.l10n.defaultCharacters;
      expect(defaults, hasLength(15));
      for (final character in defaults) {
        final persona = character['persona'] as String;

        expect(persona, contains('## Comment Policy'),
            reason: '${character['id']}');
        expect(persona, contains('Reply when:'), reason: '${character['id']}');
        expect(persona, contains('Skip when:'), reason: '${character['id']}');
        expect(
          character['style_guide'],
          isNotEmpty,
          reason: '${character['id']}',
        );
        expect(character['post_history_instructions'], isNotEmpty,
            reason: '${character['id']}');
        expect(character['pkm_interest_filter'], isNotEmpty,
            reason: '${character['id']}');
      }
    });

    test('default personas state the boundaries of high-risk roles', () {
      final locales = [
        AppLocalizationsExtPt().defaultCharacters,
        AppLocalizationsExtEn().defaultCharacters,
      ];
      for (final characters in locales) {
        final defaults = {
          for (final character in characters)
            character['id'] as String: character,
        };

        expect(
          defaults['socio_tecnico']!['persona'],
          anyOf(
            contains('não presume que viu o repositório'),
            contains('does not assume it has seen the repository'),
          ),
        );
        expect(
          defaults['cobrador_prazo']!['persona'],
          anyOf(
            contains('não cria nem agenda lembretes'),
            contains('schedule reminders'),
          ),
        );
        expect(
          defaults['memoria_projeto']!['persona'],
          anyOf(
            contains('não repete a entrada'),
            contains('does not repeat the entry'),
          ),
        );
        expect(
          defaults['financas_burocracia']!['persona'],
          anyOf(
            contains('Não acessa banco ou contas externas'),
            contains('Does not access bank or external accounts'),
          ),
        );
        expect(
          defaults['curador']!['persona'],
          anyOf(
            contains('Não presume que abriu um link'),
            contains('Does not assume it opened a link'),
          ),
        );
      }
    });

    test('deadline and incident profiles have names matching their scope', () {
      final locales = [
        AppLocalizationsExtPt().defaultCharacters,
        AppLocalizationsExtEn().defaultCharacters,
      ];
      for (final characters in locales) {
        final defaults = {
          for (final character in characters)
            character['id'] as String: character,
        };
        final deadline = defaults['cobrador_prazo']!;
        final incident = defaults['calmo_crise']!;

        expect(
          deadline['name'],
          anyOf(
            equals('Acompanhante de prazos'),
            equals('Deadline tracker'),
          ),
        );
        expect(
          deadline['style_guide'],
          anyOf(
            contains('data estiver registrada e disponível'),
            contains('date is recorded and available'),
          ),
        );
        expect(
          incident['name'],
          anyOf(
            equals('Calmo em incidentes'),
            equals('Calm incident guide'),
          ),
        );
        expect(incident['tags'], isNot(contains('crise')));
        expect(incident['tags'], isNot(contains('crisis')));
        expect(
          incident['pkm_interest_filter'],
          anyOf(
            contains('crises emocionais e médicas'),
            contains('emotional and medical crises'),
          ),
        );
      }
    });

    test('execution scope and focus use one default profile in both locales',
        () {
      final locales = [
        AppLocalizationsExtPt().defaultCharacters,
        AppLocalizationsExtEn().defaultCharacters,
      ];
      for (final characters in locales) {
        final defaults = {
          for (final character in characters)
            character['id'] as String: character,
        };
        final facilitator = defaults['facilitador_execucao']!;
        final persona = facilitator['persona'] as String;

        expect(characters, hasLength(15));
        expect(defaults.keys, isNot(contains('gerente_escopo')));
        expect(defaults.keys, isNot(contains('parceiro_foco')));
        expect(
          facilitator['style_guide'],
          anyOf(
            contains('uma ação pequena'),
            contains('one small action'),
          ),
        );
        expect(
          persona,
          anyOf(
            contains('reduzir o plano ou escolher por onde começar'),
            contains('reduce the plan or choose where to start'),
          ),
        );
      }
    });

    test('merged context and new voices have distinct comment roles', () {
      final locales = [
        AppLocalizationsExtPt().defaultCharacters,
        AppLocalizationsExtEn().defaultCharacters,
      ];
      for (final characters in locales) {
        final defaults = {
          for (final character in characters)
            character['id'] as String: character,
        };

        expect(
            defaults.keys,
            containsAll([
              'memoria_projeto',
              'observador_progresso',
              'escuta_atenta',
            ]));
        expect(defaults.keys, isNot(contains('diario_bordo')));
        expect(
          defaults['memoria_projeto']!['persona'],
          anyOf(
              contains('Comment Policy'), contains('Política de comentários')),
        );
        expect(
          defaults['observador_progresso']!['persona'],
          anyOf(contains('Reply when:'), contains('Responda quando:')),
        );
        expect(
          defaults['escuta_atenta']!['persona'],
          anyOf(contains('Reply when:'), contains('Responda quando:')),
        );
        expect(
          defaults['escuta_atenta']!['persona'],
          anyOf(
            contains('sem atuar como terapeuta'),
            contains('without acting as a therapist'),
          ),
        );
      }
    });

    test('comment prompt supports policy based skipping in normal mode', () {
      final prompt = Prompts.commentSkillSystemPrompt(
        _policyPersona,
        'Reply in Chinese.',
      );

      expect(prompt, contains('Comment Policy'));
      expect(prompt, contains('call `SkipComment`'));
      expect(
          prompt, contains('Do not update memory when you call `SkipComment`'));
    });

    test('comment prompt preserves persona voice and access boundaries', () {
      final skill = CommentAgentSkill(
        character: CharacterModel(
          id: 'curador',
          name: 'Curador',
          tags: const ['leitura'],
          persona: _policyPersona,
          enabled: true,
          postHistoryInstructions: 'Fale com {{user}} como {{char}}.',
          mesExample: 'Exemplo em voz do Curador.',
        ),
        factId: '2026/06/08.md#ts_2',
        workingDirectory: tempRoot.path,
        userId: 'policy_test_user',
        userName: 'Rafael',
      );
      final prompt = skill.systemPrompt;

      expect(prompt, contains('Fale com Rafael como Curador.'));
      expect(
        prompt.indexOf('## Character Continuity'),
        lessThan(prompt.indexOf('## Style Examples')),
      );
      expect(
        prompt.indexOf('## Style Examples'),
        lessThan(prompt.lastIndexOf('<character_post_history_instructions>')),
      );
      expect(prompt, contains('Exemplo em voz do Curador.'));
      expect(prompt, contains('Do not claim to have inspected source code'));
      expect(prompt, isNot(contains('forget you are an AI')));
      expect(prompt, isNot(contains('calm, warm, and lightly sweet')));
    });
  });
}

CommentAgentSkill _buildSkill({
  required bool forceReply,
  required Directory tempRoot,
}) {
  return CommentAgentSkill(
    character: CharacterModel(
      id: 'counselor',
      name: '心理咨询师',
      tags: const ['倾听'],
      persona: _policyPersona,
      enabled: true,
    ),
    factId: '2026/06/08.md#ts_1',
    workingDirectory: tempRoot.path,
    userId: 'policy_test_user',
    forceReply: forceReply,
  );
}

List<String> _toolNames(CommentAgentSkill skill) =>
    (skill.tools ?? const []).map((tool) => tool.name).toList();

const _policyPersona = '''
This is a steady listener.

## Comment Policy
Reply when:
- The user clearly expresses stress or anxiety.

Skip when:
- The entry is a neutral shopping record or schedule.
''';
