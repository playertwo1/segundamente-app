import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/semantic_text_embedder.dart';
import 'package:memex/data/services/unigram_tokenizer.dart';
import 'package:path/path.dart' as p;

void main() {
  test('mean pooling and normalization match the Python MiniLM reference',
      () async {
    final reference = jsonDecode(
      await File(
        p.join(
          'test',
          'data',
          'services',
          'fixtures',
          'minilm_python_reference.json',
        ),
      ).readAsString(),
    ) as Map<String, dynamic>;
    final ids = (reference['ids'] as List).cast<int>();
    final hidden = (reference['hidden_states'] as List).cast<num>();
    final expected = (reference['embedding'] as List).cast<num>();
    final tokenizer = UnigramTokenizer.fromJson(
      await File(
        p.join(
            'test', 'data', 'services', 'fixtures', 'unigram_tokenizer.json'),
      ).readAsString(),
    );
    List<int>? seenIds;
    final embedder = OnnxSemanticTextEmbedder(
      tokenizer: tokenizer,
      runHiddenState: (inputIds) async {
        seenIds = inputIds;
        return hidden;
      },
    );

    final vector = await embedder.embedTokenIds(ids);

    expect(seenIds, ids);
    expect(vector, hasLength(reference['dimension'] as int));
    for (var i = 0; i < vector.length; i++) {
      expect(vector[i], closeTo(expected[i].toDouble(), 1e-6),
          reason: 'dim $i');
    }
    expect(vector.fold<double>(0, (sum, value) => sum + value * value),
        closeTo(1, 1e-6));
    await embedder.close();
  });

  test('invalid hidden state shape is rejected', () {
    expect(() => meanPoolAndNormalize([1, 2, 3], 2), throwsArgumentError);
  });
}
