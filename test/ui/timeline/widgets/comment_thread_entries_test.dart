import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/ui/timeline/widgets/comment_thread_entries.dart';

int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Comment _persona(
  String id,
  DateTime at, {
  String characterId = 'lia',
  String name = 'Lia',
  String content = 'Oi',
  String? replyToId,
  String? replyToName,
}) {
  return Comment(
    id: id,
    content: content,
    isAi: true,
    timestamp: _secs(at),
    character: CharacterInfo(id: characterId, name: name, tags: const []),
    replyToId: replyToId,
    replyToName: replyToName,
  );
}

Comment _user(
  String id,
  DateTime at, {
  String content = 'E aí',
  String? replyToId,
  String? replyToName,
}) {
  return Comment(
    id: id,
    content: content,
    isAi: false,
    timestamp: _secs(at),
    replyToId: replyToId,
    replyToName: replyToName,
  );
}

List<CommentThreadEntry> _entries(List<Comment> comments, {Comment? pinned}) {
  return buildCommentThreadEntries(
    comments,
    pinned: pinned,
    aiFallbackName: 'IA',
    youLabel: 'Você',
  );
}

String _kind(CommentThreadEntry e) => switch (e) {
      CommentDateEntry() => 'date',
      CommentMessageEntry() => 'message',
    };

CommentMessageEntry _message(CommentThreadEntry e) => e as CommentMessageEntry;

void main() {
  final morning = DateTime(2026, 11, 16, 9, 0);

  group('day separators', () {
    test('a separator opens the thread and marks each new local day', () {
      final entries = _entries([
        _user('u1', morning),
        _user('u2', morning.add(const Duration(hours: 1))),
        _user('u3', DateTime(2026, 11, 17, 8, 0)),
      ]);

      expect(entries.map(_kind),
          ['date', 'message', 'message', 'date', 'message']);
      expect((entries[0] as CommentDateEntry).day, DateTime(2026, 11, 16));
      expect((entries[3] as CommentDateEntry).day, DateTime(2026, 11, 17));
    });

    test('no separator between messages of the same day', () {
      final entries = _entries([
        _user('u1', morning),
        _persona('p1', morning.add(const Duration(hours: 5))),
      ]);

      expect(entries.map(_kind), ['date', 'message', 'message']);
    });

    test('the first message gets no separator when the insight is that day',
        () {
      final pinned = _persona('insight', morning, content: 'Resumo');
      final entries = _entries(
        [_user('u1', morning.add(const Duration(minutes: 3)))],
        pinned: pinned,
      );

      expect(entries.map(_kind), ['message']);
    });

    test('the first message gets a separator when the insight is another day',
        () {
      final pinned = _persona(
        'insight',
        DateTime(2026, 11, 15, 22, 0),
        content: 'Resumo',
      );
      final entries = _entries([_user('u1', morning)], pinned: pinned);

      expect(entries.map(_kind), ['date', 'message']);
    });
  });

  group('grouping', () {
    test('the first message always shows its header', () {
      final entries = _entries([_persona('p1', morning)]);

      expect(_message(entries[1]).showHeader, isTrue);
    });

    test('same persona within 10 minutes shares one header', () {
      final entries = _entries([
        _persona('p1', morning),
        _persona('p2', morning.add(const Duration(minutes: 9))),
      ]);

      expect(_message(entries[1]).showHeader, isTrue);
      expect(_message(entries[2]).showHeader, isFalse);
    });

    test('exactly 10 minutes still groups', () {
      final entries = _entries([
        _persona('p1', morning),
        _persona('p2', morning.add(const Duration(minutes: 10))),
      ]);

      expect(_message(entries[2]).showHeader, isFalse);
    });

    test('after 10 minutes the header comes back', () {
      final entries = _entries([
        _persona('p1', morning),
        _persona('p2', morning.add(const Duration(minutes: 11))),
      ]);

      expect(_message(entries[2]).showHeader, isTrue);
    });

    test('a change of author breaks the group', () {
      final entries = _entries([
        _persona('p1', morning),
        _user('u1', morning.add(const Duration(minutes: 1))),
        _persona('p2', morning.add(const Duration(minutes: 2))),
        _persona('p3', morning.add(const Duration(minutes: 3)),
            characterId: 'bia', name: 'Bia'),
      ]);

      expect(_message(entries[2]).showHeader, isTrue,
          reason: 'user after persona');
      expect(_message(entries[3]).showHeader, isTrue,
          reason: 'persona after user');
      expect(_message(entries[4]).showHeader, isTrue, reason: 'other persona');
    });

    test('user messages in a row share a header', () {
      final entries = _entries([
        _user('u1', morning),
        _user('u2', morning.add(const Duration(minutes: 2))),
      ]);

      expect(_message(entries[2]).showHeader, isFalse);
    });

    test('the pinned insight counts as the previous author', () {
      final pinned = _persona('insight', morning, content: 'Resumo');
      final entries = _entries(
        [_persona('p1', morning.add(const Duration(minutes: 4)))],
        pinned: pinned,
      );

      expect(_message(entries.last).showHeader, isFalse);
    });
  });

  group('quote resolution', () {
    test('a persona target gives its name, text and character id', () {
      final entries = _entries([
        _persona('p1', morning, content: 'Bom dia'),
        _user('u1', morning.add(const Duration(minutes: 1)),
            replyToId: 'p1', replyToName: 'Lia'),
      ]);

      final quote = _message(entries[2]).quote!;
      expect(quote.targetId, 'p1');
      expect(quote.authorName, 'Lia');
      expect(quote.text, 'Bom dia');
      expect(quote.characterId, 'lia');
      expect(quote.isUser, isFalse);
    });

    test('a user target gives the "you" label and no character', () {
      final entries = _entries([
        _user('u1', morning, content: 'Quero dormir cedo'),
        _persona('p1', morning.add(const Duration(minutes: 1)),
            replyToId: 'u1', replyToName: 'Usuário'),
      ]);

      final quote = _message(entries[2]).quote!;
      expect(quote.targetId, 'u1');
      expect(quote.authorName, 'Você');
      expect(quote.text, 'Quero dormir cedo');
      expect(quote.characterId, isNull);
      expect(quote.isUser, isTrue);
    });

    test('the pinned insight is a valid target under the id insight', () {
      final pinned = _persona(
        'insight',
        morning,
        name: 'Lia',
        content: 'Resumo do dia',
      );
      final entries = _entries(
        [
          _user('u1', morning.add(const Duration(minutes: 1)),
              replyToId: 'insight', replyToName: 'Lia')
        ],
        pinned: pinned,
      );

      final quote = _message(entries.last).quote!;
      expect(quote.targetId, 'insight');
      expect(quote.authorName, 'Lia');
      expect(quote.text, 'Resumo do dia');
    });

    test('a missing target keeps only the stored name and no text', () {
      final entries = _entries([
        _user('u1', morning, replyToId: 'apagado', replyToName: 'Lia'),
      ]);

      final quote = _message(entries[1]).quote!;
      expect(quote.targetId, isNull);
      expect(quote.authorName, 'Lia');
      expect(quote.text, isNull);
    });

    test(
        'no reply gives no quote, and a missing target without a name gives none',
        () {
      final entries = _entries([
        _user('u1', morning),
        _user('u2', morning.add(const Duration(minutes: 1)), replyToId: 'x'),
      ]);

      expect(_message(entries[1]).quote, isNull);
      expect(_message(entries[2]).quote, isNull);
    });
  });
}
