import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:image/image.dart' as image_codec;
import 'package:memex/domain/models/session_report.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ReportExportFormat { markdown, pdf, docx }

const reportExportDateLabel = 'Data';
const reportExportSourceLabel = 'Fonte';
const reportExportClockLabel = 'Relógio';
const reportExportImageDisclaimer =
    'These images are visual references only; they do not prove report items.';
const reportExportNoImagesMessage = 'No related image is available.';

String reportExportFileName(ReportExportFormat format) {
  switch (format) {
    case ReportExportFormat.markdown:
      return 'relatorio.md';
    case ReportExportFormat.pdf:
      return 'relatorio.pdf';
    case ReportExportFormat.docx:
      return 'relatorio.docx';
  }
}

String reportExportMimeType(ReportExportFormat format) {
  switch (format) {
    case ReportExportFormat.markdown:
      return 'text/markdown';
    case ReportExportFormat.pdf:
      return 'application/pdf';
    case ReportExportFormat.docx:
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
}

String formatReportExportDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

class ReportExportImage {
  const ReportExportImage({
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.messageIndex,
    this.messageTimestamp,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final int messageIndex;
  final String? messageTimestamp;
}

/// [itemIds] null keeps every item that was not discarded.
/// A set keeps only those ids, including a discarded item the user checked.
String reportExportMarkdown({
  required SessionReport report,
  required DateTime exportedAt,
  Set<String>? itemIds,
  List<ReportExportImage> images = const [],
  String imageDisclaimer = reportExportImageDisclaimer,
  String noImagesMessage = reportExportNoImagesMessage,
}) {
  final chosen = _chosenItems(report, itemIds);
  final buffer = StringBuffer()
    ..writeln('# ${report.title}')
    ..writeln()
    ..writeln('$reportExportDateLabel: ${formatReportExportDate(exportedAt)}')
    ..writeln();
  for (final section in report.sections) {
    final items = chosen.where((item) => item.kind == section).toList();
    if (items.isEmpty) continue;
    buffer
      ..writeln('## ${_sectionTitle(section)}')
      ..writeln();
    for (final item in items) {
      buffer
        ..writeln('### ${item.text}')
        ..writeln()
        ..writeln('${item.assignee} · ${item.due}')
        ..writeln(_statusLabel(item.status))
        ..writeln('$reportExportSourceLabel: ${item.source.excerpt}');
      final clock = item.source.clock;
      if (clock != null && clock.isNotEmpty) {
        buffer.writeln('$reportExportClockLabel: $clock');
      }
      buffer.writeln();
    }
  }
  if (images.isNotEmpty) {
    buffer
      ..writeln('## Imagens anexadas')
      ..writeln()
      ..writeln(imageDisclaimer)
      ..writeln();
    for (final image in images) {
      final alt = image.name.replaceAll(RegExp(r'[\[\]]'), ' ');
      buffer
        ..writeln(
          '![$alt](data:${image.mimeType};base64,${base64Encode(image.bytes)})',
        )
        ..writeln(
          '$reportExportSourceLabel: mensagem ${image.messageIndex} '
          '${image.messageTimestamp ?? ''}',
        )
        ..writeln();
    }
  } else {
    buffer
      ..writeln('## Imagens relacionadas')
      ..writeln()
      ..writeln(noImagesMessage)
      ..writeln();
  }
  return buffer.toString();
}

/// TrueType fonts embedded in the PDF. Loaded by the data layer (assets), so
/// this file stays free of Flutter.
class ReportExportFonts {
  const ReportExportFonts({required this.regular, required this.bold});

  final ByteData regular;
  final ByteData bold;
}

Future<List<int>> exportSessionReportBytes({
  required SessionReport report,
  required DateTime exportedAt,
  required ReportExportFormat format,
  Set<String>? itemIds,
  ReportExportFonts? fonts,
  List<ReportExportImage> images = const [],
  String imageDisclaimer = reportExportImageDisclaimer,
  String noImagesMessage = reportExportNoImagesMessage,
}) async {
  final markdown = reportExportMarkdown(
    report: report,
    exportedAt: exportedAt,
    itemIds: itemIds,
    images: images,
    imageDisclaimer: imageDisclaimer,
    noImagesMessage: noImagesMessage,
  );
  return exportMarkdownBytes(markdown: markdown, format: format, fonts: fonts);
}

/// Renders any Markdown text (session report, F10 documents) to the format.
/// PDF needs [fonts]; Markdown and DOCX do not.
Future<List<int>> exportMarkdownBytes({
  required String markdown,
  required ReportExportFormat format,
  ReportExportFonts? fonts,
  String languageCode = 'pt',
  ExportMeta? meta,
}) async {
  switch (format) {
    case ReportExportFormat.markdown:
      return utf8.encode(markdown);
    case ReportExportFormat.pdf:
      if (fonts == null) throw ArgumentError('pdf export needs fonts');
      return _pdf(markdown, fonts, meta);
    case ReportExportFormat.docx:
      return _docx(markdown, languageCode, meta);
  }
}

List<ReportItem> _chosenItems(SessionReport report, Set<String>? itemIds) {
  if (itemIds == null) {
    return report.items
        .where((item) => item.status != ReportItemStatus.discarded)
        .toList(growable: false);
  }
  return report.items
      .where((item) => itemIds.contains(item.id))
      .toList(growable: false);
}

String _sectionTitle(ReportItemKind kind) {
  switch (kind) {
    case ReportItemKind.summary:
      return 'Resumo';
    case ReportItemKind.idea:
      return 'Ideias';
    case ReportItemKind.opportunity:
      return 'Oportunidades';
    case ReportItemKind.decision:
      return 'Decisões';
    case ReportItemKind.task:
      return 'Tarefas';
    case ReportItemKind.followUp:
      return 'Encaminhamentos';
    case ReportItemKind.question:
      return 'Dúvidas';
  }
}

String _statusLabel(ReportItemStatus status) {
  switch (status) {
    case ReportItemStatus.unconfirmed:
      return 'Não confirmado';
    case ReportItemStatus.approved:
      return 'Confirmado';
    case ReportItemStatus.discarded:
      return 'Descartado';
  }
}

const _pdfInk = PdfColor.fromInt(0xFF1F2937);
const _pdfAccent = PdfColor.fromInt(0xFF1F4E79);
const _pdfMuted = PdfColor.fromInt(0xFF6B7280);
const _pdfPanel = PdfColor.fromInt(0xFFF3F6FA);
const _pdfStripe = PdfColor.fromInt(0xFFF7F9FC);

Future<List<int>> _pdf(
  String markdown,
  ReportExportFonts fonts,
  ExportMeta? meta,
) {
  final blocks = parseExportMarkdown(markdown);
  String? title;
  for (final block in blocks) {
    if (block.kind == ExportBlockKind.heading && block.level == 1) {
      title = block.text.trim();
      break;
    }
  }
  final document = pw.Document(
    title: title?.isEmpty == true ? null : title,
    creator: 'Segunda Mente',
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(fonts.regular),
      bold: pw.Font.ttf(fonts.bold),
    ),
  );
  final runningTitle = title;
  final footerLabel = [
    'Segunda Mente',
    if (meta?.version != null) meta!.version!,
  ].join(' · ');
  pw.Widget groupWidget(List<ExportBlock> group) {
    var afterImage = false;
    final children = <pw.Widget>[];
    for (final block in group) {
      children.add(_pdfBlock(
        block,
        caption: afterImage && block.kind != ExportBlockKind.blank,
      ));
      if (block.kind == ExportBlockKind.image) afterImage = true;
    }
    return group.length == 1
        ? children.single
        : pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: children,
            ),
          );
  }

  final draft = meta?.draftLabel;
  final showDraft = draft != null && draft.isNotEmpty;
  document.addPage(
    pw.MultiPage(
      // pageTheme carries the page size. The pdf package rejects a theme
      // together with pageFormat or margin.
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        // 72 pt sides give about 85 characters per line at 10.5 pt.
        margin: const pw.EdgeInsets.fromLTRB(72, 60, 72, 64),
        buildForeground: showDraft
            ? (_) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Center(
                    child: pw.Opacity(
                      opacity: 0.14,
                      child: pw.Transform.rotate(
                        angle: -0.5,
                        child: pw.Text(
                          draft,
                          style: pw.TextStyle(
                            fontSize: 52,
                            color: _pdfAccent,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
            : null,
      ),
      header: (context) => context.pageNumber == 1 ||
              runningTitle == null ||
              runningTitle.isEmpty
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              child: pw.Text(
                runningTitle,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: const pw.TextStyle(fontSize: 8, color: _pdfMuted),
              ),
            ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 14),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              footerLabel,
              style: const pw.TextStyle(fontSize: 8, color: _pdfMuted),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _pdfMuted),
            ),
          ],
        ),
      ),
      build: (_) => [
        if (meta != null && meta.line.isNotEmpty) _pdfEyebrow(meta.line),
        for (final group in keepTogetherGroups(blocks)) groupWidget(group),
      ],
    ),
  );
  return document.save();
}

