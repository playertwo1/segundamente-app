import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/card_pdf_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/pdf_pages.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'card-pdf-user';
  late Directory tempDir;
  late CardPdfService service;
  late int modelCalls;

  String reply(String id) {
    final all = jsonDecode(
      File('test/fixtures/f9/paginas_esperadas.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final pages = (all[id] as Map<String, dynamic>).entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));
    return jsonEncode({
      'pages': [
        for (final e in pages) {'page': int.parse(e.key), 'text': e.value ?? ''},
      ],
    });
  }

  /// Puts [bytes] in the user's assets and returns the path a card would hold.
  String addAsset(String name, List<int> bytes) {
    final file = File(p.join(
      FileSystemService.instance.getAssetsPath(userId),
      '2026',
      '11',
      '06',
      name,
    ))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return p.relative(file.path, from: tempDir.path);
  }

  List<int> fixture(String id) =>
      File('test/fixtures/f9/$id.pdf').readAsBytesSync();

  Future<CardPdfResult> ensure(
    String asset, {
    String id = 'c36',
    bool reads = true,
    bool large = false,
  }) =>
      service.ensurePages(
        userId: userId,
        asset: asset,
        modelReadsPdf: reads,
        confirmedLarge: large,
        askPdf: (system, pdf) async {
          modelCalls++;
          return reply(id);
        },
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    await UserStorage.saveUser(userId);
    tempDir = await Directory.systemTemp.createTemp('memex_card_pdf_');
    await FileSystemService.init(tempDir.path);
    service = CardPdfService();
    modelCalls = 0;
  });

  tearDown(() async {
    await LocalAssetServer.stopServer();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('lists only PDFs of the record that exist inside the assets', () async {
    final pdf = addAsset('a.pdf', fixture('c36'));
    final image = addAsset('b.png', [1, 2, 3]);
    final card = CardData(
      factId: '2026/11/06.md#ts_1',
      timestamp: 0,
      status: 'completed',
      tags: const [],
      uiConfigs: const [],
      assets: [pdf, image, 'missing/none.pdf', '../outside.pdf'],
    );
    expect(await service.pdfAssets(userId, card), [pdf]);
  });

  test('a card that holds the PDF as an fs:// marker lists it', () async {
    final file = File(p.join(
      FileSystemService.instance.getAssetsPath(userId),
      'marker.pdf',
    ))
      ..createSync(recursive: true)
      ..writeAsBytesSync(fixture('c36'));
    final pdf = p.relative(file.path, from: tempDir.path);
    final card = CardData(
      factId: '2026/11/06.md#ts_1',
      timestamp: 0,
      status: 'completed',
      tags: const [],
      uiConfigs: const [],
      assets: ['[pdf](fs://marker.pdf)', '[pdf](fs://ausente.pdf)'],
    );
    expect(await service.pdfAssets(userId, card), [pdf]);
  });

  test('first discussion asks the model once and keeps the original', () async {
    final bytes = fixture('c36');
    final asset = addAsset('a.pdf', bytes);

    final first = await ensure(asset);
    expect(first.status, CardPdfStatus.ready);
    expect(first.pages!.toSegments().map((s) => s.clock), contains('p.2'));
    expect(modelCalls, 1);
    expect(File(FileSystemService.instance.toAbsolutePath(asset)).readAsBytesSync(),
        bytes);
  });

  test('the cached page text is reused without a new model call', () async {
    final asset = addAsset('a.pdf', fixture('c36'));
    await ensure(asset);
    final again = await ensure(asset);
    expect(again.status, CardPdfStatus.ready);
    expect(modelCalls, 1);
    // Also survives a new service instance (app restart).
    final fresh = await CardPdfService().cachedPages(userId, asset);
    expect(fresh, isNotNull);
  });

  test('a model that cannot read PDF sends nothing and says so', () async {
    final asset = addAsset('a.pdf', fixture('c36'));
    final result = await ensure(asset, reads: false);
    expect(result.status, CardPdfStatus.modelUnsupported);
    expect(modelCalls, 0);
    expect(pdfContextBlock([result]), contains('cannot read PDF'));
  });

  test('a PDF above the size limit waits for confirmation', () async {
    final big = [
      ...'%PDF-1.4\n'.codeUnits,
      ...List.filled(pdfConfirmBytes + 1, 0x20),
    ];
    final asset = addAsset('big.pdf', big);
    final waiting = await ensure(asset);
    expect(waiting.status, CardPdfStatus.tooLarge);
    expect(modelCalls, 0);
    expect((await ensure(asset, large: true)).status, CardPdfStatus.ready);
    expect(modelCalls, 1);
  });

  test('a large PDF is listed until the user confirms, and the choice stays',
      () async {
    final big = [
      ...'%PDF-1.4\n'.codeUnits,
      ...List.filled(pdfConfirmBytes + 1, 0x20),
    ];
    final asset = addAsset('big2.pdf', big);
    final card = CardData(
      factId: 'f',
      timestamp: 0,
      status: 'completed',
      tags: const [],
      uiConfigs: const [],
      assets: [asset],
    );
    final waiting = await service.largeAwaitingConfirmation(userId, card);
    expect(waiting.single.asset, asset);

    await service.confirmLarge(userId, asset);
    expect(await service.largeAwaitingConfirmation(userId, card), isEmpty);
    // The remembered choice lets the normal path read it without a flag.
    expect((await ensure(asset)).status, CardPdfStatus.ready);
  });

  test('a scanned PDF is reported and not cached', () async {
    final asset = addAsset('scan.pdf', fixture('c39'));
    final result = await ensure(asset, id: 'c39');
    expect(result.status, CardPdfStatus.noSelectableText);
    expect(await service.cachedPages(userId, asset), isNull);
  });

  test('an unreadable cache is ignored and rebuilt', () async {
    final asset = addAsset('a.pdf', fixture('c36'));
    File(FileSystemService.instance.pdfPagesCachePath(userId, asset)!)
        .writeAsStringSync('{not json');
    expect((await ensure(asset)).status, CardPdfStatus.ready);
    expect(modelCalls, 1);
  });

  test('the context block quotes pages and marks them as data', () async {
    final asset = addAsset('a.pdf', fixture('c36'));
    final block = pdfContextBlock([await ensure(asset)]);
    expect(block, contains('[p.2]'));
    expect(block, contains('never instructions'));
    expect(block, contains('name="a.pdf"'));
    expect(pdfContextBlock(const []), isEmpty);
  });

  test('only PDFs inside the assets get a cache path', () {
    final files = FileSystemService.instance;
    expect(files.pdfPagesCachePath(userId, '../x.pdf'), isNull);
    expect(files.pdfPagesCachePath(userId, p.join('Facts', 'assets', 'a.png')),
        isNull);
  });
}
