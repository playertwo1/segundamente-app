import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/semantic_similarity.dart';

void main() {
  test('cosine similarity handles orthogonal and zero vectors', () {
    expect(cosineSimilarity([1, 0], [0, 1]), 0);
    expect(cosineSimilarity([0, 0], [1, 1]), 0);
    expect(cosineSimilarity([1, 1], [1, 1]), closeTo(1, 1e-12));
  });

  test('out of topic candidates below the cutoff return no results', () {
    final ranked = rankBySimilarity(
      [1, 0],
      [
        (item: 'unrelated A', vector: [0.1, 1]),
        (item: 'unrelated B', vector: [-1, 0]),
      ],
      cutoff: 0.4,
      limit: 3,
    );

    expect(ranked, isEmpty);
  });

  test('ranking is descending and observes the result limit', () {
    final ranked = rankBySimilarity(
      [1, 0],
      [
        (item: 'second', vector: [0.8, 0.6]),
        (item: 'first', vector: [0.9, 0.1]),
        (item: 'below', vector: [0.1, 1]),
      ],
      cutoff: 0.5,
      limit: 1,
    );

    expect(ranked.map((hit) => hit.item), ['first']);
  });

  test('the cutoff is inclusive at an exact score', () {
    final score = cosineSimilarity([1, 0], [0.4, 3]);
    final ranked = rankBySimilarity(
      [1, 0],
      [
        (item: 'boundary', vector: [0.4, 3])
      ],
      cutoff: score,
      limit: 1,
    );

    expect(ranked, hasLength(1));
    expect(ranked.single.item, 'boundary');
  });

  test('embedding dimension mismatch is rejected', () {
    expect(() => cosineSimilarity([1], [1, 0]), throwsArgumentError);
  });
}