pw.Widget _pdfEyebrow(String line) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        line.toUpperCase(),
        style: const pw.TextStyle(
          fontSize: 8,
          letterSpacing: 0.9,
          color: _pdfAccent,
        ),
      ),
    );

/// Groups a heading with the figure, short table or short text after it, and a
/// figure with the few short lines that caption it, so a page break does not
/// strand a heading or a figure. Long text is never grouped: an inseparable
/// block taller than a page makes the pdf package fail.
List<List<ExportBlock>> keepTogetherGroups(List<ExportBlock> blocks) {
  const maxTextLength = 300;
  const maxCaptionBlocks = 3;
  const maxTableRows = 8;
  bool shortText(ExportBlock b) =>
      (b.kind == ExportBlockKind.paragraph || b.kind == ExportBlockKind.item) &&
      b.text.length <= maxTextLength;
  // Index of the next block that is not blank, or -1.
  int nextContent(int from) {
    var j = from;
    while (j < blocks.length && blocks[j].kind == ExportBlockKind.blank) {
      j++;
    }
    return j < blocks.length ? j : -1;
  }

  final groups = <List<ExportBlock>>[];
  var i = 0;
  while (i < blocks.length) {
    var end = i; // last index in this group
    final first = blocks[i];
    if (first.kind == ExportBlockKind.heading) {
      final j = nextContent(i + 1);
      if (j != -1) {
        final next = blocks[j];
        if (shortText(next) ||
            next.kind == ExportBlockKind.image ||
            (next.kind == ExportBlockKind.table &&
                next.tableRows.length <= maxTableRows)) {
          end = j;
        }
      }
    }
    if (blocks[end].kind == ExportBlockKind.image) {
      for (var n = 0; n < maxCaptionBlocks; n++) {
        final j = nextContent(end + 1);
        if (j == -1 || !shortText(blocks[j])) break;
        end = j;
      }
    }
    groups.add(blocks.sublist(i, end + 1));
    i = end + 1;
  }
  return groups;
}

