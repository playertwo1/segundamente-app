import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/thread_document_service.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/report_export_fonts.dart';

void main() {
  const userId = 'chart-user';
  const md = '# Custos\n\n```chart\n{"title":"Custos","labels":["A","B"],'
      '"values":[10,20]}\n```\nFonte [c:k1]\n';

  testWidgets('the same chart goes to markdown, pdf and docx', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      await UserStorage.saveUser(userId);
      final dir = await Directory.systemTemp.createTemp('memex_chart_doc_');
      addTearDown(() => dir.delete(recursive: true));
      await FileSystemService.init(dir.path);
      final docs = ThreadDocumentService(loadFonts: testReportExportFonts);
      final doc = await docs.create(
        userId: userId,
        requestId: 'r',
        cardId: 'card',
        title: 'Custos',
        content: md,
        now: DateTime(2026, 11, 6),
      );
      Future<File> out(ReportExportFormat f) => docs.export(
          userId: userId, id: doc.id, version: 1, format: f);

      expect((await out(ReportExportFormat.markdown)).readAsStringSync(),
          contains('data:image/png;base64,'));
      expect(
          String.fromCharCodes(
              (await out(ReportExportFormat.pdf)).readAsBytesSync().take(5)),
          '%PDF-');
      final names = ZipDecoder()
          .decodeBytes((await out(ReportExportFormat.docx)).readAsBytesSync())
          .files
          .map((f) => f.name);
      expect(names, contains('word/media/report-image-1.png'));
      // The stored version keeps the block, not the picture.
      expect((await docs.load(userId, doc.id))!.latest.content, md);
    });
  });

  testWidgets('a record photo is drawn in, and one outside the record is not',
      (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      await UserStorage.saveUser(userId);
      final dir = await Directory.systemTemp.createTemp('memex_photo_doc_');
      addTearDown(() => dir.delete(recursive: true));
      await FileSystemService.init(dir.path);
      final photo = File(p.join(
          FileSystemService.instance.getAssetsPath(userId), '2026', 'foto.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
      final rel = p.relative(photo.path, from: dir.path).replaceAll(r'\', '/');
      const cardId = '2026/11/06.md#ts_1';
      await FileSystemService.instance.updateCardFile(
        userId,
        cardId,
        createIfNotExists: true,
        (card) => card.copyWith(assets: [rel]),
      );
      final docs = ThreadDocumentService(loadFonts: testReportExportFonts);
      const markdown = '# T\n```image\n{"asset":"REL","caption":"Quadro"}\n```\n'
          '```image\n{"asset":"../fora.png"}\n```';
      final text = await docs.render(
        userId,
        markdown.replaceFirst('REL', rel),
        cardId: cardId,
      );
      expect(text, contains('![Quadro](data:image/jpeg;base64,'));
      expect(text, contains('```image\n{"asset":"../fora.png"}\n```'));
    });
  });
}
