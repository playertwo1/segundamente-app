import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/use_cases/card_task_extractor.dart';

CardDetailModel _detail({
  String rawContent = '',
  List<UiConfig> uiConfigs = const [],
}) {
  return CardDetailModel(
    id: 'card-1',
    title: 'Registro',
    timestamp: DateTime(2026, 11, 17),
    address: '',
    tags: const [],
    rawContent: rawContent,
    insight: InsightData(text: '', relatedCards: const [], comments: const []),
    assets: const [],
    uiConfigs: uiConfigs,
  );
}

UiConfig _config(String templateId, Map<String, dynamic> data) =>
    UiConfig(templateId: templateId, data: data);

void main() {
  test('reads bullet markers of every supported kind', () {
    final candidates = extractCardTaskCandidates(_detail(
      rawContent: '- Trocar o Parakeet\n'
          '* Melhorar o Todo\n'
          '• Terceira ideia\n'
          '– Quarta ideia',
    ));

    expect(candidates, [
      'Trocar o Parakeet',
      'Melhorar o Todo',
      'Terceira ideia',
      'Quarta ideia',
    ]);
  });

  test('reads numbered lists with dot and parenthesis', () {
    final candidates = extractCardTaskCandidates(_detail(
      rawContent: '1. Primeiro\n2) Segundo',
    ));

    expect(candidates, ['Primeiro', 'Segundo']);
  });

  test('reads checklist items open, done and upper case', () {
    final candidates = extractCardTaskCandidates(_detail(
      rawContent: '- [ ] Aberta\n- [x] Feita\n- [X] Maiuscula',
    ));

    expect(candidates, ['Aberta', 'Feita', 'Maiuscula']);
  });

  test('strips one trailing period or semicolon', () {
    final candidates = extractCardTaskCandidates(_detail(
      rawContent: '- Fazer X.\n- Fazer Y;\n- Fazer Z',
    ));

    expect(candidates, ['Fazer X', 'Fazer Y', 'Fazer Z']);
  });

  test('dedupes case-insensitively keeping first order', () {
    final candidates = extractCardTaskCandidates(_detail(
      rawContent: '- Ideia\n- Outra\n- ideia',
    ));

    expect(candidates, ['Ideia', 'Outra']);
  });

  test('skips links and paths', () {
    final candidates = extractCardTaskCandidates(_detail(
      rawContent: '- https://exemplo.com\n'
          '- HTTP://exemplo.com\n'
          '- fs://abc/def.jpg\n'
          '- file:///tmp/x\n'
          '- /tmp/x\n'
          '- Algo util',
    ));

    expect(candidates, ['Algo util']);
  });

  test('skips image lists', () {
    final candidates = extractCardTaskCandidates(_detail(
      uiConfigs: [
        _config('image_gallery', {
          'images': ['fs://a.jpg', 'fs://b.jpg'],
        }),
      ],
    ));

    expect(candidates, isEmpty);
  });

  test('caps the result at ten candidates', () {
    final raw = [for (var i = 1; i <= 12; i++) '- Item $i'].join('\n');

    final candidates = extractCardTaskCandidates(_detail(rawContent: raw));

    expect(candidates, hasLength(10));
    expect(candidates.first, 'Item 1');
    expect(candidates.last, 'Item 10');
  });

  test('skips candidates longer than 200 characters', () {
    final long = 'a' * 201;
    final fits = 'b' * 200;

    final candidates = extractCardTaskCandidates(_detail(
      rawContent: '- $long\n- $fits',
    ));

    expect(candidates, [fits]);
  });

  test('walks nested maps and lists of uiConfigs', () {
    final candidates = extractCardTaskCandidates(_detail(
      uiConfigs: [
        _config('classic_card', {
          'section': {
            'points': ['Primeiro', '- Segundo', 'https://x.com'],
          },
          'blocks': [
            {'text': '- Quarto'},
          ],
        }),
      ],
    ));

    expect(candidates, ['Primeiro', 'Segundo', 'Quarto']);
  });

  test('reads task lists under a case-insensitive key', () {
    final candidates = extractCardTaskCandidates(_detail(
      uiConfigs: [
        _config('classic_card', {
          'Items': ['- Um', 'Dois'],
        }),
      ],
    ));

    expect(candidates, ['Um', 'Dois']);
  });

  test('ignores audio_card templates', () {
    final candidates = extractCardTaskCandidates(_detail(
      uiConfigs: [
        _config('audio_card', {
          'items': ['Nao deve aparecer'],
          'transcript': '- Tambem nao',
        }),
      ],
    ));

    expect(candidates, isEmpty);
  });

  test('returns nothing when there is no list', () {
    final candidates = extractCardTaskCandidates(_detail(
      rawContent: 'Texto simples sem lista.',
    ));

    expect(candidates, isEmpty);
  });
}
