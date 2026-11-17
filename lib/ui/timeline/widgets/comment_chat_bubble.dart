import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/themes/app_text_styles.dart';
import 'package:memex/ui/timeline/widgets/comment_thread_entries.dart';

const Cubic _chatCurve = Cubic(0.16, 1, 0.3, 1);
const double _swipeThreshold = 56;
const double _swipeMax = 72;

/// Palette index for a persona. The same character id always gets the same
/// color, so the color never depends on the order of the thread.
int commentPersonaIndex(String? characterId) {
  var hash = 0;
  for (final unit in (characterId ?? '').codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash % AppColors.chatPersonaLight.length;
}

/// Name color of an author on the dark bubble: ivory for the user.
Color commentAuthorColor({required bool isUser, String? characterId}) => isUser
    ? AppColors.chatBubbleUser
    : AppColors.chatPersonaLight[commentPersonaIndex(characterId)];

/// One message of the record thread, drawn as a chat bubble.
///
/// Personas sit on the left with an avatar; the user sits on the right. A
/// horizontal swipe to the right or a tap calls [onReply]. A null [onReply]
/// means no reply affordance (the pinned insight).
class CommentChatBubble extends StatefulWidget {
  final bool isUser;
  final String content;
  final DateTime time;

  /// Persona name, shown only when [showHeader] is true.
  final String? authorName;

  /// Persona id: picks the color.
  final String? characterId;

  /// Persona avatar, 30dp. Ignored when [showHeader] is false; the slot stays empty.
  final Widget? avatar;

  final bool showHeader;
  final CommentQuote? quote;

  /// Called with the quoted message id. Only called when the quote has a target.
  final ValueChanged<String>? onQuoteTap;

  final VoidCallback? onReply;

  /// Label of the Semantics custom action that replies (TalkBack).
  final String? replyLabel;

  /// Plays the entrance animation on mount.
  final bool animateIn;

  /// Each increase plays the highlight flash of a quoted target.
  final int flashSignal;

  const CommentChatBubble({
    super.key,
    required this.isUser,
    required this.content,
    required this.time,
    this.authorName,
    this.characterId,
    this.avatar,
    this.showHeader = true,
    this.quote,
    this.onQuoteTap,
    this.onReply,
    this.replyLabel,
    this.animateIn = false,
    this.flashSignal = 0,
  });

  @override
  State<CommentChatBubble> createState() => _CommentChatBubbleState();
}

class _CommentChatBubbleState extends State<CommentChatBubble>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final CurvedAnimation _enterCurve;
  late final AnimationController _flash;
  late final AnimationController _pulse;
  late final AnimationController _spring;
  late final CurvedAnimation _springCurve;

  bool _introduced = false;
  double _dx = 0; // finger offset while dragging
  double _springFrom = 0; // offset where the spring-back starts
  bool _armed = false; // threshold already crossed in this drag

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.animateIn ? 0 : 1,
    );
    _enterCurve = CurvedAnimation(parent: _enter, curve: _chatCurve);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _springCurve = CurvedAnimation(parent: _spring, curve: _chatCurve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_introduced) return;
    _introduced = true;
    if (!widget.animateIn) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    _enter.duration = reduce
        ? const Duration(milliseconds: 150)
        : Duration(milliseconds: widget.isUser ? 320 : 300);
    _enter.forward();
  }

  @override
  void didUpdateWidget(CommentChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flashSignal != oldWidget.flashSignal && widget.flashSignal > 0) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _springCurve.dispose();
    _spring.dispose();
    _pulse.dispose();
    _flash.dispose();
    _enterCurve.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// Drawn horizontal offset: follows the finger, then springs back to 0.
  double get _offsetX =>
      _spring.isAnimating ? _springFrom * (1 - _springCurve.value) : _dx;

  void _onDragStart(DragStartDetails details) {
    final current = _offsetX;
    _spring.stop();
    setState(() {
      _dx = current;
      _armed = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_dx + details.delta.dx).clamp(0.0, _swipeMax).toDouble();
    if (!_armed && next >= _swipeThreshold) {
      _armed = true;
      HapticFeedback.selectionClick();
      if (!MediaQuery.disableAnimationsOf(context)) _pulse.forward(from: 0);
    }
    setState(() => _dx = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final release = _dx;
    final reply = release >= _swipeThreshold;
    final reduce = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _dx = 0;
      if (!reduce && release > 0) {
        _springFrom = release;
        _spring.forward(from: 0);
      }
    });
    if (reply) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spring,
      builder: (context, _) {
        final reduce = MediaQuery.disableAnimationsOf(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final bubble = ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.8,
              ),
              child: _entrance(_bubbleBody(reduce), reduce),
            );
            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: widget.isUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (!widget.isUser) ...[
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: widget.showHeader ? widget.avatar : null,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(child: bubble),
              ],
            );
            return widget.onReply == null ? row : _swipe(row, reduce);
          },
        );
      },
    );
  }

  Widget _entrance(Widget child, bool reduce) {
    if (!widget.animateIn) return child;
    return AnimatedBuilder(
      animation: _enterCurve,
      child: child,
      builder: (context, child) {
        final t = _enterCurve.value;
        if (reduce) return Opacity(opacity: t, child: child);
        if (widget.isUser) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(14 * (1 - t), 28 * (1 - t)),
              child: Transform.scale(
                scale: 0.9 + 0.1 * t,
                alignment: Alignment.bottomRight,
                child: child,
              ),
            ),
          );
        }
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.88 + 0.12 * t,
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );
  }

  Widget _swipe(Widget row, bool reduce) {
    final dx = _offsetX;
    final action = widget.replyLabel == null
        ? null
        : {CustomSemanticsAction(label: widget.replyLabel!): widget.onReply!};
    return Semantics(
      customSemanticsActions: action,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onReply,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: reduce ? 8 : math.max(4, dx - 42),
              top: 0,
              bottom: 0,
              child: Center(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: (dx / _swipeThreshold).clamp(0.0, 1.0),
                    child: _replyIcon(),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(reduce ? 0 : dx, 0),
              child: row,
            ),
          ],
        ),
      ),
    );
  }

  Widget _replyIcon() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Transform.scale(
        // Pulse 1.3 -> 1 when the threshold is crossed; 1 at rest.
        scale: 1.3 + (1 - 1.3) * Curves.easeOut.transform(_pulse.value),
        child: child,
      ),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.chatReplyIconBg,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.reply_rounded,
          size: 16,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _bubbleBody(bool reduce) {
    final isUser = widget.isUser;
    final base =
        isUser ? AppColors.chatBubbleUser : AppColors.chatBubblePersona;
    final highlight =
        isUser ? AppColors.chatFlashUser : AppColors.chatFlashPersona;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isUser ? 18 : 6),
      topRight: Radius.circular(isUser ? 6 : 18),
      bottomLeft: const Radius.circular(18),
      bottomRight: const Radius.circular(18),
    );

    final children = <Widget>[];
    if (!isUser && widget.showHeader && widget.authorName != null) {
      children.add(
        Text(
          widget.authorName!,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: commentAuthorColor(
              isUser: false,
              characterId: widget.characterId,
            ),
          ),
        ),
      );
    }
    final quote = widget.quote;
    if (quote != null) {
      final targetId = quote.targetId;
      children.add(
        _CommentQuoteBlock(
          quote: quote,
          inUserBubble: isUser,
          onTap: targetId == null
              ? () {} // a missing target does nothing, and must not reply
              : () => widget.onQuoteTap?.call(targetId),
        ),
      );
    }
    children.add(
      isUser
          ? Text(
              widget.content,
              style: AppTextStyles.commentContent.copyWith(
                color: AppColors.chatUserText,
              ),
            )
          : MarkdownBody(
              data: widget.content,
              softLineBreak: true,
              styleSheet: _personaMarkdownStyle,
            ),
    );
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: 4));
      spaced.add(children[i]);
    }
    // Room for the time line, which sits at the bottom right.
    spaced.add(const SizedBox(height: 14));

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        // Reduced motion keeps the same color change, done within 150ms.
        final progress =
            reduce ? math.min(1.0, _flash.value * 900 / 150) : _flash.value;
        return Container(
          key: const ValueKey('comment_chat_bubble_body'),
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 5),
          decoration: BoxDecoration(
            color:
                Color.lerp(highlight, base, Curves.easeOut.transform(progress)),
            borderRadius: radius,
          ),
          child: child,
        );
      },
      // The Stack takes the width of the content; the time is pinned to its
      // bottom right. No IntrinsicWidth: a code block scroll view cannot
      // report intrinsic sizes.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: spaced,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Text(
                DateFormat('HH:mm').format(widget.time),
                style: TextStyle(
                  fontSize: 11,
                  color: isUser
                      ? AppColors.chatUserTime
                      : AppColors.chatPersonaTime,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final MarkdownStyleSheet _personaMarkdownStyle = MarkdownStyleSheet(
    p: AppTextStyles.commentContent,
    strong: AppTextStyles.commentContent.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    listBullet: const TextStyle(color: AppColors.primary),
    code: const TextStyle(
      fontSize: 13,
      color: AppColors.textSecondary,
      backgroundColor: AppColors.background,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

/// The quoted message inside a bubble: a colored bar, its author and a
/// two-line excerpt.
class _CommentQuoteBlock extends StatelessWidget {
  final CommentQuote quote;
  final bool inUserBubble;
  final VoidCallback onTap;

  const _CommentQuoteBlock({
    required this.quote,
    required this.inUserBubble,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final index = commentPersonaIndex(quote.characterId);
    final Color accent;
    if (quote.isUser) {
      accent = inUserBubble ? AppColors.chatUserText : AppColors.chatBubbleUser;
    } else {
      accent = inUserBubble
          ? AppColors.chatPersonaDark[index]
          : AppColors.chatPersonaLight[index];
    }
    final text = quote.text?.trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: inUserBubble
              ? Colors.black.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        quote.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: accent,
                        ),
                      ),
                      if (text != null && text.isNotEmpty)
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: inUserBubble
                                ? AppColors.chatQuoteTextUser
                                : AppColors.chatQuoteTextPersona,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Day separator between messages of different days.
class CommentDateChip extends StatelessWidget {
  final String label;

  const CommentDateChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.chatBubblePersona,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.chatDateChipText,
          ),
        ),
      ),
    );
  }
}

/// The message being answered, shown above the composer. Fades in and rises 8dp.
class CommentReplyPreview extends StatelessWidget {
  final String title;
  final String? excerpt;
  final Color color;
  final String cancelLabel;
  final VoidCallback onCancel;

  const CommentReplyPreview({
    super.key,
    required this.title,
    required this.excerpt,
    required this.color,
    required this.cancelLabel,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final preview = excerpt?.trim();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: reduce ? 150 : 220),
      curve: _chatCurve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, reduce ? 0 : 8 * (1 - t)),
          child: child,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: color,
                            ),
                          ),
                          if (preview != null && preview.isNotEmpty)
                            Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: cancelLabel,
              onPressed: onCancel,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
