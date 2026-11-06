import 'dart:convert';

import 'package:memex/domain/models/session_report.dart';

// shortcut: only the file size asks for confirmation, because counting pages
// before sending needs a PDF reader; add a page limit if the cost bites.
const pdfConfirmBytes = 10 * 1024 * 1024;

class PdfPage {
  const PdfPage({required this.number, required this.text});

  final int number;
  final String text;
}

class PdfPages {
  PdfPages(List<PdfPage> pages) : pages = List.unmodifiable(pages);

  final List<PdfPage> pages;

  bool get hasSelectableText =>
      pages.any((page) => page.text.trim().isNotEmpty);

  /// `p.N` labels reuse the report's clock field; pages without text are
  /// skipped so the model never sees an empty segment.
  List<ReportSegment> toSegments({int firstId = 0}) {
    final segments = <ReportSegment>[];
    for (final page in pages) {
      final text = page.text.trim();
      if (text.isEmpty) continue;
      segments.add(
        ReportSegment(
          id: 'seg_${firstId + segments.length}',
          text: text,
          clock: 'p.${page.number}',
        ),
      );
    }
    return segments;
  }

  Map<String, dynamic> toJson() => {
        'pages': [
          for (final page in pages) {'page': page.number, 'text': page.text},
        ],
      };

  static PdfPages fromJson(Object? json) {
    if (json is! Map) throw const FormatException('pages is not an object');
    final raw = json['pages'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('pages missing');
    }
    final pages = <PdfPage>[];
    var last = 0;
    for (final entry in raw) {
      if (entry is! Map) throw const FormatException('page is not an object');
      final number = entry['page'];
      final text = entry['text'];
      if (number is! int || number <= last) {
        throw FormatException('page number out of order: $number');
      }
      if (text is! String) throw FormatException('page $number has no text');
      last = number;
      pages.add(PdfPage(number: number, text: text));
    }
    return PdfPages(pages);
  }
}

String pdfPagesSystemPrompt() {
  return 'You read the attached PDF and copy its text page by page. Reply '
      'with ONLY a JSON object {"pages":[{"page","text"}]}. page is the PDF '
      'page number starting at 1, in order, one entry for every page. text is '
      'the text of that page copied exactly as written, in its own language, '
      'with line breaks as spaces. Never summarize, translate, correct or add '
      'anything. If a page has no readable text, such as a scanned image, use '
      'an empty string for it.';
}

/// Accepts the same Markdown fence models like to add around JSON, and
/// nothing else. A reply with a different page count is refused when the
/// caller knows how many pages the PDF has.
PdfPages parsePdfPagesReply(String reply, {int? expectedPages}) {
  var text = reply.trim();
  final fence = RegExp(r'^```[a-zA-Z]*\s*([\s\S]*?)\s*```$').firstMatch(text);
  if (fence != null) text = fence.group(1)!;
  final pages = PdfPages.fromJson(jsonDecode(text));
  if (expectedPages != null && pages.pages.length != expectedPages) {
    throw FormatException(
      'expected $expectedPages pages, got ${pages.pages.length}',
    );
  }
  return pages;
}

bool pdfNeedsSizeConfirmation(int bytes) => bytes > pdfConfirmBytes;

String pagesJson(PdfPages pages) =>
    const JsonEncoder.withIndent('  ').convert(pages.toJson());
