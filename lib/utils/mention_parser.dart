/// Finds [mention] only when it is standalone, not a prefix of a longer word.
///
/// `@Bob` matches in `hi @Bob` and `@Bob.`, but not in `@Bobby` or `mail@Bob`.
int indexOfStandaloneMention(String content, String mention) {
  if (mention.isEmpty) return -1;

  var start = 0;
  while (true) {
    final index = content.indexOf(mention, start);
    if (index < 0) return -1;
    if (_isStandaloneMentionAt(content, index, mention.length)) {
      return index;
    }
    start = index + 1;
  }
}

/// Lowercases [input] and strips common Portuguese diacritics for accent- and
/// case-insensitive matching across mentions and living memory deduplication.
String foldPtAscii(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final codeUnit in lower.runes) {
    final ch = String.fromCharCode(codeUnit);
    switch (ch) {
      case 'á':
      case 'à':
      case 'â':
      case 'ã':
      case 'ä':
        buffer.write('a');
      case 'é':
      case 'è':
      case 'ê':
      case 'ë':
        buffer.write('e');
      case 'í':
      case 'ì':
      case 'î':
      case 'ï':
        buffer.write('i');
      case 'ó':
      case 'ò':
      case 'ô':
      case 'õ':
      case 'ö':
        buffer.write('o');
      case 'ú':
      case 'ù':
      case 'û':
      case 'ü':
        buffer.write('u');
      case 'ç':
        buffer.write('c');
      case 'ñ':
        buffer.write('n');
      default:
        buffer.writeCharCode(codeUnit);
    }
  }
  return buffer.toString();
}

/// Finds `@needle` inside [text] (case- and accent-insensitive), respecting
/// lexical boundaries so e-mails such as `user@domain.com` and prefixes such
/// as `@Bob` inside `@Bobby` do not match.
int? indexOfFoldedStandaloneMention(String text, String needle) {
  final trimmed = needle.trim();
  final cleanNeedle = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  if (cleanNeedle.isEmpty) return null;
  return _firstFoldedMentionPos(foldPtAscii(text), foldPtAscii(cleanNeedle));
}

/// Extracts all candidates mentioned in [text], ordered by first appearance.
///
/// Matches `@id` and `@name` (case- and accent-insensitive) first, and falls
/// back to a unique `@first_name` (minimum 3 characters) when unique across
/// [candidates]. Ignores email addresses such as `a@dominio.com`.
List<T> extractAllMentions<T>(
  String text,
  Iterable<T> candidates, {
  required String Function(T) idOf,
  required String Function(T) nameOf,
}) {
  if (text.isEmpty || !text.contains('@')) return const [];

  final candidateList = candidates.toList(growable: false);
  if (candidateList.isEmpty) return const [];

  final foldedText = foldPtAscii(text);

  final firstWords = <String?>[];
  final firstWordCounts = <String, int>{};
  for (final candidate in candidateList) {
    final foldedName = foldPtAscii(nameOf(candidate).trim());
    final firstWord = foldedName.isEmpty
        ? ''
        : foldedName
            .split(RegExp(r'\s+'))
            .firstWhere((w) => w.isNotEmpty, orElse: () => '');
    final validFirst = firstWord.length >= 3 ? firstWord : null;
    firstWords.add(validFirst);
    if (validFirst != null) {
      firstWordCounts[validFirst] = (firstWordCounts[validFirst] ?? 0) + 1;
    }
  }

  final found = <({int pos, int order, T candidate})>[];
  for (var i = 0; i < candidateList.length; i++) {
    final candidate = candidateList[i];
    final foldedId = foldPtAscii(idOf(candidate).trim());
    final foldedName = foldPtAscii(nameOf(candidate).trim());

    int? bestPos;
    for (final needle in {foldedId, foldedName}) {
      if (needle.isEmpty) continue;
      final cleanNeedle = needle.startsWith('@') ? needle.substring(1) : needle;
      final idx = _firstFoldedMentionPos(foldedText, cleanNeedle);
      if (idx != null && (bestPos == null || idx < bestPos)) {
        bestPos = idx;
      }
    }

    if (bestPos == null) {
      final firstWord = firstWords[i];
      if (firstWord != null && (firstWordCounts[firstWord] ?? 0) == 1) {
        bestPos = _firstFoldedMentionPos(foldedText, firstWord);
      }
    }

    if (bestPos != null) {
      found.add((pos: bestPos, order: i, candidate: candidate));
    }
  }

  found.sort((a, b) {
    final byPos = a.pos.compareTo(b.pos);
    return byPos != 0 ? byPos : a.order.compareTo(b.order);
  });
  return [for (final item in found) item.candidate];
}

int? _firstFoldedMentionPos(String foldedText, String foldedNeedle) {
  if (foldedNeedle.isEmpty) return null;
  final pattern = '@$foldedNeedle';
  var searchFrom = 0;
  while (true) {
    final start = foldedText.indexOf(pattern, searchFrom);
    if (start < 0) return null;
    final end = start + pattern.length;
    final prevOk = start == 0 || !_isFoldedWordChar(foldedText[start - 1]);
    final nextOk =
        end == foldedText.length || !_isFoldedWordChar(foldedText[end]);
    if (prevOk && nextOk) {
      return start;
    }
    searchFrom = end;
  }
}

final RegExp _unicodeWordChar = RegExp(r'^[\p{L}\p{N}_]$', unicode: true);

bool _isFoldedWordChar(String ch) => _unicodeWordChar.hasMatch(ch);

bool _isStandaloneMentionAt(String content, int index, int length) {
  if (index > 0 && !_isMentionBoundary(content[index - 1])) {
    return false;
  }
  final end = index + length;
  if (end < content.length && !_isMentionBoundary(content[end])) {
    return false;
  }
  return true;
}

bool _isMentionBoundary(String character) {
  if (character.trim().isEmpty) return true;
  return _mentionPunctuation.contains(character);
}

const _mentionPunctuation =
    r'''!"#$%&'()*+,-./:;<=>?@[\]^`{|}~，。！？；：（）【】《》、“”‘’…—''';
