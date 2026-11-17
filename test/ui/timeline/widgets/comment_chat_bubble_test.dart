import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/timeline/widgets/comment_chat_bubble.dart';
import 'package:memex/ui/timeline/widgets/comment_thread_entries.dart';

final DateTime _time = DateTime(2026, 11, 16, 14, 32);

void _noop() {}

const _bubbleKey = ValueKey('comment_chat_bubble_body');
const _avatarKey = ValueKey('avatar');

/// Persona content is rendered by MarkdownBody, so match rich text too.
Finder _text(String text) => find.text(text, findRichText: true);

Future<void> _pump(
  WidgetTester tester,
  Widget bubble, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: 360, child: bubble),
          ),
        ),
      ),
    ),
  );
}

CommentChatBubble _persona({
  String content = 'Boa noite',
  bool showHeader = true,
  VoidCallback? onReply,
  CommentQuote? quote,
  ValueChanged<String>? onQuoteTap,
  bool animateIn = false,
  int flashSignal = 0,
}) {
  return CommentChatBubble(
    isUser: false,
    content: content,
    time: _time,
    authorName: 'Lia',
    characterId: 'lia',
    avatar: const SizedBox(key: _avatarKey, width: 30, height: 30),
    showHeader: showHeader,
    quote: quote,
    onQuoteTap: onQuoteTap,
    onReply: onReply,
    replyLabel: 'Responder',
    animateIn: animateIn,
    flashSignal: flashSignal,
  );
}

CommentChatBubble _user({
  String content = 'Bom dia',
  VoidCallback? onReply,
  bool animateIn = false,
  int flashSignal = 0,
}) {
  return CommentChatBubble(
    isUser: true,
    content: content,
    time: _time,
    onReply: onReply,
    replyLabel: 'Responder',
    animateIn: animateIn,
    flashSignal: flashSignal,
  );
}

Color? _bubbleColor(WidgetTester tester) {
  final box = tester.widget<Container>(find.byKey(_bubbleKey));
  return (box.decoration! as BoxDecoration).color;
}

