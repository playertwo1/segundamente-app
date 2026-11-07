import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:image/image.dart' as image_codec;
import 'package:memex/domain/models/session_report.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ReportExportFormat { markdown, pdf, docx, json }

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
    case ReportExportFormat.json:
      return 'relatorio.json';
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
    case ReportExportFormat.json:
      return 'application/json';
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

/// Same item selection as the Markdown export. Each item keeps its source
/// (segment, excerpt, clock/page) so the data can be traced back.
String reportExportJson({
  required SessionReport report,
  required DateTime exportedAt,
  Set<String>? itemIds,
}) {
  final chosen = _chosenItems(report, itemIds).map((item) => item.id).toSet();
  final map = sessionReportToJson(report);
  final images = map['images'];
  if (images is List) {
    map['images'] = [
      for (final image in images)
        if (image is Map)
          Map<String, dynamic>.from(image)
            ..remove('relative_path')
            ..['illustrative_only'] = true,
    ];
  }
  map['items'] = [
    for (final item in map['items'] as List)
      if (chosen.contains((item as Map)['id'])) item,
  ];
  map['exported_at'] = exportedAt.toIso8601String();
  return const JsonEncoder.withIndent('  ').convert(map);
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
  if (format == ReportExportFormat.json) {
    return utf8.encode(
      reportExportJson(
          report: report, exportedAt: exportedAt, itemIds: itemIds),
    );
  }
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
}) async {
  switch (format) {
    case ReportExportFormat.markdown:
      return utf8.encode(markdown);
    case ReportExportFormat.pdf:
      if (fonts == null) throw ArgumentError('pdf export needs fonts');
      return _pdf(markdown, fonts);
    case ReportExportFormat.docx:
      return _docx(markdown);
    case ReportExportFormat.json:
      throw ArgumentError('json is built from the report, not from markdown');
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

Future<List<int>> _pdf(String markdown, ReportExportFonts fonts) {
  final document = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(fonts.regular),
      bold: pw.Font.ttf(fonts.bold),
    ),
  );
  final blocks = parseExportMarkdown(markdown);
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(50),
      build: (_) => [
        for (final block in blocks) _pdfBlock(block),
      ],
    ),
  );
  return document.save();
}

