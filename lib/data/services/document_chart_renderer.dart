import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:memex/domain/models/document_chart.dart';
import 'package:memex/utils/user_storage.dart';

/// Draws [chart] on the device; nothing leaves the phone.
Future<List<int>> renderChartPng(DocumentChart chart) async {
  final chartTextStyle = GoogleFonts.inter(color: const ui.Color(0xFF222222));
  await GoogleFonts.pendingFonts();
  const w = 960.0, h = 540.0, left = 118.0, right = 24.0, top = 46.0;
  // 2016 px across the 470 pt PDF slot gives about 309 dpi for print.
  const bottom = 110.0, rasterScale = 2.1;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    const ui.Rect.fromLTWH(0, 0, w * rasterScale, h * rasterScale),
  );
  canvas.scale(rasterScale);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );

  void text(String s, ui.Offset at,
      {double size = 22,
      double? maxWidth,
      bool center = false,
      int maxLines = 2}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: chartTextStyle.copyWith(fontSize: size),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? w);
    tp.paint(canvas, center ? at.translate(-tp.width / 2, 0) : at);
  }

  // The title is written once, in the caption under the figure.
  final maxV = chart.values.fold<double>(0, (a, b) => b > a ? b : a);
  final minV = chart.values.fold<double>(0, (a, b) => b < a ? b : a);
  final dataSpan = maxV - minV;
  final padding = (dataSpan == 0 ? 1.0 : dataSpan) * 0.08;
  final minScale = minV < 0 ? minV - padding : 0.0;
  final maxScale = maxV > 0 ? maxV + padding : 0.0;
  final span = maxScale == minScale ? 1.0 : maxScale - minScale;
  const plotH = h - top - bottom;
  double yOf(double v) => top + plotH * (1 - (v - minScale) / span);
  final zero = yOf(0);
  final axis = ui.Paint()
    ..color = const ui.Color(0xFF888888)
    ..strokeWidth = 2;
  canvas
    ..drawLine(
        const ui.Offset(left, top), const ui.Offset(left, h - bottom), axis)
    ..drawLine(ui.Offset(left, zero), ui.Offset(w - right, zero), axis);
  text(chart.unit ?? 'Valor', const ui.Offset(left, 10), size: 18);
  final ticks = <double>{maxV, minV, if (minV < 0 && maxV > 0) 0};
  for (final value in ticks) {
    final y = yOf(value);
    canvas.drawLine(ui.Offset(left - 7, y), ui.Offset(left, y), axis);
    text(
      formatChartValue(
        value,
        languageCode: UserStorage.localeNotifier.value.languageCode,
      ),
      ui.Offset(left - 34, y - 10),
      size: 18,
      maxWidth: 64,
      center: true,
    );
  }

  final slot = (w - left - right) / chart.values.length;
  // Same blue as the document accent; negative values get a second tone, and
  // the sign and value are always written, so color is never the only cue.
  final bar = ui.Paint()..color = const ui.Color(0xFF1F4E79);
  final negativeBar = ui.Paint()..color = const ui.Color(0xFFC2410C);
  for (var i = 0; i < chart.values.length; i++) {
    final x = left + slot * i + slot * 0.15;
    final y = yOf(chart.values[i]);
    canvas.drawRect(
      ui.Rect.fromLTRB(
          x, y < zero ? y : zero, x + slot * 0.7, y < zero ? zero : y),
      chart.values[i] < 0 ? negativeBar : bar,
    );
    final cx = x + slot * 0.35;
    text(
      formatChartValue(
        chart.values[i],
        languageCode: UserStorage.localeNotifier.value.languageCode,
      ),
      ui.Offset(cx, chart.values[i] < 0 ? y + 8 : y - 28),
      size: 20,
      center: true,
    );
    text(chart.labels[i], ui.Offset(cx, h - bottom + 12),
        size: 20, maxWidth: slot * 0.95, center: true);
  }
  final image = await recorder
      .endRecording()
      .toImage((w * rasterScale).round(), (h * rasterScale).round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Keeps source verification locale-neutral while matching chart labels to UI language.
String formatChartValue(double value, {required String languageCode}) {
  final formatted = formatValue(value);
  return languageCode == 'pt' ? formatted.replaceAll('.', ',') : formatted;
}

/// Replaces each readable chart block by an inline PNG and a caption that
/// says where it came from. Unreadable blocks stay as written.
Future<String> expandCharts(String markdown) async {
  final blocks = findChartBlocks(markdown);
  if (blocks.isEmpty) return markdown;
  final out = StringBuffer();
  var cursor = 0;
  var figureNumber = 0;
  for (final b in blocks) {
    out.write(markdown.substring(cursor, b.start));
    cursor = b.end;
    final chart = b.chart;
    if (chart == null) {
      out.write(markdown.substring(b.start, b.end));
      continue;
    }
    figureNumber++;
    final png = await renderChartPng(chart);
    final alt = chart.title.replaceAll(RegExp(r'[\[\]]'), ' ');
    final isPortuguese = UserStorage.localeNotifier.value.languageCode == 'pt';
    final data = chart.labels.indexed
        .map((entry) => '${entry.$2}: ${formatChartValue(
              chart.values[entry.$1],
              languageCode: isPortuguese ? 'pt' : 'en',
            )}')
        .join('; ');
    final figure = isPortuguese ? 'Figura' : 'Figure';
    final shown = isPortuguese ? 'Dados' : 'Data';
    final title = chart.title.trim();
    final heading = title.isEmpty
        ? '$figure $figureNumber'
        : '$figure $figureNumber. $title';
    out
      ..write('![$alt](data:image/png;base64,${base64Encode(png)})\n')
      ..write('$heading. $shown')
      ..write(chart.unit == null ? ': ' : ' (${chart.unit}): ')
      ..write('$data.');
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
  final decoded =
      img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final small =
      oriented.width > 1280 ? img.copyResize(oriented, width: 1280) : oriented;
  return img.encodeJpg(small, quality: 85);
}
