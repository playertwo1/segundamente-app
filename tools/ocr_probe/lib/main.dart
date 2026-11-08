import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Runs every OCR engine over every image and writes results.json. No input:
/// it starts on launch; read the result with `adb shell run-as ... cat`.
void main() {
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('OCR bench')))));
  _guard();
}

Future<void> _guard() async {
  try {
    await _run();
  } catch (e, st) {
    final d = await getExternalStorageDirectory();
    File('${d!.path}/error.txt').writeAsStringSync('$e\n$st');
  }
}

double _lastConf = 0;

typedef Engine = Future<String> Function(String path);

Future<void> _run() async {
  final docs = (await getExternalStorageDirectory())!;
  final work = Directory('${docs.path}/work')..createSync(recursive: true);
  final images = <String>[];
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  for (final a in manifest.listAssets().where((a) => a.startsWith('assets/set/'))) {
    final f = File('${work.path}/${a.split('/').last}');
    f.writeAsBytesSync((await rootBundle.load(a)).buffer.asUint8List());
    images.add(f.path);
  }
  final real = Directory('${docs.path}/real');
  final realFiles = real.existsSync()
      ? real.listSync().whereType<File>().map((f) => f.path).toList()
      : <String>[];
  // When real documents were pushed, only they are measured.
  final list = realFiles.isNotEmpty ? realFiles : images;
  list.sort();
  images
    ..clear()
    ..addAll(list);
  final onlyFile = File('${docs.path}/only.txt');
  final only = onlyFile.existsSync() ? onlyFile.readAsStringSync().trim() : '';

  final latin = TextRecognizer(script: TextRecognitionScript.latin);
  final chinese = TextRecognizer(script: TextRecognitionScript.chinese);
  final paddle = PaddleOcr();
  final engines = <String, Engine>{
    'mlkit_latin': (p) async =>
        (await latin.processImage(InputImage.fromFilePath(p))).text,
    'mlkit_rows': (p) async =>
        _rows(await latin.processImage(InputImage.fromFilePath(p))),
    'mlkit_chinese': (p) async =>
        (await chinese.processImage(InputImage.fromFilePath(p))).text,
    'tesseract_fast': (p) =>
        FlutterTesseractOcr.extractText(p, language: 'por'),
    'tesseract_best': (p) =>
        FlutterTesseractOcr.extractText(p, language: 'porbest'),
    'paddle_native': _paddle(paddle, const PaddleOcrConfig()),
    'paddle_b1': _paddle(paddle, const PaddleOcrConfig(recBatchSize: 1)),
    'paddle_hi': _paddle(paddle, const PaddleOcrConfig(detLimitSideLen: 1536)),
    'paddle_hi_b1': _paddle(
        paddle, const PaddleOcrConfig(detLimitSideLen: 1536, recBatchSize: 1)),
    'paddle_split': _paddle(paddle, const PaddleOcrConfig(), split: true),
  };

  final out = <String, dynamic>{};
  for (final e in engines.entries.where((e) => only.isEmpty || e.key == only)) {
    final rows = <String, dynamic>{};
    final warm = Stopwatch()..start();
    try {
      await e.value(images.first).timeout(const Duration(seconds: 120)); // warm-up, not counted
      rows['_warmup_ms'] = warm.elapsedMilliseconds;
    } catch (err) {
      out[e.key] = {'error': '$err'};
      debugPrint('OCRBENCH ${e.key} failed: $err');
      continue;
    }
    for (final img in images) {
      final name = img.split('/').last.replaceAll(RegExp(r'\.[A-Za-z]+$'), '');
      final sw = Stopwatch()..start();
      try {
        final text = await e.value(img).timeout(const Duration(seconds: 120));
        rows[name] = {
          'text': text,
          'ms': sw.elapsedMilliseconds,
          if (e.key.startsWith('paddle')) 'conf': _lastConf,
        };
      } catch (err) {
        rows[name] = {'text': '', 'ms': sw.elapsedMilliseconds, 'error': '$err'};
      }
    }
    out[e.key] = rows;
    debugPrint('OCRBENCH ${e.key} done');
    File('${docs.path}/results_${only.isEmpty ? 'all' : only}.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  }
  File('${docs.path}/done.txt').writeAsStringSync('done');
  debugPrint('OCRBENCH_DONE');
}

/// ML Kit returns blocks, which splits a table by column. Lines that sit on
/// the same row (centres within half a line height) are joined left to right.
String _rows(RecognizedText t) {
  final lines = [for (final b in t.blocks) ...b.lines]
    ..sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
  final rows = <List<TextLine>>[];
  for (final l in lines) {
    if (rows.isNotEmpty) {
      final last = rows.last.first.boundingBox;
      if ((l.boundingBox.center.dy - last.center.dy).abs() <
          0.5 * (last.height < l.boundingBox.height ? last.height : l.boundingBox.height)) {
        rows.last.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  return rows
      .map((r) => (r..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left)))
          .map((l) => l.text)
          .join(' '))
      .join('\n');
}

bool _paddleReady = false;

/// One engine per process: the plugin initialises only once, so each variant
/// is run alone (see only.txt).
Engine _paddle(PaddleOcr paddle, PaddleOcrConfig config, {bool split = false}) {
  Future<String> one(String p) async {
    final r = await paddle.recognize(p);
    _lastConf = r.results.isEmpty
        ? 0
        : r.results.map((e) => e.confidence).reduce((a, b) => a + b) /
            r.results.length;
    return r.results.map((e) => e.text).join(' ');
  }

  return (p) async {
    if (!_paddleReady) {
      await paddle.init(config: config, engine: const EngineConfig(numThreads: 4));
      _paddleReady = true;
    }
    if (!split) return one(p);
    // Two halves with a small overlap; each has fewer lines than the page.
    final image = img.decodeImage(File(p).readAsBytesSync())!;
    final cut = (image.height * 0.5).round();
    final overlap = (image.height * 0.03).round();
    final parts = [
      img.copyCrop(image, x: 0, y: 0, width: image.width, height: cut + overlap),
      img.copyCrop(image,
          x: 0, y: cut - overlap, width: image.width, height: image.height - cut + overlap),
    ];
    final texts = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final f = File('${p}_part$i.png')..writeAsBytesSync(img.encodePng(parts[i]));
      try {
        texts.add(await one(f.path));
      } finally {
        f.deleteSync();
      }
    }
    return texts.join(' ');
  };
}
