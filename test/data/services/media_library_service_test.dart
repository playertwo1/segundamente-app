import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/media_library_service.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/media_library_item.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:path/path.dart' as p;

void main() {
  test('classifyMediaKind maps photo, pdf, audio and ignores others', () {
    expect(classifyMediaKind('a.jpg'), MediaLibraryKind.photo);
    expect(classifyMediaKind('b.PNG'), MediaLibraryKind.photo);
    expect(classifyMediaKind('c.pdf'), MediaLibraryKind.pdf);
    expect(classifyMediaKind('d.m4a'), MediaLibraryKind.audio);
    expect(classifyMediaKind('e.mp3'), MediaLibraryKind.audio);
    expect(classifyMediaKind('notes.md'), isNull);
    expect(classifyMediaKind('temp.tmp'), isNull);
  });

  test('listAll scans assets dir, sorts newest-first, and links cards',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('media_lib_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final photoFile = File(p.join(tempDir.path, 'img_1.png'));
    final pdfFile = File(p.join(tempDir.path, 'doc_1.pdf'));
    final audioFile = File(p.join(tempDir.path, 'rec_1.m4a'));
    final ignoredFile = File(p.join(tempDir.path, 'ignored.txt'));

    await photoFile.writeAsBytes([1, 2, 3]);
    await pdfFile.writeAsBytes([4, 5, 6, 7]);
    await audioFile.writeAsBytes([8, 9]);
    await ignoredFile.writeAsString('ignore');

    await photoFile.setLastModified(DateTime(2026, 11, 10));
    await pdfFile.setLastModified(DateTime(2026, 11, 15));
    await audioFile.setLastModified(DateTime(2026, 11, 20));

    final service = MediaLibraryService(
      getAssetsDir: () async => tempDir.path,
      loadCards: () async => [
        TimelineCardModel(
          id: 'card-pdf',
          timestamp: DateTime(2026, 11, 15),
          tags: const [],
          status: 'completed',
          uiConfigs: const [],
          title: 'Contrato PDF',
          assets: [AssetData(type: 'pdf', url: 'fs://doc_1.pdf')],
        ),
        TimelineCardModel(
          id: 'card-photo',
          timestamp: DateTime(2026, 11, 10),
          tags: const [],
          status: 'completed',
          uiConfigs: const [],
          title: 'Foto da lousa',
          assets: [AssetData(type: 'img', url: 'http://localhost/assets/img_1.png')],
        ),
      ],
    );

    final items = await service.listAll();

    expect(items.map((e) => e.fileName), ['rec_1.m4a', 'doc_1.pdf', 'img_1.png']);
    expect(items[0].kind, MediaLibraryKind.audio);
    expect(items[0].cardId, isNull);
    expect(items[1].kind, MediaLibraryKind.pdf);
    expect(items[1].cardId, 'card-pdf');
    expect(items[1].cardTitle, 'Contrato PDF');
    expect(items[2].kind, MediaLibraryKind.photo);
    expect(items[2].cardId, 'card-photo');
  });
}
