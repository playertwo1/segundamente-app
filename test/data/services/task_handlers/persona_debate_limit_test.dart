import 'package:memex/data/services/task_handlers/comment_agent_handler.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:test/test.dart';

CardComment _c(String id, {required bool ai, String? content}) => CardComment(
      id: id,
      content: content ?? id,
      isAi: ai,
      timestamp: 0,
      characterId: ai ? 'char-$id' : null,
    );

CharacterModel _char(
  String id, {
  bool enabled = true,
  String? interestFilter,
}) =>
    CharacterModel(
      id: id,
      name: id,
      tags: const [],
      persona: '',
      enabled: enabled,
      interestFilter: interestFilter,
    );

void main() {
  group('remainingPersonaTurns', () {
    test('initial persona comment never opens a debate', () {
      expect(remainingPersonaTurns([_c('a1', ai: true)]), 0);
      expect(
        remainingPersonaTurns([_c('a1', ai: true), _c('a2', ai: true)]),
        0,
      );
      expect(remainingPersonaTurns(const []), 0);
    });

    test('a user reply allows the full four turns', () {
      expect(
        remainingPersonaTurns([_c('a1', ai: true), _c('u1', ai: false)]),
        4,
      );
    });

    test('each persona turn after the user message uses one', () {
      final thread = [_c('a1', ai: true), _c('u1', ai: false)];
      expect(remainingPersonaTurns([...thread, _c('a2', ai: true)]), 3);
      expect(
        remainingPersonaTurns(
            [...thread, _c('a2', ai: true), _c('a3', ai: true)]),
        2,
      );
    });

    test('stops at four and stays stopped', () {
      final thread = [
        _c('u1', ai: false),
        for (var i = 0; i < 4; i++) _c('a$i', ai: true),
      ];
      expect(remainingPersonaTurns(thread), 0);
      expect(remainingPersonaTurns([...thread, _c('a9', ai: true)]), 0);
    });

    test('a new user message resets the count', () {
      final thread = [
        _c('u1', ai: false),
        for (var i = 0; i < 4; i++) _c('a$i', ai: true),
        _c('u2', ai: false),
      ];
      expect(remainingPersonaTurns(thread), 4);
    });
  });

  group('pickNextDebater', () {
    test('skips the last speaker and disabled personas', () {
      final thread = [_c('u1', ai: false), _c('a1', ai: true)];
      final chars = [_char('char-a1'), _char('b', enabled: false), _char('c')];
      expect(pickNextDebater(chars, thread)?.id, 'c');
    });

    test('prefers the persona who spoke least, then id order', () {
      final thread = [
        _c('u1', ai: false),
        _c('x', ai: true),
        _c('y', ai: true),
      ];
      final chars = [_char('char-x'), _char('z'), _char('a')];
      expect(pickNextDebater(chars, thread)?.id, 'a');
    });

    test('prefers a persona matching the latest user message', () {
      final thread = [
        _c(
          'u1',
          ai: false,
          content: 'Estou cansada e dormi mal essa noite.',
        ),
        _c('a1', ai: true),
      ];
      final chars = [
        _char('amigo_bar', interestFilter: 'Focus on humor. Ignore sleep.'),
        _char('guardiao_energia',
            interestFilter: 'Focus on sleep and fatigue.'),
      ];

      expect(pickNextDebater(chars, thread)?.id, 'guardiao_energia');
    });

    test('nobody is available', () {
      final thread = [_c('u1', ai: false), _c('a1', ai: true)];
      expect(pickNextDebater([_char('char-a1')], thread), isNull);
    });
  });

  group('runPersonaDebate', () {
    late List<CardComment> thread;
    final chars = [_char('char-a1'), _char('b'), _char('c')];

    Future<int> run({bool Function(CharacterModel)? skip}) => runPersonaDebate(
          loadComments: () async => [...thread],
          loadCharacters: () async => chars,
          speak: (next, replyToId) async {
            if (skip?.call(next) ?? false) return;
            thread.add(CardComment(
              id: 'd${thread.length}',
              content: 'x',
              isAi: true,
              timestamp: 0,
              characterId: next.id,
              replyToId: replyToId,
            ));
          },
        );

    test('stops at four persona turns counting the direct reply', () async {
      thread = [_c('a0', ai: true), _c('u1', ai: false), _c('a1', ai: true)];
      expect(await run(), 3);
      expect(remainingPersonaTurns(thread), 0);
      expect(thread.length, 6);
    });

    test('no debate without a user message', () async {
      thread = [_c('a1', ai: true)];
      expect(await run(), 0);
    });

    test('stops when a persona has nothing to add', () async {
      thread = [_c('u1', ai: false), _c('a1', ai: true)];
      expect(await run(skip: (_) => true), 0);
      expect(thread.length, 2);
    });

    test('a persona that passes is replaced by another one', () async {
      thread = [_c('u1', ai: false), _c('a1', ai: true)];
      expect(await run(skip: (c) => c.id == 'b'), 3);
      final speakers = thread.where((c) => c.isAi).map((c) => c.characterId);
      expect(speakers, isNot(contains('b')));
    });

    test('gives up after two personas pass', () async {
      thread = [_c('u1', ai: false), _c('a1', ai: true)];
      var asked = 0;
      final turns = await runPersonaDebate(
        loadComments: () async => [...thread],
        loadCharacters: () async => [_char('b'), _char('c'), _char('d')],
        speak: (next, replyToId) async => asked++,
      );
      expect(turns, 0);
      expect(asked, maxPersonaSkipsPerDebate);
    });

    test('alternates personas instead of repeating the last speaker', () async {
      thread = [_c('u1', ai: false), _c('a1', ai: true)];
      await run();
      final speakers =
          thread.where((c) => c.isAi).map((c) => c.characterId).toList();
      for (var i = 1; i < speakers.length; i++) {
        expect(speakers[i], isNot(speakers[i - 1]));
      }
    });
  });
}
