import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/document_chart_renderer.dart';
import 'package:memex/domain/models/document_chart.dart';

const _block = '```chart\n{"title":"Custos","labels":["A","B"],"values":[10,12.5]}\n```';

void main() {
  test('reads a valid block and refuses malformed ones', () {
    final c = findChartBlocks('# T\n\n$_block\n').single.chart!;
    expect(c.labels, ['A', 'B']);
    expect(c.values, [10, 12.5]);
    for (final bad in [
      '{"labels":["A"],"values":[1,2]}',
      '{"labels":[],"values":[]}',
      '{"labels":["A"],"values":["x"]}',
      'not json',
    ]) {
      expect(DocumentChart.tryParse(bad), isNull, reason: bad);
    }
    expect(
      DocumentChart.tryParse(
          '{"labels":[${List.filled(13, '"a"').join(',')}],"values":[${List.filled(13, '1').join(',')}]}'),
      isNull,
    );
  });

  test('values missing from the sources are flagged, comma decimals accepted',
      () {
    expect(unverifiedCharts(_block, 'custo A: 10 e B: 12,5'), isEmpty);
    expect(unverifiedCharts(_block, 'custo A: 10 apenas'), ['chart:12.5']);
    expect(unverifiedCharts(_block, 'A 100 e B 12.5'), ['chart:10']);
    expect(unverifiedCharts('```chart\nlixo\n```', ''), ['chart:invalid']);
  });

  testWidgets('a chart becomes an inline png and an unreadable one stays',
      (tester) async {
    final out = (await tester.runAsync(
        () => expandCharts('a\n$_block\nb\n```chart\nlixo\n```')))!;
    expect(out, contains('![Custos](data:image/png;base64,iVBOR'));
    expect(out, contains('```chart\nlixo\n```'));
    expect(out, isNot(contains('"values"')));
  });

  test('record photos: only images the record holds are accepted', () {
    const md = 'x\n```image\n{"asset":"a/1.jpg","caption":"Quadro"}\n```\n'
        '```image\n{"asset":"b/2.jpg"}\n```\n```image\nlixo\n```';
    final blocks = findImageBlocks(md);
    expect(blocks.map((b) => b.asset), ['a/1.jpg', 'b/2.jpg', null]);
    expect(blocks.first.caption, 'Quadro');
    expect(
      unverifiedImages(md, {'a/1.jpg'}),
      ['image:b/2.jpg', 'image:invalid'],
    );
  });
}