void main() {
  group('layout and colors', () {
    testWidgets('user bubble sits on the right with the ivory color',
        (tester) async {
      await _pump(tester, _user());

      expect(_bubbleColor(tester), AppColors.chatBubbleUser);
      final bubble = tester.getRect(find.byKey(_bubbleKey));
      final row = tester.getRect(find.byType(CommentChatBubble));
      expect(bubble.right, closeTo(row.right, 0.5));
      expect(find.byKey(_avatarKey), findsNothing);
    });

    testWidgets('persona bubble sits on the left after a 30dp avatar',
        (tester) async {
      await _pump(tester, _persona());

      expect(_bubbleColor(tester), AppColors.chatBubblePersona);
      final bubble = tester.getRect(find.byKey(_bubbleKey));
      final row = tester.getRect(find.byType(CommentChatBubble));
      expect(bubble.left, closeTo(row.left + 38, 0.5));
      expect(find.byKey(_avatarKey), findsOneWidget);
    });

    testWidgets('the header shows only when showHeader is true',
        (tester) async {
      await _pump(tester, _persona());
      expect(find.text('Lia'), findsOneWidget);

      await _pump(tester, _persona(showHeader: false));
      expect(find.text('Lia'), findsNothing);
      // The avatar slot stays, so the text still lines up with its group.
      final bubble = tester.getRect(find.byKey(_bubbleKey));
      final row = tester.getRect(find.byType(CommentChatBubble));
      expect(bubble.left, closeTo(row.left + 38, 0.5));
      expect(find.byKey(_avatarKey), findsNothing);
    });

    testWidgets('the time is shown as HH:mm', (tester) async {
      await _pump(tester, _user());
      expect(find.text('14:32'), findsOneWidget);
    });
  });

  group('quote', () {
    testWidgets(
        'renders the quoted author and text, and a tap sends the target id',
        (tester) async {
      String? tapped;
      var replies = 0;
      await _pump(
        tester,
        _persona(
          quote: const CommentQuote(
            targetId: 'c1',
            authorName: 'Você',
            text: 'Oi, tudo bem?',
            characterId: null,
            isUser: true,
          ),
          onQuoteTap: (id) => tapped = id,
          onReply: () => replies++,
        ),
      );

      expect(find.text('Você'), findsOneWidget);
      expect(find.text('Oi, tudo bem?'), findsOneWidget);

      await tester.tap(find.text('Oi, tudo bem?'));
      await tester.pumpAndSettle();
      expect(tapped, 'c1');
      expect(replies, 0, reason: 'tapping a quote must not start a reply');
    });

    testWidgets('a quote without a target does nothing when tapped',
        (tester) async {
      var taps = 0;
      var replies = 0;
      await _pump(
        tester,
        _persona(
          quote: const CommentQuote(
            targetId: null,
            authorName: 'Bia',
            text: null,
            characterId: 'bia',
            isUser: false,
          ),
          onQuoteTap: (_) => taps++,
          onReply: () => replies++,
        ),
      );

      await tester.tap(find.text('Bia'));
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(replies, 0);
    });

    testWidgets('a persona quote inside a persona bubble uses the light color',
        (tester) async {
      await _pump(
        tester,
        _persona(
          quote: const CommentQuote(
            targetId: 'c2',
            authorName: 'Bia',
            text: 'Vou dormir',
            characterId: 'bia',
            isUser: false,
          ),
        ),
      );

      final color = tester.widget<Text>(find.text('Bia')).style?.color;
      expect(color, AppColors.chatPersonaLight[commentPersonaIndex('bia')]);
    });

    testWidgets('a persona quote inside the user bubble uses the dark variant',
        (tester) async {
      await _pump(
        tester,
        CommentChatBubble(
          isUser: true,
          content: 'Concordo',
          time: _time,
          quote: const CommentQuote(
            targetId: 'c2',
            authorName: 'Bia',
            text: 'Vou dormir',
            characterId: 'bia',
            isUser: false,
          ),
        ),
      );

      final color = tester.widget<Text>(find.text('Bia')).style?.color;
      expect(color, AppColors.chatPersonaDark[commentPersonaIndex('bia')]);
    });
  });

  group('reply', () {
    testWidgets('a tap calls onReply', (tester) async {
      var replies = 0;
      await _pump(tester, _persona(onReply: () => replies++));

      await tester.tap(_text('Boa noite'));
      await tester.pumpAndSettle();
      expect(replies, 1);
    });

    testWidgets('a drag of 90dp replies once the 56dp threshold is passed',
        (tester) async {
      var replies = 0;
      await _pump(tester, _user(onReply: () => replies++));

      await tester.drag(_text('Bom dia'), const Offset(90, 0));
      await tester.pumpAndSettle();
      expect(replies, 1);
    });

    testWidgets('a drag under 56dp does not reply', (tester) async {
      var replies = 0;
      await _pump(tester, _user(onReply: () => replies++));
      final start = tester.getTopLeft(_text('Bom dia')).dx;

      final gesture = await tester.startGesture(
        tester.getCenter(_text('Bom dia')),
      );
      await gesture.moveBy(const Offset(20, 0)); // accepts the drag
      await gesture.moveBy(const Offset(45, 0));
      await tester.pump();
      expect(tester.getTopLeft(_text('Bom dia')).dx, closeTo(start + 45, 0.5));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(replies, 0);
    });

    testWidgets('the row follows the finger, clamps at 72dp and springs back',
        (tester) async {
      await _pump(tester, _persona(onReply: () {}));
      final start = tester.getTopLeft(_text('Boa noite')).dx;

      final gesture = await tester.startGesture(
        tester.getCenter(_text('Boa noite')),
      );
      // The first move past the touch slop starts the drag and is not
      // reported as an update, so accept with a short move first.
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(_text('Boa noite')).dx,
        closeTo(start + 40, 0.5),
      );
      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);

      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(_text('Boa noite')).dx,
        closeTo(start + 72, 0.5),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_text('Boa noite')).dx, closeTo(start, 0.5));
    });

    testWidgets('crossing the threshold gives one selection haptic',
        (tester) async {
      final calls = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(tester, _user(onReply: () {}));
      await tester.drag(_text('Bom dia'), const Offset(90, 0));
      await tester.pumpAndSettle();

      expect(calls, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('the insight bubble has no reply affordance', (tester) async {
      await _pump(tester, _persona(content: 'Resumo do dia'));

      await tester.drag(_text('Resumo do dia'), const Offset(90, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.reply_rounded), findsNothing);
      expect(_text('Resumo do dia'), findsOneWidget);
    });

    testWidgets(
        'with reduced motion the row does not move, but the reply still works',
        (tester) async {
      var replies = 0;
      await _pump(
        tester,
        _user(onReply: () => replies++),
        disableAnimations: true,
      );
      final start = tester.getTopLeft(_text('Bom dia')).dx;

      final gesture = await tester.startGesture(
        tester.getCenter(_text('Bom dia')),
      );
      await gesture.moveBy(const Offset(20, 0)); // accepts the drag
      await gesture.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(tester.getTopLeft(_text('Bom dia')).dx, closeTo(start, 0.5));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(replies, 1);
    });
  });

  group('motion', () {
    testWidgets('an arriving persona bubble fades and scales in',
        (tester) async {
      await _pump(tester, _persona(animateIn: true));

      double opacity() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: _text('Boa noite'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;

      expect(opacity(), 0);
      await tester.pumpAndSettle();
      expect(opacity(), 1);
    });

    testWidgets('an arriving user bubble fades in and moves into place',
        (tester) async {
      await _pump(tester, _user(content: 'Chegou', animateIn: true));

      await tester.pump();
      final start = tester.getTopLeft(_text('Chegou'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_text('Chegou')).dy, lessThan(start.dy));
    });

    testWidgets(
        'with reduced motion the entrance is only a fade of at most 150ms',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: _user(content: 'Chegou', animateIn: true),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 160));
      final opacity = tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: _text('Chegou'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(opacity, 1);
      expect(
        find.descendant(
          of: find.byType(CommentChatBubble),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });

    testWidgets(
        'a new flash signal highlights the bubble, then it returns to the base color',
        (tester) async {
      await _pump(tester, _user());
      expect(_bubbleColor(tester), AppColors.chatBubbleUser);

      await _pump(tester, _user(flashSignal: 1));
      expect(_bubbleColor(tester), AppColors.chatFlashUser);

      await tester.pumpAndSettle();
      expect(_bubbleColor(tester), AppColors.chatBubbleUser);
    });
  });

  group('reply preview', () {
    testWidgets('shows the title and the excerpt of the quoted message',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommentReplyPreview(
              title: 'Respondendo a Lia',
              excerpt: '  Boa noite, tudo bem?  ',
              color: AppColors.primary,
              cancelLabel: 'Cancelar resposta',
              onCancel: _noop,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Respondendo a Lia'), findsOneWidget);
      expect(find.text('Boa noite, tudo bem?'), findsOneWidget);
    });

    testWidgets('without an excerpt only the title shows', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommentReplyPreview(
              title: 'Respondendo a Lia',
              excerpt: null,
              color: AppColors.primary,
              cancelLabel: 'Cancelar resposta',
              onCancel: _noop,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Respondendo a Lia'), findsOneWidget);
      expect(find.byType(Text), findsNWidgets(1));
    });

    testWidgets('the X is a 48dp target that cancels the reply',
        (tester) async {
      var cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentReplyPreview(
              title: 'Respondendo a Lia',
              excerpt: 'Oi',
              color: AppColors.primary,
              cancelLabel: 'Cancelar resposta',
              onCancel: () => cancels++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cancel = find.byTooltip('Cancelar resposta');
      expect(tester.getSize(cancel), const Size(48, 48));
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(cancels, 1);
    });

    testWidgets('the preview fades and rises in', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommentReplyPreview(
              title: 'Respondendo a Lia',
              excerpt: 'Oi',
              color: AppColors.primary,
              cancelLabel: 'Cancelar resposta',
              onCancel: _noop,
            ),
          ),
        ),
      );

      double opacity() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('Respondendo a Lia'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;

      expect(opacity(), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
    });
  });

  group('date chip', () {
    testWidgets('shows the day label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CommentDateChip(label: '16 de novembro')),
        ),
      );
      expect(find.text('16 de novembro'), findsOneWidget);
    });
  });
}
