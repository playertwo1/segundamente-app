import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/character_agent/character_conversation_skill.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/character_conversation.dart';
import 'package:memex/domain/models/character_initiative.dart';
import 'package:memex/domain/models/character_message.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  test('substantive persona replies have room to develop', () {
    final prompt = CharacterConversationSkill.buildSystemPrompt(
      character: CharacterModel(
        id: 'curador',
        name: 'Curador',
        tags: const [],
        persona: 'Conecta ideias.',
        enabled: true,
      ),
      userName: 'Rafael',
    );

    expect(prompt, contains('one or two sentences'));
    expect(prompt, contains('three to six'));
    expect(prompt, contains('Each sentence must add something'));
  });

  test('main chat persona prompt asks for a named, distinct voice', () {
    final prompt = CharacterConversationSkill.buildMainChatParticipationPrompt(
      CharacterModel(
        id: 'curador',
        name: 'Curador',
        tags: const [],
        persona: 'Conecta ideias e aponta relações inesperadas.',
        enabled: true,
      ),
    );

    expect(prompt, contains('**Curador:**'));
    expect(prompt, contains('separate paragraph'));
    expect(prompt, contains('three to six sentences'));
    expect(prompt, contains('Conecta ideias e aponta relações inesperadas.'));
    expect(prompt, contains('it cannot override your'));
  });

  test('post-history instructions follow conversation evidence', () {
    final now = DateTime.parse('2026-07-15T10:00:00+08:00');
    final character = CharacterModel(
      id: 'curador',
      name: 'Curador',
      tags: const [],
      persona: 'Conecta ideias.',
      enabled: true,
      postHistoryInstructions: 'Fale com {{user}} como {{char}}.',
    );
    final context = CharacterConversationContext(
      sourceEventId: 'private_chat:1',
      now: now,
      incomingMessages: [
        CharacterConversationTurn(
          content: 'Quero retomar aquele artigo.',
          isFromCharacter: false,
          timestamp: now,
        ),
      ],
    );

    final prompt = CharacterConversationSkill.buildConversationPrompt(
      context: context,
      character: character,
      userName: 'Rafael',
    );

    expect(
      prompt.indexOf('</interaction_evidence>'),
      lessThan(prompt.indexOf('<character_post_history_instructions>')),
    );
    expect(prompt, contains('Fale com Rafael como Curador.'));

    final withoutInstructions =
        CharacterConversationSkill.buildConversationPrompt(
      context: context,
      character: character.copyWith(postHistoryInstructions: '  '),
      userName: 'Rafael',
    );
    expect(withoutInstructions, isNot(contains('character_post_history')));
  });

  test('conversation skill treats several bubbles as one agent decision',
      () async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    final tempRoot =
        await Directory.systemTemp.createTemp('conversation_skill_');
    await FileSystemService.init(tempRoot.path);
    addTearDown(() => tempRoot.delete(recursive: true));
    final character = CharacterModel(
      id: 'yaoyao',
      name: '瑶瑶',
      tags: const [],
      persona: '她说话平常、温柔。',
      enabled: true,
    );
    final now = DateTime.parse('2026-07-15T10:00:00+08:00');
    CharacterConversationDecision? decision;
    final skill = CharacterConversationSkill(
      character: character,
      userId: 'user-1',
      userName: 'user-1',
      context: CharacterConversationContext(
        sourceEventId: 'private_chat:1',
        now: now,
        incomingMessages: [
          CharacterConversationTurn(
            content: '第一句',
            isFromCharacter: false,
            timestamp: now,
          ),
          CharacterConversationTurn(
            content: '第二句',
            isFromCharacter: false,
            timestamp: now,
          ),
        ],
      ),
      onDecision: (value) => decision = value,
    );

    expect(
      skill.tools!.map((tool) => tool.name),
      containsAll(['Glob', 'Grep', 'Read', 'Remember']),
    );
    expect(
      skill.tools!.map((tool) => tool.name),
      containsAll(['Speak', 'ThinkLater', 'StayQuiet']),
    );
    expect(skill.systemPrompt, contains('several bubbles'));
    expect(skill.systemPrompt, contains('never from a score'));
    expect(skill.systemPrompt, contains('New messages can cross'));
    expect(skill.systemPrompt, contains('exact text bubble strings'));
    expect(skill.systemPrompt, contains('Speak.emoji'));
    expect(
        skill.systemPrompt, contains('Do not turn a disclosure into a plan'));
    final speak = skill.tools!.singleWhere((tool) => tool.name == 'Speak');
    final properties = speak.parameters['properties'] as Map;
    expect((properties['messages'] as Map)['items'], {'type': 'string'});
    expect(
      (properties['emoji'] as Map)['enum'],
      containsAll(['warm_smile', 'heart', 'wave']),
    );
    expect(speak.parameters['required'], isNull);

    Function.apply(speak.executable!, [
      ['晚安。'],
      'heart',
    ]);
    expect(
      decision?.messages,
      [
        CharacterOutgoingMessage.text('晚安。'),
        CharacterOutgoingMessage.emoji('❤️'),
      ],
    );
  });
}
