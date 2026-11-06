import 'dart:math' as math;

double cosineSimilarity(List<num> left, List<num> right) {
  if (left.length != right.length) {
    throw ArgumentError('Embedding dimensions do not match');
  }
  if (left.isEmpty) return 0;

  var dot = 0.0;
  var leftNorm = 0.0;
  var rightNorm = 0.0;
  for (var i = 0; i < left.length; i++) {
    final a = left[i].toDouble();
    final b = right[i].toDouble();
    if (!a.isFinite || !b.isFinite) {
      throw ArgumentError('Embeddings must contain finite values');
    }
    dot += a * b;
    leftNorm += a * a;
    rightNorm += b * b;
  }
  if (leftNorm == 0 || rightNorm == 0) return 0;
  return (dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm)))
      .clamp(-1.0, 1.0)
      .toDouble();
}

List<({T item, double score})> rankBySimilarity<T>(
  List<num> query,
  Iterable<({T item, List<num> vector})> candidates, {
  required double cutoff,
  required int limit,
}) {
  if (!cutoff.isFinite || cutoff < -1 || cutoff > 1) {
    throw ArgumentError.value(cutoff, 'cutoff', 'must be between -1 and 1');
  }
  if (limit < 0) throw ArgumentError.value(limit, 'limit', 'must be >= 0');

  final ranked = <({T item, double score})>[];
  for (final candidate in candidates) {
    final score = cosineSimilarity(query, candidate.vector);
    if (score >= cutoff) ranked.add((item: candidate.item, score: score));
  }
  ranked.sort((a, b) => b.score.compareTo(a.score));
  return ranked.take(limit).toList();
}
