import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/data/services/pdf_import_service.dart';
import 'package:memex/data/services/session_report_service.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'pdf-import-user';
  late Directory tempDir;
  late PdfImportService imports;
  late SessionReportService reports;

  List<int> pdf(String id) =>
      File('test/fixtures/f9/$id.pdf').readAsBytesSync();

  // The reply a faithful model gives for a fixture, from its expected pages.
  String reply(String id) {
    final all = jsonDecode(
      File('test/fixtures/f9/paginas_esperadas.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final pages = (all[id] as Map<String, dynamic>).entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));
    return jsonEncode({
      'pages': [
        for (final e in pages)
          {'page': int.parse(e.key), 'text': e.value ?? ''},
      ],
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    await UserStorage.saveUser(userId);
    tempDir = await Directory.systemTemp.createTemp('memex_pdf_import_');
    await FileSystemService.init(tempDir.path);
    imports = PdfImportService();
    reports = SessionReportService();
  });

  tearDown(() async {
    await LocalAssetServer.stopServer();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<PdfImportOutcome> run(
    String id, {
    bool confirmed = true,
    bool confirmedLarge = false,
    List<int>? bytes,
    void Function()? onAsk,
  }) {
    return imports.importPdf(
      userId: userId,
      sessionId: 'pdf_$id',
      pdfBytes: bytes ?? pdf(id),
      confirmed: confirmed,
      confirmedLarge: confirmedLarge,
      askPdf: (system, _) async {
        onAsk?.call();
        return reply(id);
      },
    );
  }

  String importDir(String id) => p.join(
        FileSystemService.instance.getTranscriptImportsPath(userId),
        'pdf_$id',
      );

  test('nothing is sent or written without confirmation', () async {
    var asked = false;
    final outcome =
        await run('c36', confirmed: false, onAsk: () => asked = true);
    expect(outcome, PdfImportOutcome.notConfirmed);
    expect(asked, isFalse);
    expect(Directory(importDir('c36')).existsSync(), isFalse);
  });

  test('a big file asks again before it is sent', () async {
    var asked = false;
    final big = [...pdf('c36'), ...List.filled(10 * 1024 * 1024, 0x20)];
    expect(await run('c36', bytes: big, onAsk: () => asked = true),
        PdfImportOutcome.needsSizeConfirmation);
    expect(asked, isFalse);
    expect(await run('c36', bytes: big, confirmedLarge: true),
        PdfImportOutcome.stored);
  });

  test('a scanned PDF stores nothing and says so', () async {
    expect(await run('c39'), PdfImportOutcome.noSelectableText);
    expect(Directory(importDir('c39')).existsSync(), isFalse);
  });

  test('refuses a file that is not a PDF', () async {
    await expectLater(
      run('c36', bytes: utf8.encode('Reunião de hoje')),
      throwsArgumentError,
    );
  });

  test('keeps the original bytes and reports the page as evidence', () async {
    expect(await run('c36'), PdfImportOutcome.stored);
    expect(
      File(p.join(importDir('c36'), '0', 'original.bin')).readAsBytesSync(),
      pdf('c36'),
    );

    final segments = await reports.importedSegments(userId, 'pdf_c36');
    expect(segments.map((s) => s.clock), ['p.1', 'p.2']);

    final report = await reports.applyModelJson(
      userId: userId,
      sessionId: 'pdf_c36',
      kind: ReportKind.reuniao,
      customTitle: null,
      json: reportModelReplyJson(jsonEncode({
        'items': [
          {
            'kind': 'decision',
            'text': 'Revisar o orçamento',
            'segment_id': segments[1].id,
            'excerpt': 'Ficou decidido que o orçamento será revisado.',
          },
        ],
      })),
    );
    expect(report.items.single.source.clock, 'p.2');
    expect(report.items.single.assignee, reportAssigneeUnknown);
  });

  test('a quote from the wrong page is refused', () async {
    await run('c36');
    final segments = await reports.importedSegments(userId, 'pdf_c36');
    await expectLater(
      reports.applyModelJson(
        userId: userId,
        sessionId: 'pdf_c36',
        kind: ReportKind.reuniao,
        customTitle: null,
        json: reportModelReplyJson(jsonEncode({
          'items': [
            {
              'kind': 'decision',
              'text': 'Revisar o orçamento',
              'segment_id': segments[0].id,
              'excerpt': 'Ficou decidido que o orçamento será revisado.',
            },
          ],
        })),
      ),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('excerpt is not in'))),
    );
  });
}
