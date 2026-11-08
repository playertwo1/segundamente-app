import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:memex/domain/models/pdf_pages.dart';
import 'package:memex/utils/logger.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

final _logger = getLogger('LocalPdfText');

/// Reads a rendered page (PNG) and returns its text; empty when none is found.
typedef PageOcr = Future<String> Function(Uint8List png);

/// Widest side of a page rendered for OCR: about 200 dpi on an A4 page, enough
/// for printed text without a huge bitmap.
const _ocrPixels = 1700.0;

/// Reads a PDF on the device, page by page, so nothing has to be sent to a
/// model: the text layer first and, for a page without one (a scan), [ocr] on
/// the rendered page. Null when the file cannot be opened.
Future<PdfPages?> readLocalPdfPages(Uint8List bytes, {PageOcr? ocr}) async {
  rx.PdfDocument? doc;
  try {
    doc = await rx.PdfDocument.openData(bytes);
    final pages = <PdfPage>[];
    for (final page in doc.pages) {
      var text = _oneLine((await page.loadText())?.fullText ?? '');
      if (text.isEmpty && ocr != null) {
        try {
          text = _oneLine(await ocr(await _renderPng(page)));
        } catch (e, st) {
          // One bad page must not lose the others; it stays empty.
          _logger.warning('OCR failed on page ${page.pageNumber}', e, st);
        }
      }
      pages.add(PdfPage(number: page.pageNumber, text: text));
    }
    return pages.isEmpty ? null : PdfPages(pages);
  } catch (e, st) {
    _logger.warning('Local PDF text failed', e, st);
    return null;
  } finally {
    await doc?.dispose();
  }
}

// The model prompt asks for line breaks as spaces; keep the same shape.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

Future<Uint8List> _renderPng(rx.PdfPage page) async {
  final scale = _ocrPixels / (page.width > page.height ? page.width : page.height);
  final image = await page.render(
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
  );
  if (image == null) throw StateError('page could not be rendered');
  try {
    return img.encodePng(img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.pixels.buffer,
      order: img.ChannelOrder.bgra,
    ));
  } finally {
    image.dispose();
  }
}

/// ML Kit OCR on the device (Latin script, which covers Portuguese). It reads
/// from a file, so the bitmap goes through a temporary one.
Future<String> ocrWithMlKit(Uint8List png) async {
  final file = File(
    '${Directory.systemTemp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(png, flush: true);
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result =
        await recognizer.processImage(InputImage.fromFilePath(file.path));
    return joinLinesByRow([
      for (final b in result.blocks)
        for (final l in b.lines) (text: l.text, box: l.boundingBox),
    ], fallback: result.text);
  } finally {
    await recognizer.close();
    if (await file.exists()) await file.delete();
  }
}

/// ML Kit returns blocks, so a table comes out column by column and a number
/// ends up far from its label. Lines whose centres sit on the same row (within
/// half a line height) are joined left to right, top to bottom.
///
/// shortcut: a page with two text columns reads across both, and a page turned
/// 90 degrees (tall lines) keeps the plain [fallback] text; add column
/// detection if a real document needs it.
String joinLinesByRow(
  List<({String text, Rect box})> lines, {
  required String fallback,
}) {
  if (lines.isEmpty) return fallback;
  final wide = lines.where((l) => l.box.width >= l.box.height).length;
  if (wide * 2 < lines.length) return fallback;
  final sorted = [...lines]
    ..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
  final rows = <List<({String text, Rect box})>>[];
  for (final line in sorted) {
    if (rows.isNotEmpty) {
      final first = rows.last.first.box;
      final height = first.height < line.box.height ? first.height : line.box.height;
      if ((line.box.center.dy - first.center.dy).abs() < 0.5 * height) {
        rows.last.add(line);
        continue;
      }
    }
    rows.add([line]);
  }
  return rows
      .map((row) => (row..sort((a, b) => a.box.left.compareTo(b.box.left)))
          .map((l) => l.text)
          .join(' '))
      .join('\n');
}
