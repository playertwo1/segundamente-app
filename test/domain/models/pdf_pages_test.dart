import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/pdf_pages.dart';

void main() {
  test('reads a fenced reply and keeps page numbers as clock labels', () {
    final pages = parsePdfPagesReply(
      '```json\n{"pages":[{"page":1,"text":"Ata"},{"page":2,"text":""},'
      '{"page":3,"text":"Prazo: 15/10."}]}\n```',
      expectedPages: 3,
    );
    final segments = pages.toSegments();
    expect(segments.map((s) => s.clock), ['p.1', 'p.3']);
    expect(segments.map((s) => s.id), ['seg_0', 'seg_1']);
    expect(pages.hasSelectableText, isTrue);
  });

  test('a scanned PDF has no selectable text', () {
    final pages = parsePdfPagesReply('{"pages":[{"page":1,"text":"  "}]}');
    expect(pages.hasSelectableText, isFalse);
    expect(pages.toSegments(), isEmpty);
  });

  test('refuses replies that cannot be trusted', () {
    for (final bad in [
      'not json',
      '{"pages":[]}',
      '{"pages":[{"page":2,"text":"a"},{"page":1,"text":"b"}]}',
      '{"pages":[{"page":1,"text":"a"},{"page":1,"text":"b"}]}',
      '{"pages":[{"page":"1","text":"a"}]}',
      '{"pages":[{"page":1}]}',
    ]) {
      expect(() => parsePdfPagesReply(bad), throwsA(isA<Exception>()),
          reason: bad);
    }
    expect(
      () => parsePdfPagesReply('{"pages":[{"page":1,"text":"a"}]}',
          expectedPages: 2),
      throwsFormatException,
    );
  });

  test('only big files ask for another confirmation', () {
    expect(pdfNeedsSizeConfirmation(pdfConfirmBytes), isFalse);
    expect(pdfNeedsSizeConfirmation(pdfConfirmBytes + 1), isTrue);
  });
}
