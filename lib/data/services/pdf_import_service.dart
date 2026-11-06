import 'dart:io';

import 'package:memex/data/services/chat_session_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/pdf_pages.dart';
import 'package:memex/utils/logger.dart';
import 'package:path/path.dart' as p;

enum PdfImportOutcome {
  stored,
  notConfirmed,
  needsSizeConfirmation,
  noSelectableText,
}

/// Sends a PDF to the model only after the user confirmed it, keeps the
/// original bytes, and stores the page text the model copied so a report can
/// quote and check it. The model never decides what the original says.
class PdfImportService {
  PdfImportService({
    FileSystemService? fileService,
    ChatSessionStorage? sessions,
  })  : _files = fileService ?? FileSystemService.instance,
        _sessions = sessions ?? ChatSessionStorage.instance;

  final FileSystemService _files;
  final ChatSessionStorage _sessions;
  final _logger = getLogger('PdfImportService');

  Future<PdfImportOutcome> importPdf({
    required String userId,
    required String sessionId,
    required List<int> pdfBytes,
    required bool confirmed,
    required bool confirmedLarge,
    required Future<String> Function(String system, List<int> pdf) askPdf,
  }) async {
    _checkId(sessionId);
    if (!_isPdf(pdfBytes)) throw ArgumentError('not a PDF');
    if (!confirmed) return PdfImportOutcome.notConfirmed;
    if (pdfNeedsSizeConfirmation(pdfBytes.length) && !confirmedLarge) {
      return PdfImportOutcome.needsSizeConfirmation;
    }

    final root = Directory(
      p.join(_files.getTranscriptImportsPath(userId), sessionId),
    );
    if (await root.exists()) throw StateError('import already stored');

    final pages = parsePdfPagesReply(
      await askPdf(pdfPagesSystemPrompt(), pdfBytes),
    );
    if (!pages.hasSelectableText) return PdfImportOutcome.noSelectableText;

    final dir = Directory(p.join(root.path, '0'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'original.bin')).writeAsBytes(
      pdfBytes,
      flush: true,
    );
    await File(p.join(dir.path, 'pages.json')).writeAsString(
      pagesJson(pages),
      flush: true,
    );

    final text =
        pages.toSegments().map((s) => '[${s.clock}] ${s.text}').join('\n');
    final now = DateTime.now().toIso8601String();
    await _sessions.createSession(
      userId: userId,
      sessionId: sessionId,
      metadata: {
        'session_id': sessionId,
        'agent_name': 'memex_agent',
        'title': _title(text),
        'created_at': now,
        'updated_at': now,
      },
      messages: [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text},
          ],
          'timestamp': now,
        },
      ],
    );
    _logger.info('Stored PDF import $sessionId (${pages.pages.length} pages)');
    return PdfImportOutcome.stored;
  }
}

bool _isPdf(List<int> bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2d;

void _checkId(String sessionId) {
  if (sessionId.isEmpty ||
      sessionId.contains('/') ||
      sessionId.contains('\\') ||
      sessionId == '.' ||
      sessionId == '..') {
    throw ArgumentError.value(sessionId, 'sessionId', 'invalid session id');
  }
}

String _title(String text) {
  final line = text.split('\n').first.trim();
  if (line.isEmpty) return 'PDF';
  return line.length > 50 ? line.substring(0, 50) : line;
}
