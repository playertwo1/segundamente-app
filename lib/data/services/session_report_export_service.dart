import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_codec;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/session_report_service.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:path/path.dart' as p;
import 'package:memex/utils/user_storage.dart';

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
    final List<ReportExportImage> images = format == ReportExportFormat.json
        ? const []
        : await _exportImages(userId, report.images);
    final bytes = await exportSessionReportBytes(
      report: report,
      exportedAt: exportedAt,
      format: format,
      itemIds: itemIds,
      fonts: format == ReportExportFormat.pdf ? await _loadFonts() : null,
      images: images,
      imageDisclaimer: UserStorage.l10n.reportImagesDisclaimer,
      noImagesMessage: UserStorage.l10n.reportImagesUnavailable,
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

  Future<List<ReportExportImage>> _exportImages(
    String userId,
    List<ReportImage> reportImages,
  ) async {
    final exported = <ReportExportImage>[];
    for (final image in reportImages) {
      if (!await _files.isUserImageAsset(
        userId: userId,
        relativePath: image.relativePath,
      )) {
        throw StateError('Report image is missing: ${image.name}');
      }
      final path = _files.toAbsolutePath(image.relativePath);
      final png = p.extension(path).toLowerCase() == '.png';
      Uint8List? bytes;
      try {
        bytes = await FlutterImageCompress.compressWithFile(
          path,
          minWidth: 4096,
          minHeight: 4096,
          quality: png ? 100 : 92,
          format: png ? CompressFormat.png : CompressFormat.jpeg,
          autoCorrectionAngle: true,
          keepExif: false,
        );
      } on MissingPluginException {
        // Flutter tests do not load the native image compressor.
      } on PlatformException {
        // Unsupported native formats fall back to the bundled Dart decoder.
      } on UnimplementedError {
        // The Flutter test runner uses an unsupported platform implementation.
      }
      bytes ??= _normalizeImageBytes(
        await _files.readUserImageAssetBytes(
          userId: userId,
          relativePath: image.relativePath,
        ),
        png: png,
      );
      if (bytes == null || bytes.isEmpty) {
        throw FormatException('Unsupported report image: ${image.name}');
      }
      exported.add(
        ReportExportImage(
          name: image.name,
          bytes: bytes,
          mimeType: png ? 'image/png' : 'image/jpeg',
          messageIndex: image.messageIndex,
          messageTimestamp: image.messageTimestamp,
        ),
      );
    }
    return exported;
  }

  Uint8List? _normalizeImageBytes(Uint8List original, {required bool png}) {
    final decoded = image_codec.decodeImage(original);
    if (decoded == null) return null;
    final oriented = image_codec.bakeOrientation(decoded);
    return Uint8List.fromList(
      png ? image_codec.encodePng(oriented) : image_codec.encodeJpg(oriented),
    );
  }
}
