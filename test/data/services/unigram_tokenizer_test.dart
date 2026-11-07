import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/unigram_tokenizer.dart';
import 'package:path/path.dart' as p;

void main() {
  test('synthetic Unigram vocabulary encodes whitespace-delimited text',
      () async {
    final json = await File(
      p.join('test', 'data', 'services', 'fixtures', 'unigram_tokenizer.json'),
    ).readAsString();
    final tokenizer = UnigramTokenizer.fromJson(json);

    expect(tokenizer.encode('olá mundo'), [0, 4, 5, 2]);
    expect(tokenizer.encode('olá mundo', maxTokens: 3), [0, 4, 2]);
    expect(tokenizer.encode(''), [0, 2]);
    expect(() => tokenizer.encode('olá', maxTokens: 1), throwsArgumentError);
  });

  test('real tokenizer IDs match the checked Python reference', () async {
    final path = Platform.environment['F610_TOKENIZER_JSON'] ??
        p.join(
          Directory.systemTemp.path,
          'f610',
          'm',
          'paraphrase-multilingual-MiniLM-L12-v2',
          'tokenizer.json',
        );
    final file = File(path);
    if (!await file.exists()) {
      markTestSkipped('F6-10 tokenizer.json is not downloaded on this machine');
      return;
    }

    final tokenizer = await UnigramTokenizer.fromFile(path);
    const text = 'A equipe adiou a publicação por falta de revisão';
    expect(
      tokenizer.encode(text),
      [0, 62, 33980, 20655, 796, 10, 169113, 196, 9829, 8, 456, 75801, 2],
    );
  });

  test('fixture remains valid JSON', () async {
    final json = await File(
      p.join('test', 'data', 'services', 'fixtures', 'unigram_tokenizer.json'),
    ).readAsString();
    expect(jsonDecode(json), isA<Map<String, dynamic>>());
  });
}