pw.TextStyle? _pdfRunStyle(ExportRun run) {
  if (run.citation) return const pw.TextStyle(fontSize: 8.5, color: _pdfMuted);
  final color = run.color == null ? null : PdfColor.fromHex(run.color!);
  if (!run.bold && color == null) return null;
  return pw.TextStyle(fontWeight: pw.FontWeight.bold, color: color);
}

pw.Widget _pdfCallout(ExportBlock block) {
  final inner = block.children.where((b) => b.kind != ExportBlockKind.blank);
  // A box cannot continue on the next page, so a long one is plain text.
  if (block.text.length > 1200) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [for (final b in block.children) _pdfBlock(b)],
    );
  }
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.symmetric(vertical: 8),
    padding: const pw.EdgeInsets.fromLTRB(14, 10, 12, 8),
    decoration: const pw.BoxDecoration(
      color: _pdfPanel,
      border: pw.Border(left: pw.BorderSide(color: _pdfAccent, width: 3)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [for (final b in inner) _pdfBlock(b, body: 11)],
    ),
  );
}

pw.Widget _pdfBlock(
  ExportBlock block, {
  bool caption = false,
  double body = 10.5,
}) {
  if (block.kind == ExportBlockKind.blank) return pw.SizedBox(height: 4);
  if (block.kind == ExportBlockKind.table) return _pdfTable(block);
  if (block.kind == ExportBlockKind.callout) return _pdfCallout(block);
  if (block.kind == ExportBlockKind.image) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Center(
        child: pw.SizedBox(
          width: 450,
          height: 290,
          child: pw.Image(
            pw.MemoryImage(block.imageBytes!),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );
  }
  final heading = block.kind == ExportBlockKind.heading;
  final title = heading && block.level == 1;
  // Title 24pt, section 15pt, subsection 12.5pt, body 10.5pt, caption 9pt.
  final size = heading
      ? const [10.5, 24.0, 15.0, 12.5][block.level]
      : caption
          ? 9.0
          : body;
  // Natural Inter line height is about 1.21 em; +2 pt gives about 140%.
  final lineSpacing = heading ? 1.0 : (caption ? 1.5 : 2.0);
  final style = pw.TextStyle(
    fontSize: size,
    lineSpacing: lineSpacing,
    color: heading
        ? _pdfAccent
        : caption
            ? _pdfMuted
            : _pdfInk,
    fontWeight: heading ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  pw.TextSpan runSpan(ExportRun run) => pw.TextSpan(
        text: run.text,
        style: heading ? null : _pdfRunStyle(run),
      );
  // Items hang their marker; an item too long for a page falls back to a
  // marker inside the text, because a Row cannot continue on the next page.
  final hanging = block.marker != null && block.text.length <= 700;
  final text = pw.RichText(
    // Lets one paragraph longer than a page continue on the next page.
    overflow: pw.TextOverflow.span,
    text: pw.TextSpan(
      style: style,
      children: [
        if (block.marker != null && !hanging)
          pw.TextSpan(text: '${block.marker} '),
        for (final run in block.runs) runSpan(run),
      ],
    ),
  );
  if (hanging) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 18,
            child: pw.Text(block.marker!, style: style),
          ),
          pw.Expanded(child: text),
        ],
      ),
    );
  }
  return pw.Container(
    width: double.infinity,
    padding: pw.EdgeInsets.only(
      left: block.marker == null ? 0 : 18,
      bottom: title ? 8 : 0,
    ),
    margin: pw.EdgeInsets.only(
      top: !heading ? 0 : (title ? 0 : 22),
      bottom: title ? 14 : (caption ? 2 : 6),
    ),
    decoration: title
        ? const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _pdfAccent, width: 1.2),
            ),
          )
        : null,
    child: text,
  );
}

