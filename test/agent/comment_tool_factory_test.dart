import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/agent/skills/comment_agent/tools/comment_tools.dart';
import 'package:memex/data/services/character_workspace_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('CommentToolFactory SaveComment reply routing', () {
    late Directory tempRoot;
    late AppDatabase db;
    late String userId;
    const cardId = '2026/05/15.md#ts_1';
    const characterId = 'char-a';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      userId = 'comment_tool_${DateTime.now().microsecondsSinceEpoch}';
      await UserStorage.saveUser(userId);

      tempRoot = await Directory.systemTemp.createTemp('memex_comment_tool_');
      await FileSystemService.init(tempRoot.path);

      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
      await db.searchDao.createFtsTables();

      await _writeCard(
        userId: userId,
        cardId: cardId,
        comments: const [
          CardComment(
            id: 'char-comment',
            content: 'I am the original character comment.',
            isAi: true,
            timestamp: 1000,
            characterId: characterId,
          ),
          CardComment(
            id: 'user-comment',
            content: 'User replied to the character.',
            isAi: false,
            timestamp: 1001,
            replyToId: 'char-comment',
          ),
          CardComment(
            id: 'other-char-comment',
            content: 'I am a different character.',
            isAi: true,
            timestamp: 1002,
            characterId: 'char-b',
          ),
        ],
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test(
        'forcedReplyToId pins AI reply to the user comment even when '
        'the model supplies the original character comment id', () async {
      final tool = CommentToolFactory(
        userId: userId,
        cardId: cardId,
        characterId: characterId,
        forcedReplyToId: 'user-comment',
      ).buildSaveCommentTool();

      await Function.apply(tool.executable!, [
        'Character answer to the user.',
        'char-comment',
      ]);

      final latest = await _latestComment(userId, cardId);
      expect(latest.isAi, isTrue);
      expect(latest.characterId, characterId);
      expect(latest.replyToId, 'user-comment');
    });

    test(
        'forcedReplyToId still attaches to the user comment when '
        'the model leaves reply_to_id empty', () async {
      final tool = CommentToolFactory(
        userId: userId,
        cardId: cardId,
        characterId: characterId,
        forcedReplyToId: 'user-comment',
      ).buildSaveCommentTool();

      await Function.apply(tool.executable!, [
        'Character answer without explicit tool routing.',
        '',
      ]);

      final latest = await _latestComment(userId, cardId);
      expect(latest.replyToId, 'user-comment');
    });

    test(
      'without forcedReplyToId, SaveComment treats a self-reply as top-level',
      () async {
        final tool = CommentToolFactory(
          userId: userId,
          cardId: cardId,
          characterId: characterId,
        ).buildSaveCommentTool();

        await Function.apply(tool.executable!, [
          'Character comments on own previous comment.',
          'char-comment',
        ]);

        final latest = await _latestComment(userId, cardId);
        expect(latest.replyToId, isNull);
      },
    );

    test(
      'without forcedReplyToId, SaveComment preserves a valid model-supplied '
      'reply target for character-to-character interactions',
      () async {
        final tool = CommentToolFactory(
          userId: userId,
          cardId: cardId,
          characterId: characterId,
        ).buildSaveCommentTool();

        await Function.apply(tool.executable!, [
          'Character builds on another character.',
          'other-char-comment',
        ]);

        final latest = await _latestComment(userId, cardId);
        expect(latest.replyToId, 'other-char-comment');
      },
    );

    test('empty reply_to_id is normalized to a top-level comment', () async {
      final tool = CommentToolFactory(
        userId: userId,
        cardId: cardId,
        characterId: characterId,
      ).buildSaveCommentTool();

      await Function.apply(tool.executable!, [
        'Top-level character comment.',
        '   ',
      ]);

      final latest = await _latestComment(userId, cardId);
      expect(latest.replyToId, isNull);
    });

    test('SkipComment completes without writing a visible comment', () async {
      final cardBefore = await FileSystemService.instance.readCardFile(
        userId,
        cardId,
      );
      expect(cardBefore, isNotNull);

      final tool = CommentToolFactory(
        userId: userId,
        cardId: cardId,
        characterId: characterId,
      ).buildSkipCommentTool();

      await Function.apply(tool.executable!, [
        'Outside this character comment policy.',
      ]);

      final cardAfter = await FileSystemService.instance.readCardFile(
        userId,
        cardId,
      );
      expect(cardAfter, isNotNull);
      expect(cardAfter!.comments.length, cardBefore!.comments.length);
      expect(
        cardAfter.comments.map((c) => c.content),
        isNot(contains('Outside this character comment policy.')),
      );
    });

    test('ProposeTodo attaches an ambiguous proposal without resolving it',
        () async {
      final tool = CommentToolFactory(
        userId: userId,
        cardId: cardId,
        characterId: characterId,
      ).buildTodoProposalTool();

      await Function.apply(tool.executable!, [
        'Posso deixar isso como tarefa para você revisar.',
        'Enviar relatório',
        'ambiguous',
        'unspecified',
        null,
        'sexta',
        null,
        null,
      ]);

      final latest = await _latestComment(userId, cardId);
      expect(latest.content, contains('revisar'));
      expect(latest.todoProposal?.title, 'Enviar relatório');
      expect(latest.todoProposal?.datePhrase, 'sexta');
      expect(latest.todoProposal?.dueDate, isNull);
    });

    test('parseGroupCommentOutput extracts [REPLY:] and [MEMORY:] without leaking tags',
        () {
      const raw = '[REPLY: other-char-comment]\n'
          'Concordo com o @Sócio, mas falta orçamento.\n\n'
          'Vale checar antes de assinar.\n'
          '[MEMORY: Usuário negocia orçamento anual em maio.]\n'
          '[MEMORY: Preferência por validação jurídica prévia.]';

      final parsed = parseGroupCommentOutput(raw);
      expect(parsed.replyToId, 'other-char-comment');
      expect(parsed.memoryNotes, [
        'Usuário negocia orçamento anual em maio.',
        'Preferência por validação jurídica prévia.',
      ]);
      expect(
        parsed.content,
        'Concordo com o @Sócio, mas falta orçamento.\n\nVale checar antes de assinar.',
      );
      expect(parsed.content, isNot(contains('[REPLY:')));
      expect(parsed.content, isNot(contains('[MEMORY:')));
    });

    test('SaveComment strips [REPLY:]/[MEMORY:], persists MEMORY.md, and resolves @mention replyToId',
        () async {
      await CharacterWorkspaceService.instance.ensureInitialized(
        userId,
        CharacterModel(
          id: characterId,
          name: 'Sócio Direto',
          tags: const [],
          persona: 'Objetivo.',
          enabled: true,
        ),
      );

      final tool = CommentToolFactory(
        userId: userId,
        cardId: cardId,
        characterId: characterId,
        fallbackReplyToId: 'user-comment',
        activeCharacters: [
          CharacterModel(
            id: characterId,
            name: 'Sócio Direto',
            tags: const [],
            persona: '',
            enabled: true,
          ),
          CharacterModel(
            id: 'char-b',
            name: 'Advogado do Diabo',
            tags: const [],
            persona: '',
            enabled: true,
          ),
        ],
      ).buildSaveCommentTool();

      await Function.apply(tool.executable!, [
        '@Advogado bom ponto sobre a cláusula.\n[MEMORY: Usuário valoriza análise de risco contratual.]',
        null,
      ]);

      final latest = await _latestComment(userId, cardId);
      expect(latest.content, '@Advogado bom ponto sobre a cláusula.');
      expect(latest.content, isNot(contains('[MEMORY:')));
      expect(latest.replyToId, 'other-char-comment');

      final docs = await CharacterWorkspaceService.instance.loadPersonaLivingDocs(
        userId,
        CharacterModel(
          id: characterId,
          name: 'Sócio Direto',
          tags: const [],
          persona: 'Objetivo.',
          enabled: true,
        ),
      );
      expect(docs.livingMemory, contains('análise de risco contratual'));
    });
  });
}

Future<void> _writeCard({
  required String userId,
  required String cardId,
  required List<CardComment> comments,
}) async {
  await FileSystemService.instance.safeWriteCardFile(
    userId,
    cardId,
    CardData(
      factId: cardId,
      timestamp: 1000,
      status: 'done',
      tags: const [],
      uiConfigs: const [],
      title: 'Reply routing fixture',
      comments: comments,
    ),
  );
}

Future<CardComment> _latestComment(String userId, String cardId) async {
  final card = await FileSystemService.instance.readCardFile(userId, cardId);
  expect(card, isNotNull);
  expect(card!.comments, isNotEmpty);
  return card.comments.last;
}
