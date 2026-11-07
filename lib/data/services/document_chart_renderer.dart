import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:memex/domain/models/document_chart.dart';

/// Draws [chart] on the device; nothing leaves the phone.
Future<List<int>> renderChartPng(DocumentChart chart) async {
  const w = 960.0, h = 540.0, left = 70.0, right = 24.0, top = 64.0;
  const bottom = 110.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );

  void text(String s, ui.Offset at,
      {double size = 22, double? maxWidth, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: const ui.Color(0xFF222222)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? w);
    tp.paint(canvas, center ? at.translate(-tp.width / 2, 0) : at);
  }

  if (chart.title.isNotEmpty) {
    text(chart.title, const ui.Offset(left, 16), size: 28, maxWidth: w - 90);
  }
  final maxV = chart.values.fold<double>(0, (a, b) => b > a ? b : a);
  final minV = chart.values.fold<double>(0, (a, b) => b < a ? b : a);
  final span = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
  const plotH = h - top - bottom;
  double yOf(double v) => top + plotH * (1 - (v - minV) / span);
  final zero = yOf(0);
  final axis = ui.Paint()
    ..color = const ui.Color(0xFF888888)
    ..strokeWidth = 2;
  canvas.drawLine(ui.Offset(left, zero), ui.Offset(w - right, zero), axis);

  final slot = (w - left - right) / chart.values.length;
  final bar = ui.Paint()..color = const ui.Color(0xFF3F6FD1);
  for (var i = 0; i < chart.values.length; i++) {
    final x = left + slot * i + slot * 0.15;
    final y = yOf(chart.values[i]);
    canvas.drawRect(
      ui.Rect.fromLTRB(x, y < zero ? y : zero, x + slot * 0.7,
          y < zero ? zero : y),
      bar,
    );
    final cx = x + slot * 0.35;
    text(formatValue(chart.values[i]), ui.Offset(cx, (y < zero ? y : zero) - 28),
        size: 20, center: true);
    text(chart.labels[i], ui.Offset(cx, h - bottom + 12),
        size: 20, maxWidth: slot * 0.95, center: true);
  }
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Replaces each readable chart block by an inline PNG and a caption that
/// says where it came from. Unreadable blocks stay as written.
Future<String> expandCharts(String markdown) async {
  final blocks = findChartBlocks(markdown);
  if (blocks.isEmpty) return markdown;
  final out = StringBuffer();
  var cursor = 0;
  for (final b in blocks) {
    out.write(markdown.substring(cursor, b.start));
    cursor = b.end;
    final chart = b.chart;
    if (chart == null) {
      out.write(markdown.substring(b.start, b.end));
      continue;
    }
    final png = await renderChartPng(chart);
    final alt = chart.title.replaceAll(RegExp(r'[\[\]]'), ' ');
    out
      ..write('![$alt](data:image/png;base64,${base64Encode(png)})\n')
      ..write('Gráfico gerado no aparelho com números do próprio fio.');
  }
  out.write(markdown.substring(cursor));
  return out.toString();
}

/// Charts and record photos drawn into the Markdown. [readImage] returns the
/// bytes of a record image, or null when it is not allowed or gone; such a
/// block stays as written.
Future<String> expandDocument(
  String markdown, {
  Future<List<int>?> Function(String asset)? readImage,
}) async {
  final withCharts = await expandCharts(markdown);
  if (readImage == null) return withCharts;
  final blocks = findImageBlocks(withCharts);
  if (blocks.isEmpty) return withCharts;
  final out = StringBuffer();
  var cursor = 0;
  for (final b in blocks) {
    out.write(withCharts.substring(cursor, b.start));
    cursor = b.end;
    final bytes = b.asset == null ? null : await readImage(b.asset!);
    final jpeg = bytes == null ? null : _shrinkToJpeg(bytes);
    if (jpeg == null) {
      out.write(withCharts.substring(b.start, b.end));
      continue;
    }
    final alt = b.caption.replaceAll(RegExp(r'[\[\]]'), ' ');
    out
      ..write('![$alt](data:image/jpeg;base64,${base64Encode(jpeg)})\n')
      ..write('${b.caption.isEmpty ? 'Foto do registro' : b.caption}'
          ' (foto do registro).');
  }
  out.write(withCharts.substring(cursor));
  return out.toString();
}

List<int>? _shrinkToJpeg(List<int> bytes) {
  final decoded = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final small = oriented.width > 1280 ? img.copyResize(oriented, width: 1280) : oriented;
  return img.encodeJpg(small, quality: 85);
}