pw.Widget _pdfTable(ExportBlock block) {
  final rows = block.tableRows;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 10),
    child: pw.Table(
      // Three rules: top, under the header, bottom. Body rows stay open.
      border: const pw.TableBorder(
        top: pw.BorderSide(color: _pdfAccent, width: 1.1),
        bottom: pw.BorderSide(color: _pdfAccent, width: 1.1),
      ),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: {
        for (var column = 0; column < block.tableAlignments.length; column++)
          column: const pw.FlexColumnWidth(),
      },
      children: [
        for (var row = 0; row < rows.length; row++)
          pw.TableRow(
            repeat: row == 0,
            decoration: pw.BoxDecoration(
              color: row == 0 ? _pdfPanel : (row.isEven ? _pdfStripe : null),
              border: row == 0
                  ? const pw.Border(
                      bottom: pw.BorderSide(color: _pdfAccent, width: 0.6),
                    )
                  : null,
            ),
            children: [
              for (var column = 0; column < rows[row].length; column++)
                pw.Container(
                  alignment: _pdfTableAlignment(block.tableAlignments[column]),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 7,
                  ),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        lineSpacing: 2,
                        color: row == 0 ? _pdfAccent : _pdfInk,
                        fontWeight: row == 0
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                      ),
                      children: [
                        for (final run in _cellRuns(rows[row][column]))
                          pw.TextSpan(
                            text: run.text,
                            style: _pdfRunStyle(run),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

pw.Alignment _pdfTableAlignment(ExportTableAlignment alignment) =>
    switch (alignment) {
      ExportTableAlignment.left => pw.Alignment.centerLeft,
      ExportTableAlignment.center => pw.Alignment.center,
      ExportTableAlignment.right => pw.Alignment.centerRight,
    };

List<int> _docx(String markdown, String languageCode, ExportMeta? meta) {
  final blocks = parseExportMarkdown(markdown);
  final images = blocks
      .where((block) => block.kind == ExportBlockKind.image)
      .toList(growable: false);
  final document = utf8.encode(_documentXmlBlocks(blocks, meta?.draftLabel));
  final types = utf8.encode(_contentTypes);
  final rels = utf8.encode(_rels);
  final styles = utf8.encode(_docxStyles(languageCode));
  final core = utf8.encode(_docxCoreProperties(blocks, languageCode));
  final documentRels = _documentRelationships(images);
  final archive = Archive()
    ..addFile(ArchiveFile('[Content_Types].xml', types.length, types))
    ..addFile(ArchiveFile('_rels/.rels', rels.length, rels))
    ..addFile(ArchiveFile('word/document.xml', document.length, document))
    ..addFile(ArchiveFile('word/styles.xml', styles.length, styles))
    ..addFile(ArchiveFile('docProps/core.xml', core.length, core))
    ..addFile(
      ArchiveFile(
        'word/_rels/document.xml.rels',
        documentRels.length,
        documentRels,
      ),
    );
  var imageIndex = 0;
  for (final image in images) {
    imageIndex++;
    final media = image.imageBytes!;
    archive.addFile(ArchiveFile(
      'word/media/report-image-$imageIndex.${_imageExtension(image.imageMimeType!)}',
      media.length,
      media,
    ));
  }
  return ZipEncoder().encode(archive);
}

const _contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="jpg" ContentType="image/jpeg"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>
''';

const _rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>
''';

Uint8List _documentRelationships(List<ExportBlock> images) =>
    Uint8List.fromList(
      utf8.encode(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '${[
          for (var i = 0; i < images.length; i++)
            '<Relationship Id="rIdImg${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/report-image-${i + 1}.${_imageExtension(images[i].imageMimeType!)}"/>'
        ].join()}'
        '</Relationships>',
      ),
    );

String _imageExtension(String mimeType) =>
    mimeType == 'image/png' ? 'png' : 'jpg';

String _documentXmlBlocks(List<ExportBlock> blocks, String? draftLabel) {
  var imageIndex = 0;
  String paragraph(ExportBlock block, {bool box = false}) {
    final heading = block.kind == ExportBlockKind.heading;
    final size =
        heading ? '<w:sz w:val="${const [22, 36, 28, 24][block.level]}"/>' : '';
    String run(ExportRun r, bool bold) {
      final color = r.citation
          ? '<w:color w:val="6B7280"/>'
          : r.color != null
              ? '<w:color w:val="${r.color}"/>'
              : '';
      final props =
          '${bold ? '<w:b/>' : ''}$color${r.citation ? '<w:sz w:val="17"/>' : size}';
      return '<w:r>${props.isEmpty ? '' : '<w:rPr>$props</w:rPr>'}'
          '<w:t xml:space="preserve">${_xml(r.text)}</w:t></w:r>';
    }

    final pPr = [
      if (heading) '<w:pStyle w:val="Heading${block.level.clamp(1, 3)}"/>',
      if (box)
        '<w:pBdr><w:left w:val="single" w:sz="24" w:space="8" w:color="1F4E79"/></w:pBdr>'
            '<w:shd w:val="clear" w:color="auto" w:fill="F3F6FA"/>',
      if (!heading && block.marker != null)
        '<w:ind w:left="360" w:hanging="360"/>',
    ].join();
    final runs = [
      if (block.marker != null) run(ExportRun('${block.marker} '), false),
      for (final r in block.runs) run(r, heading || r.bold),
    ].join();
    return '<w:p>${pPr.isEmpty ? '' : '<w:pPr>$pPr</w:pPr>'}$runs</w:p>';
  }

  final paragraphs = blocks.map((block) {
    if (block.kind == ExportBlockKind.blank) return '<w:p/>';
    if (block.kind == ExportBlockKind.table) return _docxTable(block);
    if (block.kind == ExportBlockKind.image) {
      return _docxImage(block, ++imageIndex);
    }
    if (block.kind == ExportBlockKind.callout) {
      return [
        for (final inner in block.children)
          if (inner.kind != ExportBlockKind.blank) paragraph(inner, box: true),
      ].join();
    }
    return paragraph(block);
  }).join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>${_docxDraft(draftLabel)}$paragraphs<w:sectPr/></w:body></w:document>';
}

String _docxDraft(String? label) {
  if (label == null || label.isEmpty) return '';
  return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/>'
      '<w:color w:val="1F4E79"/><w:sz w:val="32"/></w:rPr>'
      '<w:t xml:space="preserve">${_xml(label)}</w:t></w:r></w:p>';
}

String _docxCellRunProps(ExportRun run, bool header) {
  final bold = header || run.bold || run.color != null;
  final color =
      run.citation ? '6B7280' : run.color ?? (header ? '1F4E79' : null);
  final props = '${bold && !run.citation ? '<w:b/>' : ''}'
      '${color == null ? '' : '<w:color w:val="$color"/>'}'
      '${run.citation ? '<w:sz w:val="17"/>' : ''}';
  return props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
}

String _docxTable(ExportBlock block) {
  final rows = block.tableRows;
  String cell(String text, int column, bool header, bool stripe) {
    final alignment = switch (block.tableAlignments[column]) {
      ExportTableAlignment.left => 'left',
      ExportTableAlignment.center => 'center',
      ExportTableAlignment.right => 'right',
    };
    final runs = [
      for (final run in _cellRuns(text))
        '<w:r>${_docxCellRunProps(run, header)}'
            '<w:t xml:space="preserve">${_xml(run.text)}</w:t></w:r>',
    ].join();
    final fill = header
        ? '<w:shd w:fill="F3F6FA"/>'
        : stripe
            ? '<w:shd w:fill="F7F9FC"/>'
            : '';
    final rule = header
        ? '<w:tcBorders><w:bottom w:val="single" w:sz="8" w:color="1F4E79"/></w:tcBorders>'
        : '';
    return '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>$fill$rule'
        '<w:tcMar><w:top w:w="90" w:type="dxa"/><w:left w:w="100" w:type="dxa"/>'
        '<w:bottom w:w="90" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tcMar>'
        '<w:vAlign w:val="center"/></w:tcPr><w:p><w:pPr><w:jc w:val="$alignment"/></w:pPr>'
        '$runs</w:p></w:tc>';
  }

  final tableRows = [
    for (var row = 0; row < rows.length; row++)
      '<w:tr>${row == 0 ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}'
          '${[
        for (var column = 0; column < rows[row].length; column++)
          cell(rows[row][column], column, row == 0, row > 0 && row.isEven)
      ].join()}'
          '</w:tr>',
  ].join();
  return '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders>'
      '<w:top w:val="single" w:sz="12" w:color="1F4E79"/>'
      '<w:left w:val="nil"/><w:bottom w:val="single" w:sz="12" w:color="1F4E79"/>'
      '<w:right w:val="nil"/><w:insideH w:val="nil"/>'
      '<w:insideV w:val="nil"/></w:tblBorders></w:tblPr>$tableRows</w:tbl>';
}

String _docxImage(ExportBlock block, int index) {
  final image = image_codec.decodeImage(block.imageBytes!);
  final width = image?.width ?? 1600;
  final height = image?.height ?? 1000;
  const maxWidthEmu = 4_572_000.0;
  const maxHeightEmu = 2_743_200.0;
  final scale = math.min(maxWidthEmu / width, maxHeightEmu / height);
  final cx = (width * scale).round();
  final cy = (height * scale).round();
  final name = _xmlAttribute(block.imageName ?? 'image-$index.jpg');
  return '<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$index" name="$name" descr="$name"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$index" name="$name"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="rIdImg$index"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
      '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';
}

// Real heading styles and the document language let Word and screen readers
// navigate by heading and pick the right voice. Sizes stay as direct run
// formatting on each heading.
String _docxStyles(String languageCode) {
  final lang = languageCode == 'en' ? 'en-US' : 'pt-BR';
  String heading(int level) =>
      '<w:style w:type="paragraph" w:styleId="Heading$level"><w:name w:val="heading $level"/>'
      '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
      '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="${level - 1}"/></w:pPr></w:style>';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="$lang" w:eastAsia="$lang" w:bidi="ar-SA"/></w:rPr></w:rPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
      '${heading(1)}${heading(2)}${heading(3)}</w:styles>';
}

String _docxCoreProperties(List<ExportBlock> blocks, String languageCode) {
  final title = blocks
      .where((b) => b.kind == ExportBlockKind.heading && b.level == 1)
      .map((b) => b.text.trim())
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '${title.isEmpty ? '' : '<dc:title>${_xml(title)}</dc:title>'}'
      '<dc:creator>Segunda Mente</dc:creator>'
      '<dc:language>${languageCode == 'en' ? 'en-US' : 'pt-BR'}</dc:language>'
      '</cp:coreProperties>';
}

String _xml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _xmlAttribute(String value) =>
    _xml(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');

enum ExportBlockKind { heading, paragraph, item, blank, image, table, callout }

enum ExportTableAlignment { left, center, right }

class ExportRun {
  const ExportRun(
    this.text, {
    this.bold = false,
    this.citation = false,
    this.color,
  });

  final String text;
  final bool bold;

  /// A source marker such as `[p.2]` or `[c:id]`, drawn small and muted.
  final bool citation;

  /// Hex RRGGBB for a status word in a table cell; the word stays as text.
  final String? color;
}

/// Identification shown above the title of a PDF.
class ExportMeta {
  const ExportMeta({this.kindLabel, this.date, this.version, this.draftLabel});

  final String? kindLabel;
  final String? date;
  final String? version;

  /// Short word painted across the PDF and written at the top of the DOCX.
  /// Empty means a finished export.
  final String? draftLabel;

  String get line => [
        if (kindLabel != null && kindLabel!.isNotEmpty) kindLabel!,
        if (date != null && date!.isNotEmpty) date!,
        if (version != null && version!.isNotEmpty) version!,
      ].join(' · ');
}

/// Markdown content prepared for PDF/DOCX: heading, list, table, image or text.
/// `**text**` becomes bold.
class ExportBlock {
  const ExportBlock(
    this.kind,
    this.runs, {
    this.level = 0,
    this.marker,
    this.imageBytes,
    this.imageName,
    this.imageMimeType,
    this.tableRows = const [],
    this.tableAlignments = const [],
    this.children = const [],
  });

  final ExportBlockKind kind;
  final List<ExportRun> runs;
  final int level;
  final String? marker;
  final Uint8List? imageBytes;
  final String? imageName;
  final String? imageMimeType;
  final List<List<String>> tableRows;
  final List<ExportTableAlignment> tableAlignments;

  /// Blocks inside a callout (a Markdown `>` quote).
  final List<ExportBlock> children;

  String get text => kind == ExportBlockKind.callout
      ? children.map((b) => b.text).join(' ')
      : runs.map((run) => run.text).join();
}

final _headingPattern = RegExp(r'^(#{1,3}) (.*)$');
final _bulletPattern = RegExp(r'^\s*[-*•] (.*)$');
final _numberPattern = RegExp(r'^\s*(\d+[.)]) (.*)$');
final _inlineImagePattern = RegExp(
  r'^!\[([^\]]*)\]\(data:(image/jpeg|image/png);base64,([A-Za-z0-9+/=]+)\)$',
);

/// shortcut: links, italics and nested lists stay as plain text; pipe escapes
/// inside table cells are not interpreted.
List<ExportBlock> parseExportMarkdown(String markdown) {
  final blocks = <ExportBlock>[];
  final lines = const LineSplitter().convert(markdown);
  for (var i = 0; i < lines.length;) {
    if (i + 1 < lines.length && lines[i].contains('|')) {
      final headers = _tableCells(lines[i]);
      final separators = _tableCells(lines[i + 1]);
      if (headers.length > 1 &&
          separators.length == headers.length &&
          _isTableSeparator(separators)) {
        final rows = <List<String>>[headers];
        var end = i + 2;
        while (end < lines.length &&
            lines[end].trim().isNotEmpty &&
            lines[end].contains('|')) {
          final row = _tableCells(lines[end]);
          if (row.length != headers.length || _isTableSeparator(row)) break;
          rows.add(row);
          end++;
        }
        blocks.add(ExportBlock(
          ExportBlockKind.table,
          const [],
          tableRows: rows,
          tableAlignments: [
            for (final cell in separators)
              cell.startsWith(':') && cell.endsWith(':')
                  ? ExportTableAlignment.center
                  : cell.endsWith(':')
                      ? ExportTableAlignment.right
                      : ExportTableAlignment.left,
          ],
        ));
        i = end;
        continue;
      }
    }

    final line = lines[i];
    final inlineImage = _inlineImagePattern.firstMatch(line);
    if (inlineImage != null) {
      blocks.add(
        ExportBlock(
          ExportBlockKind.image,
          const [],
          imageName: inlineImage.group(1),
          imageMimeType: inlineImage.group(2),
          imageBytes: base64Decode(inlineImage.group(3)!),
        ),
      );
      i++;
      continue;
    }
    if (line.trim().isEmpty) {
      blocks.add(const ExportBlock(ExportBlockKind.blank, []));
      i++;
      continue;
    }
    if (line.trimLeft().startsWith('>')) {
      var end = i;
      final inner = <String>[];
      while (end < lines.length && lines[end].trimLeft().startsWith('>')) {
        inner.add(lines[end].trimLeft().substring(1).replaceFirst(' ', ''));
        end++;
      }
      blocks.add(ExportBlock(
        ExportBlockKind.callout,
        const [],
        children: parseExportMarkdown(inner.join('\n')),
      ));
      i = end;
      continue;
    }
    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      blocks.add(ExportBlock(
        ExportBlockKind.heading,
        _runs(heading.group(2)!),
        level: heading.group(1)!.length,
      ));
      i++;
      continue;
    }
    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      blocks.add(ExportBlock(
        ExportBlockKind.item,
        _runs(bullet.group(1)!),
        marker: '•',
      ));
      i++;
      continue;
    }
    final number = _numberPattern.firstMatch(line);
    if (number != null) {
      blocks.add(ExportBlock(
        ExportBlockKind.item,
        _runs(number.group(2)!),
        marker: number.group(1),
      ));
      i++;
      continue;
    }
    blocks.add(ExportBlock(ExportBlockKind.paragraph, _runs(line)));
    i++;
  }
  return blocks;
}

