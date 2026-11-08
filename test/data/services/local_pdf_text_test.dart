import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/local_pdf_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads the text layer page by page without a model', () async {
    final bytes = File('test/fixtures/f9/c38.pdf').readAsBytesSync();
    final pages = await readLocalPdfPages(bytes);
    expect(pages, isNotNull);
    expect(pages!.pages.first.number, 1);
    expect(pages.hasSelectableText, isTrue);
    expect(pages.pages.length, 4);
    expect(pages.pages[1].text, 'No trimestre anterior, foram vendidas 120 unidades.');
    for (final p in pages.pages) {
      expect(p.text, isNot(contains('\n')));
    }
  });

  test('a file that is not a PDF gives null instead of throwing', () async {
    expect(await readLocalPdfPages(Uint8List.fromList([1, 2, 3])), isNull);
  });

  ({String text, Rect box}) line(String t, double x, double y,
          {double w = 100, double h = 20}) =>
      (text: t, box: Rect.fromLTWH(x, y, w, h));

  test('table cells on one row are joined, rows stay in order', () {
    // ML Kit gives the label column first, then the value column.
    final out = joinLinesByRow([
      line('Servico', 0, 100),
      line('Manutencao', 0, 140),
      line('Valor', 300, 60),
      line('Item', 0, 60),
      line('1.200,00', 300, 100),
      line('450,75', 300, 140),
    ], fallback: 'x');
    expect(out, 'Item Valor\nServico 1.200,00\nManutencao 450,75');
  });

  test('a page of tall (rotated) lines keeps the plain text', () {
    final out = joinLinesByRow([
      line('a', 0, 0, w: 20, h: 100),
      line('b', 40, 0, w: 20, h: 100),
    ], fallback: 'plain');
    expect(out, 'plain');
    expect(joinLinesByRow([], fallback: 'none'), 'none');
  });

  test('a page without a text layer is rendered and read by OCR', () async {
    final bytes = File('test/fixtures/f9/c39.pdf').readAsBytesSync();
    final seen = <Uint8List>[];
    final pages = await readLocalPdfPages(bytes, ocr: (png) async {
      seen.add(png);
      return 'Texto\n  lido   por OCR';
    });
    expect(pages!.pages.single.text, 'Texto lido por OCR');
    expect(seen.single.take(4), [0x89, 0x50, 0x4E, 0x47]); // PNG signature
  });

  test('pages with text are not sent to OCR', () async {
    final bytes = File('test/fixtures/f9/c38.pdf').readAsBytesSync();
    var calls = 0;
    final pages = await readLocalPdfPages(bytes, ocr: (png) async {
      calls++;
      return 'x';
    });
    expect(calls, 0);
    expect(pages!.pages[0].text, 'Relatório trimestral.');
  });

  test('an OCR failure leaves that page empty instead of losing the file',
      () async {
    final bytes = File('test/fixtures/f9/c39.pdf').readAsBytesSync();
    final pages = await readLocalPdfPages(bytes, ocr: (png) async {
      throw StateError('ocr down');
    });
    expect(pages, isNotNull);
    expect(pages!.pages.single.text, isEmpty);
  });
}
