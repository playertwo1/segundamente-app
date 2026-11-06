import 'dart:io';
import 'dart:typed_data';

import 'package:memex/domain/models/session_report_export.dart';

/// Reads the bundled Inter files from disk, so tests need no asset bundle.
Future<ReportExportFonts> testReportExportFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = await File('google_fonts/$name').readAsBytes();
    return ByteData.sublistView(bytes);
  }

  return ReportExportFonts(
    regular: await read('Inter-Regular.ttf'),
    bold: await read('Inter-Bold.ttf'),
  );
}
