import 'dart:io';

import 'package:flutter/services.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/session_report_service.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:path/path.dart' as p;

/// Inter is already bundled (OFL) for the app theme; it covers pt-BR plus
/// curly quotes, dashes, ellipsis and bullets.
Future<ReportExportFonts> loadReportExportFonts() async {
  return ReportExportFonts(
    regular: await rootBundle.load('google_fonts/Inter-Regular.ttf'),
    bold: await rootBundle.load('google_fonts/Inter-Bold.ttf'),
  );
}

class SessionReportExportService {
  SessionReportExportService({
    FileSystemService? fileService,
    SessionReportService? reports,
    Future<ReportExportFonts> Function()? loadFonts,
  })  : _files = fileService ?? FileSystemService.instance,
        _reports = reports ?? SessionReportService(),
        _loadFonts = loadFonts ?? loadReportExportFonts;

  final FileSystemService _files;
  final SessionReportService _reports;
  final Future<ReportExportFonts> Function() _loadFonts;

  Future<File> write({
    required String userId,
    required String sessionId,
    required ReportExportFormat format,
    required DateTime exportedAt,
    Set<String>? itemIds,
  }) async {
    final report = await _reports.load(userId: userId, sessionId: sessionId);
    if (report == null) throw StateError('report missing');
    final bytes = await exportSessionReportBytes(
      report: report,
      exportedAt: exportedAt,
      format: format,
      itemIds: itemIds,
      fonts: format == ReportExportFormat.pdf ? await _loadFonts() : null,
    );
    final file = File(
      p.join(
        _files.getSessionReportsPath(userId),
        sessionId,
        reportExportFileName(format),
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
