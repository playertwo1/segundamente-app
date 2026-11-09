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

  test('pdf metadata includes the document title and creator', () async {
    final pdf = await pdfOf(sample());
    expect(pdf, contains('/Title'));
    expect(pdf, contains('/Creator'));
    expect(pdf, contains('Segunda Mente'));
  });

  test('markdown tables become formatted tables in PDF and DOCX', () async {
    const markdown = '# Resultados\n\n'
        '| Indicador | Base | Atual |\n'
        '|:---|---:|:---:|\n'
        '| **Custo** | R\$ 12,50 | R\$ 10,00 |\n'
        '| Taxa | 4 | 5 |';
    final table = parseExportMarkdown(markdown).singleWhere(
      (block) => block.kind == ExportBlockKind.table,
    );
    expect(table.tableRows, [
      ['Indicador', 'Base', 'Atual'],
      ['**Custo**', 'R\$ 12,50', 'R\$ 10,00'],
      ['Taxa', '4', '5'],
    ]);
    expect(table.tableAlignments, [
      ExportTableAlignment.left,
      ExportTableAlignment.right,
      ExportTableAlignment.center,
    ]);

    final pdf = latin1.decode(await exportMarkdownBytes(
      markdown: markdown,
      format: ReportExportFormat.pdf,
      fonts: fonts,
    ));
    expect(pdf, startsWith('%PDF-'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf), hasLength(1));

    final docx = _docxText(await exportMarkdownBytes(
      markdown: markdown,
      format: ReportExportFormat.docx,
    ));
    expect(docx, contains('<w:tbl>'));
    expect(docx, contains('<w:tblHeader/>'));
    expect(docx, contains('<w:jc w:val="right"/>'));
    expect(docx, contains('<w:jc w:val="center"/>'));
    expect(docx, contains('<w:t xml:space="preserve">Custo</w:t>'));
    expect(docx, isNot(contains('**')));
    expect(docx, contains('<w:insideH w:val="nil"/>'));
    expect(docx, contains('w:fill="F7F9FC"'));
    expect(
        docx,
        contains(
          '<w:tcBorders><w:bottom w:val="single" w:sz="8" w:color="1F4E79"/>',
        ));
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

  test('docx declares heading styles, language and document properties',
      () async {
    final bytes = await exportMarkdownBytes(
      markdown: '# Plano\n\n## Parte um\n\ntexto',
      format: ReportExportFormat.docx,
      languageCode: 'en',
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    String read(String name) =>
        utf8.decode(archive.findFile(name)!.content as List<int>);
    final doc = read('word/document.xml');
    expect(doc, contains('<w:pStyle w:val="Heading1"/>'));
    expect(doc, contains('<w:pStyle w:val="Heading2"/>'));
    expect(read('word/styles.xml'), contains('w:styleId="Heading1"'));
    expect(read('word/styles.xml'), contains('w:val="en-US"'));
    expect(read('docProps/core.xml'), contains('<dc:title>Plano</dc:title>'));
    expect(read('word/_rels/document.xml.rels'), contains('styles.xml'));
    expect(read('[Content_Types].xml'), contains('/word/styles.xml'));
    expect(read('_rels/.rels'), contains('docProps/core.xml'));
  });

  test(
      'a heading or image stays with the short text after it, long text does not',
      () async {
    final long = List.filled(80, 'palavra').join(' ');
    final blocks = parseExportMarkdown(
      '# Título\n\nabertura curta\n\n## Seção\n\n$long\n\n- item\n',
    );
    final groups = keepTogetherGroups(blocks);
    expect(groups.first.map((b) => b.kind), [
      ExportBlockKind.heading,
      ExportBlockKind.blank,
      ExportBlockKind.paragraph,
    ]);
    // The heading before the long paragraph stays alone.
    final section = groups.firstWhere((g) => g.first.text == 'Seção');
    expect(section, hasLength(1));
    // Output with grouped blocks still renders.
    final pdf = await exportMarkdownBytes(
      markdown: '# Título\n\nabertura curta\n\n## Seção\n\n$long',
      format: ReportExportFormat.pdf,
      fonts: fonts,
    );
    expect(pdf, isNotEmpty);
  });

  test('a heading stays with its figure and caption, or a short table',
      () async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAHnOcQAAAAABJRU5ErkJggg==';
    final blocks = parseExportMarkdown(
      '## Gráfico\n\n![G](data:image/png;base64,$png)\nlegenda 1\nlegenda 2\n\n'
      'texto seguinte\n\n## Tabela\n\n| a | b |\n|---|---|\n| 1 | 2 |\n',
    );
    final groups = keepTogetherGroups(blocks);
    expect(
        groups.first
            .map((b) => b.kind)
            .where((k) => k != ExportBlockKind.blank)
            .take(4),
        [
          ExportBlockKind.heading,
          ExportBlockKind.image,
          ExportBlockKind.paragraph,
          ExportBlockKind.paragraph,
        ]);
    final table = groups.firstWhere((g) => g.first.text == 'Tabela');
    expect(table.last.kind, ExportBlockKind.table);
  });

  test('a quote becomes a callout, citations and status words get a style',
      () async {
    const markdown = '# Título\n\n'
        '> **O que importa**\n'
        '> - Queda no T3 [p.2] [c:c1]\n'
        '> - Produto B em baixa\n\n'
        'Texto com fonte [p.3] e mais.\n\n'
        '| Item | Situação |\n|---|---|\n'
        '| Explicar | Pendente: sem motivo |\n'
        '| Plano | Confirmado |\n';
    final blocks = parseExportMarkdown(markdown);
    final callout =
        blocks.singleWhere((b) => b.kind == ExportBlockKind.callout);
    expect(callout.children.where((b) => b.kind == ExportBlockKind.item),
        hasLength(2));
    expect(callout.text, contains('Queda no T3'));
    final para = blocks.firstWhere((b) =>
        b.kind == ExportBlockKind.paragraph && b.text.startsWith('Texto'));
    expect(para.runs.where((r) => r.citation).map((r) => r.text), ['[p.3]']);
    expect(para.text, 'Texto com fonte [p.3] e mais.');

    final docx = _docxText(await exportMarkdownBytes(
      markdown: markdown,
      format: ReportExportFormat.docx,
    ));
    expect(docx, contains('w:fill="F3F6FA"'));
    expect(docx, contains('<w:pBdr><w:left'));
    expect(docx, contains('<w:color w:val="6B7280"/>'));
    expect(docx, contains('<w:color w:val="475569"/>'));
    expect(docx, contains('<w:color w:val="166534"/>'));

    final pdf = await exportMarkdownBytes(
      markdown: markdown,
      format: ReportExportFormat.pdf,
      fonts: fonts,
      meta: const ExportMeta(
        kindLabel: 'Documento',
        date: '09/11/2026',
        version: 'versão 2',
      ),
    );
    expect(pdf, isNotEmpty);
    expect(const ExportMeta(kindLabel: 'Documento', version: 'versão 2').line,
        'Documento · versão 2');
  });

  test('a draft label changes the PDF and is written at the top of the DOCX',
      () async {
    const markdown = '# T\n\ntexto';
    final plain = await exportMarkdownBytes(
      markdown: markdown,
      format: ReportExportFormat.pdf,
      fonts: fonts,
    );
    final draft = await exportMarkdownBytes(
      markdown: markdown,
      format: ReportExportFormat.pdf,
      fonts: fonts,
      meta: const ExportMeta(draftLabel: 'Rascunho'),
    );
    expect(draft, isNot(equals(plain)));
    final docx = _docxText(await exportMarkdownBytes(
      markdown: markdown,
      format: ReportExportFormat.docx,
      meta: const ExportMeta(draftLabel: 'Rascunho'),
    ));
    expect(docx, contains('>Rascunho</w:t>'));
  });

  test('a long list item and a long callout still render', () async {
    final long = List.filled(400, 'palavra').join(' ');
    final pdf = await exportMarkdownBytes(
      markdown: '# T\n\n- curto\n- $long\n\n> **x**\n> $long\n\n$long',
      format: ReportExportFormat.pdf,
      fonts: fonts,
    );
    expect(pdf, isNotEmpty);
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