List<String> _tableCells(String line) {
  var content = line.trim();
  if (content.startsWith('|')) content = content.substring(1);
  if (content.endsWith('|')) content = content.substring(0, content.length - 1);
  return content.split('|').map((cell) => cell.trim()).toList();
}

bool _isTableSeparator(List<String> cells) =>
    cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell));

final _citationPattern = RegExp(r'\[(?:c:[^\]\s]+|p\.\d+(?:[–-]\d+)?)\]');

List<ExportRun> _runs(String text) {
  final parts = text.split('**');
  // An odd number of parts means every "**" is paired.
  final base = parts.length.isEven
      ? [ExportRun(text)]
      : [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].isNotEmpty) ExportRun(parts[i], bold: i.isOdd),
        ];
  return [for (final run in base) ..._splitCitations(run)];
}

List<ExportRun> _splitCitations(ExportRun run) {
  final out = <ExportRun>[];
  var last = 0;
  for (final m in _citationPattern.allMatches(run.text)) {
    if (m.start > last) {
      out.add(ExportRun(run.text.substring(last, m.start), bold: run.bold));
    }
    out.add(ExportRun(m.group(0)!, citation: true));
    last = m.end;
  }
  if (out.isEmpty) return [run];
  if (last < run.text.length) {
    out.add(ExportRun(run.text.substring(last), bold: run.bold));
  }
  return out;
}

final _statusPattern = RegExp(
  r'^(confirmado|confirmed|hip[óo]tese|hypothesis|pendente|pending)',
  caseSensitive: false,
);

String _statusColor(String word) {
  final w = word.toLowerCase();
  if (w.startsWith('confirm')) return '166534';
  if (w.startsWith('hip')) return '92400E';
  return '475569';
}

/// Runs of a table cell; a leading status word (Confirmado, Hipótese,
/// Pendente and their English forms) is bold and colored, the rest is plain.
List<ExportRun> _cellRuns(String text) {
  final runs = _runs(text);
  if (runs.isEmpty) return runs;
  final first = runs.first;
  final match = first.citation ? null : _statusPattern.firstMatch(first.text);
  if (match == null) return runs;
  return [
    ExportRun(match.group(0)!,
        bold: true, color: _statusColor(match.group(0)!)),
    if (match.end < first.text.length)
      ExportRun(first.text.substring(match.end), bold: first.bold),
    ...runs.skip(1),
  ];
}