pw.Widget _pdfBlock(ExportBlock block) {
  if (block.kind == ExportBlockKind.blank) return pw.SizedBox(height: 6);
  if (block.kind == ExportBlockKind.image) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Center(
        child: pw.SizedBox(
          width: 480,
          height: 300,
          child: pw.Image(
            pw.MemoryImage(block.imageBytes!),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );
  }
  final heading = block.kind == ExportBlockKind.heading;
  final size = heading ? const [11.0, 18.0, 14.0, 12.0][block.level] : 11.0;
  final text = pw.RichText(
    // Lets one paragraph longer than a page continue on the next page.
    overflow: pw.TextOverflow.span,
    text: pw.TextSpan(
      style: pw.TextStyle(
        fontSize: size,
        lineSpacing: 2,
        fontWeight: heading ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
      children: [
        if (block.marker != null) pw.TextSpan(text: '${block.marker} '),
        for (final run in block.runs)
          pw.TextSpan(
            text: run.text,
            style:
                run.bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
          ),
      ],
    ),
  );
  return pw.Padding(
    padding: pw.EdgeInsets.only(
      left: block.marker == null ? 0 : 14,
      top: heading ? 8 : 0,
      bottom: heading ? 4 : 2,
    ),
    child: text,
  );
}

List<int> _docx(String markdown) {
  final blocks = parseExportMarkdown(markdown);
  final images = blocks
      .where((block) => block.kind == ExportBlockKind.image)
      .toList(growable: false);
  final document = utf8.encode(_documentXmlBlocks(blocks));
  final types = utf8.encode(_contentTypes);
  final rels = utf8.encode(_rels);
  final documentRels = _documentRelationships(images);
  final archive = Archive()
    ..addFile(ArchiveFile('[Content_Types].xml', types.length, types))
    ..addFile(ArchiveFile('_rels/.rels', rels.length, rels))
    ..addFile(ArchiveFile('word/document.xml', document.length, document))
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
</Types>
''';

const _rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';

Uint8List _documentRelationships(List<ExportBlock> images) =>
    Uint8List.fromList(
      utf8.encode(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[
          for (var i = 0; i < images.length; i++)
            '<Relationship Id="rIdImg${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/report-image-${i + 1}.${_imageExtension(images[i].imageMimeType!)}"/>'
        ].join()}'
        '</Relationships>',
      ),
    );

String _imageExtension(String mimeType) =>
    mimeType == 'image/png' ? 'png' : 'jpg';

String _documentXmlBlocks(List<ExportBlock> blocks) {
  var imageIndex = 0;
  final paragraphs = blocks.map((block) {
    if (block.kind == ExportBlockKind.blank) return '<w:p/>';
    if (block.kind == ExportBlockKind.image) {
      return _docxImage(block, ++imageIndex);
    }
    final heading = block.kind == ExportBlockKind.heading;
    final size =
        heading ? '<w:sz w:val="${const [22, 36, 28, 24][block.level]}"/>' : '';
    String run(String text, bool bold) {
      final props = bold || size.isNotEmpty
          ? '<w:rPr>${bold ? '<w:b/>' : ''}$size</w:rPr>'
          : '';
      return '<w:r>$props<w:t xml:space="preserve">${_xml(text)}</w:t></w:r>';
    }

    final indent = block.marker == null
        ? ''
        : '<w:pPr><w:ind w:left="360" w:hanging="360"/></w:pPr>';
    final runs = [
      if (block.marker != null) run('${block.marker} ', false),
      for (final r in block.runs) run(r.text, heading || r.bold),
    ].join();
    return '<w:p>$indent$runs</w:p>';
  }).join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>$paragraphs<w:sectPr/></w:body></w:document>';
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

String _xml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _xmlAttribute(String value) =>
    _xml(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');

enum ExportBlockKind { heading, paragraph, item, blank, image }

class ExportRun {
  const ExportRun(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

/// One Markdown line ready for PDF/DOCX: heading level 1-3, list item with its
/// marker ("•" or "1."), paragraph or blank line. `**text**` becomes bold.
class ExportBlock {
  const ExportBlock(
    this.kind,
    this.runs, {
    this.level = 0,
    this.marker,
    this.imageBytes,
    this.imageName,
    this.imageMimeType,
  });

  final ExportBlockKind kind;
  final List<ExportRun> runs;
  final int level;
  final String? marker;
  final Uint8List? imageBytes;
  final String? imageName;
  final String? imageMimeType;

  String get text => runs.map((run) => run.text).join();
}

final _headingPattern = RegExp(r'^(#{1,3}) (.*)$');
final _bulletPattern = RegExp(r'^\s*[-*•] (.*)$');
final _numberPattern = RegExp(r'^\s*(\d+[.)]) (.*)$');
final _inlineImagePattern = RegExp(
  r'^!\[([^\]]*)\]\(data:(image/jpeg|image/png);base64,([A-Za-z0-9+/=]+)\)$',
);

/// shortcut: tables, links, italics and nested lists stay as plain text.
/// Upgrade when F10 documents need them (tables first).
List<ExportBlock> parseExportMarkdown(String markdown) {
  final blocks = <ExportBlock>[];
  for (final line in const LineSplitter().convert(markdown)) {
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
      continue;
    }
    if (line.trim().isEmpty) {
      blocks.add(const ExportBlock(ExportBlockKind.blank, []));
      continue;
    }
    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      blocks.add(ExportBlock(
        ExportBlockKind.heading,
        _runs(heading.group(2)!),
        level: heading.group(1)!.length,
      ));
      continue;
    }
    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      blocks.add(ExportBlock(
        ExportBlockKind.item,
        _runs(bullet.group(1)!),
        marker: '•',
      ));
      continue;
    }
    final number = _numberPattern.firstMatch(line);
    if (number != null) {
      blocks.add(ExportBlock(
        ExportBlockKind.item,
        _runs(number.group(2)!),
        marker: number.group(1),
      ));
      continue;
    }
    blocks.add(ExportBlock(ExportBlockKind.paragraph, _runs(line)));
  }
  return blocks;
}

List<ExportRun> _runs(String text) {
  final parts = text.split('**');
  // An odd number of parts means every "**" is paired.
  if (parts.length.isEven) return [ExportRun(text)];
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty) ExportRun(parts[i], bold: i.isOdd),
  ];
}
