import 'package:memex/domain/models/card_detail_model.dart';

/// Messages from the same author within this window share one header.
const Duration commentGroupWindow = Duration(minutes: 10);

/// One row of the comment thread, in display order.
sealed class CommentThreadEntry {
  const CommentThreadEntry();
}

/// Separator for a local calendar day; [day] is that day at local midnight.
class CommentDateEntry extends CommentThreadEntry {
  final DateTime day;

  const CommentDateEntry(this.day);
}

class CommentMessageEntry extends CommentThreadEntry {
  final Comment comment;

  /// False when the previous message has the same author within the group window.
  final bool showHeader;

  final CommentQuote? quote;

  const CommentMessageEntry({
    required this.comment,
    required this.showHeader,
    this.quote,
  });

  bool get isUser => !comment.isAi;
}

/// The message a reply points to. [targetId] is null when that message is not
/// in the thread, so the quote shows only [authorName].
class CommentQuote {
  final String? targetId;
  final String authorName;
  final String? text;

  /// Persona id for the color; null for the user.
  final String? characterId;
  final bool isUser;

  const CommentQuote({
    required this.targetId,
    required this.authorName,
    required this.text,
    required this.characterId,
    required this.isUser,
  });
}

/// Turns the ordered comments into thread rows.
///
/// [pinned] is the card insight: it is not emitted as a row, but it takes
/// part in grouping, day separators and quote lookup (id `insight`). Comments
/// must be in chronological order.
List<CommentThreadEntry> buildCommentThreadEntries(
  List<Comment> comments, {
  Comment? pinned,
  required String aiFallbackName,
  required String youLabel,
}) {
  final targets = <String, Comment>{
    for (final c in comments) c.id: c,
    if (pinned != null) pinned.id: pinned,
  };
  final entries = <CommentThreadEntry>[];
  Comment? previous = pinned;
  for (final comment in comments) {
    final at = _timeOf(comment);
    if (previous == null || !_sameDay(_timeOf(previous), at)) {
      entries.add(CommentDateEntry(_startOfDay(at)));
    }
    final showHeader = previous == null ||
        _authorKey(previous) != _authorKey(comment) ||
        at.difference(_timeOf(previous)).abs() > commentGroupWindow;
    entries.add(CommentMessageEntry(
      comment: comment,
      showHeader: showHeader,
      quote: _resolveQuote(comment, targets, aiFallbackName, youLabel),
    ));
    previous = comment;
  }
  return entries;
}

CommentQuote? _resolveQuote(
  Comment comment,
  Map<String, Comment> targets,
  String aiFallbackName,
  String youLabel,
) {
  final replyId = comment.replyToId;
  final target = replyId == null ? null : targets[replyId];
  if (target != null) {
    final isUser = !target.isAi;
    return CommentQuote(
      targetId: target.id,
      authorName:
          isUser ? youLabel : (target.character?.name ?? aiFallbackName),
      text: target.content,
      characterId: isUser ? null : target.character?.id,
      isUser: isUser,
    );
  }
  final name = comment.replyToName;
  if (name == null) return null;
  return CommentQuote(
    targetId: null,
    authorName: name,
    text: null,
    characterId: null,
    isUser: false,
  );
}

DateTime _timeOf(Comment c) =>
    DateTime.fromMillisecondsSinceEpoch(c.timestamp * 1000);

DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _authorKey(Comment c) => c.isAi ? 'ai:${c.character?.id ?? ''}' : 'user';
