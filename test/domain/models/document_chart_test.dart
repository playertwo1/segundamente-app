import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as image_codec;
import 'package:memex/data/services/document_chart_renderer.dart';
import 'package:memex/domain/models/document_chart.dart';
import 'package:memex/utils/user_storage.dart';

const _block = '```chart\n{"title":"Custos","labels":["A","B"],'
    '"values":[10,12.5],"unit":"R\$"}\n```';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('reads a valid block and refuses malformed ones', () {
    final c = findChartBlocks('# T\n\n$_block\n').single.chart!;
    expect(c.labels, ['A', 'B']);
    expect(c.values, [10, 12.5]);
    expect(c.unit, 'R\$');
    expect(
      findChartBlocks(_block.replaceAll('\n', '\r\n')).single.chart!.values,
      [10, 12.5],
    );
    for (final bad in [
      '{"labels":["A"],"values":[1,2]}',
      '{"labels":[],"values":[]}',
      '{"labels":["A"],"values":["x"]}',
      '{"labels":["A"],"values":[1],"unit":7}',
      '{"labels":["A"],"values":[1],"unit":"${List.filled(25, "x").join()}"}',
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

  testWidgets('chart raster is print-ready at the PDF export size',
      (tester) async {
    final bytes = await tester.runAsync(
      () => renderChartPng(
        const DocumentChart(
          title: 'Unidades vendidas',
          labels: ['T1', 'T2', 'T3', 'T4'],
          values: [80, 95, 120, 150],
          unit: 'unidades',
        ),
      ),
    );
    final image = image_codec.decodePng(Uint8List.fromList(bytes!));
    expect((image!.width, image.height), (2016, 1134));
    for (final x in [462, 892, 1321, 1751]) {
      final bar = image.getPixel(x, 840);
      // The document accent blue.
      expect((bar.r, bar.g, bar.b), (31, 78, 121));
    }
  });

  testWidgets('a negative bar uses a second tone', (tester) async {
    final bytes = await tester.runAsync(
      () => renderChartPng(
        const DocumentChart(
          title: 'Variação',
          labels: ['A', 'B'],
          values: [12, -8],
        ),
      ),
    );
    final image = image_codec.decodePng(Uint8List.fromList(bytes!))!;
    var accent = 0, negative = 0;
    for (final px in image) {
      if ((px.r, px.g, px.b) == (31, 78, 121)) accent++;
      if ((px.r, px.g, px.b) == (194, 65, 12)) negative++;
    }
    expect(accent, greaterThan(10000));
    expect(negative, greaterThan(10000));
  });

  test('values missing from the sources are flagged, comma decimals accepted',
      () {
    expect(unverifiedCharts(_block, 'custo A: 10 e B: 12,5'), isEmpty);
    expect(unverifiedCharts(_block, 'custo A: 10 apenas'), ['chart:12.5']);
    expect(unverifiedCharts(_block, 'A 100 e B 12.5'), ['chart:10']);
    expect(unverifiedCharts('```chart\nlixo\n```', ''), ['chart:invalid']);
  });

  test('chart labels use the active language decimal separator', () {
    expect(formatChartValue(12.5, languageCode: 'pt'), '12,5');
    expect(formatChartValue(12.5, languageCode: 'en'), '12.5');
  });

  testWidgets('a chart becomes an inline png and an unreadable one stays',
      (tester) async {
    final out = (await tester
        .runAsync(() => expandCharts('a\n$_block\nb\n```chart\nlixo\n```')))!;
    expect(out, contains('![Custos](data:image/png;base64,iVBOR'));
    final expectedData = UserStorage.localeNotifier.value.languageCode == 'pt'
        ? 'Figura 1. Custos. Dados (R\$): A: 10; B: 12,5.'
        : 'Figure 1. Custos. Data (R\$): A: 10; B: 12.5.';
    expect(out, contains(expectedData));
    expect(out, contains('```chart\nlixo\n```'));
    expect(out, isNot(contains('"values"')));
  });

  testWidgets('negative chart values are labeled after the bar end',
      (tester) async {
    final bytes = await tester.runAsync(
      () => renderChartPng(
        const DocumentChart(
          title: 'Saldo',
          labels: ['Mês 1'],
          values: [-20],
          unit: 'R\$',
        ),
      ),
    );
    final image = image_codec.decodePng(Uint8List.fromList(bytes!))!;
    var darkPixels = 0;
    for (var y = 850; y < 925; y++) {
      for (var x = 1030; x < 1180; x++) {
        final pixel = image.getPixel(x, y);
        if (pixel.r < 100 && pixel.g < 100 && pixel.b < 100) darkPixels++;
      }
    }
    expect(darkPixels, greaterThan(0));
  });

  test('record photos: only images the record holds are accepted', () {
    const md = 'x\n```image\n{"asset":"a/1.jpg","caption":"Quadro"}\n```\n'
        '```image\n{"asset":"b/2.jpg"}\n```\n```image\nlixo\n```';
    final blocks = findImageBlocks(md);
    expect(blocks.map((b) => b.asset), ['a/1.jpg', 'b/2.jpg', null]);
    expect(
      findImageBlocks('```image\r\n{"asset":"a/1.jpg","caption":"Q"}\r\n```')
          .single
          .asset,
      'a/1.jpg',
    );
    expect(blocks.first.caption, 'Quadro');
    expect(
      unverifiedImages(md, {'a/1.jpg'}),
      ['image:b/2.jpg', 'image:invalid'],
    );
  });

  test('a photo written as markdown becomes the image block, others stay', () {
    const md = 'a\n![Quadro](Facts/assets/a.jpg)\n![x](http://x/y.png)\n';
    final out = imageMarkdownToBlocks(md, {'Facts/assets/a.jpg'});
    expect(findImageBlocks(out).single.asset, 'Facts/assets/a.jpg');
    expect(findImageBlocks(out).single.caption, 'Quadro');
    expect(out, contains('![x](http://x/y.png)'));
    expect(unverifiedImages(out, {'Facts/assets/a.jpg'}), isEmpty);
  });
}
