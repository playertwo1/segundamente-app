import 'dart:convert';
import 'dart:io';

class UnigramTokenizer {
  UnigramTokenizer._(this._pieces, this._scores, this._unkId, this._maxLen);

  final Map<String, int> _pieces;
  final List<double> _scores;
  final int _unkId;
  final int _maxLen;

  static const bos = 0;
  static const eos = 2;

  static Future<UnigramTokenizer> fromFile(String path) async =>
      UnigramTokenizer.fromJson(await File(path).readAsString());

  factory UnigramTokenizer.fromJson(String json) {
    final root = jsonDecode(json);
    if (root is! Map<String, dynamic> || root['model'] is! Map) {
      throw const FormatException('Tokenizer model is missing');
    }
    final model = root['model'] as Map;
    final rawVocab = model['vocab'];
    final unkId = model['unk_id'];
    if (rawVocab is! List ||
        unkId is! int ||
        unkId < 0 ||
        unkId >= rawVocab.length) {
      throw const FormatException('Tokenizer vocabulary is invalid');
    }

    final pieces = <String, int>{};
    final scores = <double>[];
    var maxLen = 1;
    for (var i = 0; i < rawVocab.length; i++) {
      final row = rawVocab[i];
      if (row is! List ||
          row.length < 2 ||
          row[0] is! String ||
          row[1] is! num) {
        throw const FormatException('Tokenizer vocabulary entry is invalid');
      }
      final piece = row[0] as String;
      scores.add((row[1] as num).toDouble());
      pieces[piece] = i;
      if (piece.runes.length > maxLen) maxLen = piece.runes.length;
    }
    return UnigramTokenizer._(pieces, scores, unkId, maxLen);
  }

  /// Encodes XLM-R's SentencePiece Unigram vocabulary, including BOS/EOS.
  /// shortcut: skips the tokenizer's Precompiled NFKC charsmap; add that map if compatibility or decomposed text differs from SentencePiece.
  List<int> encode(String text, {int maxTokens = 128}) {
    if (maxTokens < 2) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be >= 2');
    }
    final words = text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final ids = <int>[];
    for (final word in words) {
      ids.addAll(_viterbi('\u2581$word'));
    }
    final body =
        ids.length > maxTokens - 2 ? ids.sublist(0, maxTokens - 2) : ids;
    return [bos, ...body, eos];
  }

  List<int> _viterbi(String word) {
    final runes = word.runes.toList();
    final best = List<double>.filled(runes.length + 1, double.negativeInfinity)
      ..[0] = 0;
    final from = List<int>.filled(runes.length + 1, -1);
    final pieceIds = List<int>.filled(runes.length + 1, -1);

    for (var start = 0; start < runes.length; start++) {
      if (best[start] == double.negativeInfinity) continue;
      var found = false;
      final piece = StringBuffer();
      for (var length = 1;
          length <= _maxLen && start + length <= runes.length;
          length++) {
        piece.writeCharCode(runes[start + length - 1]);
        final id = _pieces[piece.toString()];
        if (id == null || id == _unkId) continue;
        found = true;
        final score = best[start] + _scores[id];
        if (score > best[start + length]) {
          best[start + length] = score;
          from[start + length] = start;
          pieceIds[start + length] = id;
        }
      }
      if (!found) {
        final score = best[start] - 10;
        if (score > best[start + 1]) {
          best[start + 1] = score;
          from[start + 1] = start;
          pieceIds[start + 1] = _unkId;
        }
      }
    }

    final result = <int>[];
    for (var end = runes.length; end > 0; end = from[end]) {
      result.add(pieceIds[end]);
    }
    return result.reversed.toList();
  }
}
