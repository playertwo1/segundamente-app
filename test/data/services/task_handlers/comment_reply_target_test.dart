import 'package:memex/data/services/character_selection_service.dart';
import 'package:memex/data/services/task_handlers/comment_agent_handler.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:test/test.dart';

void main() {
  group('resolveReplyTargetCharacterId', () {
    const comments = [
      CardComment(
        id: 'a1',
        content: 'Character A first',
        isAi: true,
        timestamp: 1,
        characterId: 'char-a',
      ),
      CardComment(
        id: 'b1',
        content: 'Character B later',
        isAi: true,
        timestamp: 2,
        characterId: 'char-b',
      ),
      CardComment(
        id: 'u1',
        content: 'User replied to A',
        isAi: false,
        timestamp: 3,
        replyToId: 'a1',
      ),
      CardComment(
        id: 'u2',
        content: 'User replied to their own reply',
        isAi: false,
        timestamp: 4,
        replyToId: 'u1',
      ),
    ];

    test('direct reply to an AI comment uses that character', () {
      expect(resolveReplyTargetCharacterId(comments, 'a1'), 'char-a');
      expect(resolveReplyTargetCharacterId(comments, 'b1'), 'char-b');
    });

    test('reply to a user comment walks the chain to the thread owner', () {
      expect(resolveReplyTargetCharacterId(comments, 'u1'), 'char-a');
      expect(resolveReplyTargetCharacterId(comments, 'u2'), 'char-a');
    });

    test('unknown or cyclic reply ids return null', () {
      expect(resolveReplyTargetCharacterId(comments, 'missing'), isNull);
      expect(
        resolveReplyTargetCharacterId(
          const [
            CardComment(
              id: 'loop-a',
              content: 'loop',
              isAi: false,
              timestamp: 1,
              replyToId: 'loop-b',
            ),
            CardComment(
              id: 'loop-b',
              content: 'loop',
              isAi: false,
              timestamp: 2,
              replyToId: 'loop-a',
            ),
          ],
          'loop-a',
        ),
        isNull,
      );
    });
  });

  group('resolveMentionedCharacters & selectReplyCharacters', () {
    final characters = <CharacterModel>[
      CharacterModel(
        id: 'socio',
        name: 'Sócio Direto',
        tags: const ['decisao', 'estrategia'],
        persona: 'Direto ao ponto.',
        enabled: true,
        interestFilter: 'projeto, prazo, decisao',
      ),
      CharacterModel(
        id: 'advogado',
        name: 'Advogado do Diabo',
        tags: const ['risco', 'contrato'],
        persona: 'Questiona riscos.',
        enabled: true,
        interestFilter: 'contrato, risco, custo',
      ),
      CharacterModel(
        id: 'ritmo_marina',
        name: 'Marina Costa',
        tags: const ['ritmo', 'foco'],
        persona: 'Observa energia.',
        enabled: true,
      ),
    ];

    test('extracts multiple mentions in order with accent folding and ignores emails',
        () {
      final matched = resolveMentionedCharacters(
        'Falei com contato@socio.com, mas quero ouvir @Sócio e @advogado juntos.',
        characters,
      );
      expect(matched.map((c) => c.id).toList(), ['socio', 'advogado']);
    });

    test('matches unique @first_name (>= 3 chars) and skips ambiguous first names',
        () {
      final ambiguous = <CharacterModel>[
        ...characters,
        CharacterModel(
          id: 'pesquisadora_marina',
          name: 'Marina Silva',
          tags: const [],
          persona: '',
          enabled: true,
        ),
      ];
      final uniqueMatch = resolveMentionedCharacters(
        '@Marina o que acha do meu foco hoje?',
        characters,
      );
      expect(uniqueMatch.map((c) => c.id).toList(), ['ritmo_marina']);

      final ambiguousMatch = resolveMentionedCharacters(
        '@Marina o que acha?',
        ambiguous,
      );
      expect(ambiguousMatch, isEmpty);
    });

    test('selectReplyCharacters triggers all multiple @mentions with forceReply',
        () async {
      final selected = await CharacterSelectionService.selectReplyCharacters(
        userId: 'u_test',
        postContent: 'Proposta comercial',
        userComment: '@socio @advogado analisem os prós e riscos.',
        existingComments: const [],
        enableCharacterComment: true,
        maxCharacters: 15,
        charactersOverride: characters,
      );

      expect(selected.map((s) => s.character.id).toList(), ['socio', 'advogado']);
      expect(selected.every((s) => s.forceReply), isTrue);
    });

    test('open user follow-up comment without replyToId or @mention always gets a guaranteed responder',
        () async {
      final selected = await CharacterSelectionService.selectReplyCharacters(
        userId: 'u_test',
        postContent: 'Pensando no meu próximo passo.',
        userComment: 'Faz sentido, vou revisar amanhã de manhã.',
        existingComments: const [
          CardComment(
            id: 'c1',
            content: 'Qual ponto pesa mais agora?',
            isAi: true,
            timestamp: 10,
            characterId: 'marina',
          ),
        ],
        replyToId: null,
        enableCharacterComment: true,
        maxCharacters: 15,
        charactersOverride: characters,
      );

      expect(selected, isNotEmpty);
      expect(selected.first.forceReply, isTrue);
    });
  });
}
