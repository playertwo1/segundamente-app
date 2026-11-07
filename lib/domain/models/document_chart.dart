import 'dart:convert';

/// A bar chart the model asks for inside a document, as a fenced block:
///
/// ```chart
/// {"title":"Custos","labels":["A","B"],"values":[10,20]}
/// ```
///
/// Every value has to appear in the sources, otherwise the document gets a
/// warning; the chart never adds a number the conversation did not say.
class DocumentChart {
  const DocumentChart({
    required this.title,
    required this.labels,
    required this.values,
  });

  static const maxPoints = 12;

  final String title;
  final List<String> labels;
  final List<double> values;

  /// Null when the block is not a usable chart.
  static DocumentChart? tryParse(String json) {
    try {
      final map = jsonDecode(json);
      if (map is! Map) return null;
      final labels = map['labels'];
      final values = map['values'];
      if (labels is! List || values is! List) return null;
      if (labels.isEmpty ||
          labels.length != values.length ||
          labels.length > maxPoints) {
        return null;
      }
      if (values.any((v) => v is! num || !v.isFinite)) return null;
      return DocumentChart(
        title: '${map['title'] ?? ''}'.trim(),
        labels: [for (final l in labels) '$l'],
        values: [for (final v in values) (v as num).toDouble()],
      );
    } on FormatException {
      return null;
    }
  }

  /// Values the sources do not contain, written as in [formatValue].
  List<String> unbackedValues(String sourceText) {
    final bad = <String>[];
    for (final v in values) {
      final plain = formatValue(v);
      final comma = plain.replaceAll('.', ',');
      final found = RegExp('(?<![\\d.,])(${RegExp.escape(plain)}|'
              '${RegExp.escape(comma)})(?![\\d])')
          .hasMatch(sourceText);
      if (!found && !bad.contains(plain)) bad.add(plain);
    }
    return bad;
  }
}

String formatValue(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

final _chartBlock = RegExp(r'```chart[ \t]*\n(.*?)\n```', dotAll: true);

class ChartBlock {
  const ChartBlock(this.start, this.end, this.chart);
  final int start;
  final int end;

  /// Null when the block could not be read.
  final DocumentChart? chart;
}

List<ChartBlock> findChartBlocks(String markdown) => [
      for (final m in _chartBlock.allMatches(markdown))
        ChartBlock(m.start, m.end, DocumentChart.tryParse(m.group(1)!)),
    ];

/// One warning per chart that is unreadable (`chart:invalid`) or that shows a
/// number the sources do not contain (`chart:<value>`).
List<String> unverifiedCharts(String markdown, String sourceText) {
  final bad = <String>[];
  for (final block in findChartBlocks(markdown)) {
    final chart = block.chart;
    final issues = chart == null
        ? ['chart:invalid']
        : [for (final v in chart.unbackedValues(sourceText)) 'chart:$v'];
    for (final i in issues) {
      if (!bad.contains(i)) bad.add(i);
    }
  }
  return bad;
}

/// A photo of the record, placed in a document as a fenced block:
///
/// ```image
/// {"asset":"assets/2026/11/06/foto.jpg","caption":"Quadro da reunião"}
/// ```
///
/// Only images the record itself holds are allowed; anything else is a warning.
class ImageBlock {
  const ImageBlock(this.start, this.end, this.asset, this.caption);
  final int start;
  final int end;

  /// Null when the block could not be read.
  final String? asset;
  final String caption;
}

final _imageBlock = RegExp(r'```image[ \t]*\n(.*?)\n```', dotAll: true);

List<ImageBlock> findImageBlocks(String markdown) {
  final blocks = <ImageBlock>[];
  for (final m in _imageBlock.allMatches(markdown)) {
    String? asset;
    var caption = '';
    try {
      final map = jsonDecode(m.group(1)!);
      if (map is Map && map['asset'] is String) {
        asset = map['asset'] as String;
        caption = '${map['caption'] ?? ''}'.trim();
      }
    } on FormatException {
      // left null: reported as invalid
    }
    blocks.add(ImageBlock(m.start, m.end, asset, caption));
  }
  return blocks;
}

/// `image:invalid` for an unreadable block, `image:<asset>` for a picture the
/// record does not hold.
/// The model sometimes writes a photo as `![caption](path)` instead of the
/// ```image block. When the path is one of the record's photos it becomes the
/// block (which is what draws and checks it); any other target is left alone.
String imageMarkdownToBlocks(String markdown, Set<String> recordImages) {
  return markdown.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)'), (m) {
    final path = m[2]!;
    if (!recordImages.contains(path)) return m[0]!;
    final json = jsonEncode({'asset': path, 'caption': m[1]!});
    return '```image\n$json\n```';
  });
}

List<String> unverifiedImages(String markdown, Set<String> recordImages) {
  final bad = <String>[];
  for (final b in findImageBlocks(markdown)) {
    final issue = b.asset == null
        ? 'image:invalid'
        : recordImages.contains(b.asset)
            ? null
            : 'image:${b.asset}';
    if (issue != null && !bad.contains(issue)) bad.add(issue);
  }
  return bad;
}
