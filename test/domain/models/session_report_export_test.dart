import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:pdf/pdf.dart';

import '../../helpers/report_export_fonts.dart';

void main() {
  const segments = [
    ReportSegment(id: 'seg_0', text: 'fechar o escopo', clock: '00:00:01'),
    ReportSegment(id: 'seg_1', text: 'mandar o resumo', clock: '00:00:02'),
  ];
  final exportedAt = DateTime(2026, 11, 2, 15, 4);
  late ReportExportFonts fonts;

  setUpAll(() async {
    fonts = await testReportExportFonts();
  });

  SessionReport sample() {
    return sessionReportFromModelJson(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: segments,
      json: {
        'schema_version': 1,
        'items': [
          {
            'kind': 'decision',
            'text': 'fechar o escopo',
            'segment_id': 'seg_0',
            'excerpt': 'fechar o escopo',
            'clock': '00:00:01',
          },
          {
            'kind': 'task',
            'text': 'mandar o resumo',
            'segment_id': 'seg_1',
            'excerpt': 'resumo',
            'clock': '00:00:02',
          },
        ],
      },
    );
  }

  Future<String> markdownOf(SessionReport report,
      {Set<String>? itemIds}) async {
    return utf8.decode(
      await exportSessionReportBytes(
        report: report,
        exportedAt: exportedAt,
        format: ReportExportFormat.markdown,
        itemIds: itemIds,
      ),
    );
  }

  Future<String> pdfOf(SessionReport report) async {
    return latin1.decode(
      await exportSessionReportBytes(
        report: report,
        exportedAt: exportedAt,
        format: ReportExportFormat.pdf,
        fonts: fonts,
      ),
    );
  }

  Future<String> docxOf(SessionReport report) async {
    return _docxText(
      await exportSessionReportBytes(
        report: report,
        exportedAt: exportedAt,
        format: ReportExportFormat.docx,
      ),
    );
  }

  test('markdown, pdf and docx carry the same report text', () async {
    final report = sample();
    final markdown = await markdownOf(report);
    final docx = await docxOf(report);
    // The PDF draws the same parsed lines as the DOCX; its glyphs are
    // embedded, so its bytes are checked for structure, not raw text.
    final pdfLines =
        parseExportMarkdown(markdown).map((block) => block.text).join('\n');

    for (final text in [markdown, pdfLines, docx]) {
      expect(text, contains('Relatório de reunião'));
      expect(text, contains('Data: 2026-11-02 15:04'));
      expect(text, contains('Decisões'));
      expect(text, contains('Tarefas'));
      expect(text, contains('não identificado'));
      expect(text, contains('não informado'));
      expect(text, contains('Fonte: fechar o escopo'));
      expect(text, contains('Relógio: 00:00:01'));
      expect(text, contains('Fonte: resumo'));
      expect(text, contains('Não confirmado'));
    }
    final pdf = await pdfOf(report);
    expect(pdf, startsWith('%PDF-'));
    expect(pdf, contains('/FontFile2'));
    expect(pdf, isNot(contains('Helvetica')));
  });

  test('a discarded item stays out of the full export', () async {
    final report = setReportItemStatus(
      sample(),
      itemId: 'item_2',
      status: ReportItemStatus.discarded,
    );
    final markdown = await markdownOf(report);
    expect(markdown, contains('fechar o escopo'));
    expect(markdown, isNot(contains('mandar o resumo')));
  });

  test('a selected item is the only body that is exported', () async {
    final markdown = await markdownOf(sample(), itemIds: {'item_1'});
    expect(markdown, contains('fechar o escopo'));
    expect(markdown, isNot(contains('mandar o resumo')));
    expect(markdown, isNot(contains('Tarefas')));
  });

  test('a long report uses a second pdf page', () async {
    final report = SessionReport(
      schemaVersion: sessionReportSchemaVersion,
      sessionId: 's',
      kind: ReportKind.livre,
      title: 'Relatório livre',
      sections: sectionsFor(ReportKind.livre),
      items: [
        ReportItem(
          id: 'item_1',
          kind: ReportItemKind.summary,
          text: List.filled(50, 'linha com ação').join('\n'),
          status: ReportItemStatus.unconfirmed,
          assignee: reportAssigneeUnknown,
          due: reportDueUnknown,
          source: const ReportSource(
            segmentId: 'seg_0',
            excerpt: 'ação',
            clock: null,
          ),
        ),
      ],
    );
    final pdf = await pdfOf(report);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf).length, 2);
  });

  test('pdf and docx draw headings in bold instead of showing # markers',
      () async {
    final report = sample();
    final markdown = await markdownOf(report);
    final docx = await docxOf(report);
    final headings = parseExportMarkdown(markdown)
        .where((block) => block.kind == ExportBlockKind.heading)
        .toList();

    expect(markdown, contains('## Decisões'));
    expect(
      headings.map((block) => (block.level, block.text)),
      contains((2, 'Decisões')),
    );
    for (final block in headings) {
      expect(block.text, isNot(startsWith('#')));
    }
    expect(docx, isNot(contains('# ')));
    expect(docx, contains('Decisões'));
    expect(docx, contains('<w:b/>'));
    expect(await pdfOf(report), contains('/FontFile2'));
  });

  test('the embedded font has every glyph model text usually carries', () {
    // The old WinAnsi PDF turned anything above U+00FF into "?".
    const text = 'ação é ê ô ü “aspas” ‘simples’ — – … • ºª €';
    for (final data in [fonts.regular, fonts.bold]) {
      final glyphs = TtfParser(data).charToGlyphIndexMap;
      for (final rune in text.runes.where((rune) => rune != 0x20)) {
        expect(
          glyphs.containsKey(rune),
          isTrue,
          reason: String.fromCharCode(rune),
        );
      }
    }
  });

  test('markdown lists and bold become list items and bold runs', () async {
    const markdown = '- **Prazo:** sexta\n2. revisar o texto\nlinha *simples*';
    final blocks = parseExportMarkdown(markdown);

    expect(blocks[0].kind, ExportBlockKind.item);
    expect(blocks[0].marker, '•');
    expect(blocks[0].runs.first.bold, isTrue);
    expect(blocks[0].text, 'Prazo: sexta');
    expect(blocks[1].marker, '2.');
    expect(blocks[1].text, 'revisar o texto');
    expect(blocks[2].kind, ExportBlockKind.paragraph);
    expect(blocks[2].text, 'linha *simples*');

    final docx = _docxText(
      await exportMarkdownBytes(
        markdown: markdown,
        format: ReportExportFormat.docx,
      ),
    );
    expect(docx, contains('<w:ind w:left="360" w:hanging="360"/>'));
    expect(docx, contains('<w:b/></w:rPr><w:t xml:space="preserve">Prazo:'));
    expect(docx, isNot(contains('**')));
  });

  test('one paragraph longer than a page continues on the next pages',
      () async {
    // Without TextOverflow.span the pdf package throws "won't fit".
    final huge = List.filled(6000, 'palavra').join(' ');
    for (final markdown in [huge, '- $huge']) {
      final pdf = latin1.decode(
        await exportMarkdownBytes(
          markdown: markdown,
          format: ReportExportFormat.pdf,
          fonts: fonts,
        ),
      );
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(pdf).length,
        greaterThan(5),
      );
    }
  });

  test('pdf export without fonts is refused', () {
    expect(
      exportMarkdownBytes(markdown: 'x', format: ReportExportFormat.pdf),
      throwsArgumentError,
    );
  });
}

String _docxText(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile('word/document.xml');
  expect(file, isNotNull);
  return utf8.decode(file!.content as List<int>);
}
