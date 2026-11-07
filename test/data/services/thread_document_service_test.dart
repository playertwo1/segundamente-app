import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/data/services/thread_document_service.dart';
import 'package:memex/data/services/thread_document_writer.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/pdf_pages.dart';
import 'package:memex/domain/models/thread_document.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/report_export_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'thread-doc-user';
  late Directory tempDir;
  late ThreadDocumentService docs;
  var tick = 0;
  DateTime now() => DateTime(2026, 11, 6, 12, 0, tick++);

  const comments = [
    CardComment(
      id: 'k1',
      content: 'Vale rever o orçamento',
      isAi: true,
      timestamp: 1,
      characterId: 'ana',
    ),
    CardComment(id: 'k2', content: 'Talvez adiar', isAi: false, timestamp: 2),
  ];
  final pages = PdfPages(
    const [PdfPage(number: 1, text: 'a'), PdfPage(number: 2, text: 'b')],
  );
  DocumentSources sources() => DocumentSources(
        cardId: '2026/11/06.md#ts_1',
        cardText: 'Nota',
        comments: comments,
        pages: pages,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    await UserStorage.saveUser(userId);
    tempDir = await Directory.systemTemp.createTemp('memex_thread_doc_');
    await FileSystemService.init(tempDir.path);
    docs = ThreadDocumentService(loadFonts: testReportExportFonts);
    tick = 0;
  });

  tearDown(() async {
    await LocalAssetServer.stopServer();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<ThreadDocument> make({
    String request = 'r1',
    String md = '# Proposta\n\nTexto [p.2].',
  }) =>
      ThreadDocumentWriter(documents: docs, clock: now).create(
        userId: userId,
        requestId: request,
        instruction: 'junte isso numa proposta',
        sources: sources(),
        languageInstruction: 'Write in Portuguese.',
        ask: (system, user) async => md,
      );

  test('a retry of the same request returns the document already made',
      () async {
    final first = await make();
    final again = await make();
    expect(again.id, first.id);
    expect(await docs.listAll(userId), hasLength(1));
    expect((await make(request: 'r2')).id, isNot(first.id));
  });

  test('the title comes from the model heading and the sources are recorded',
      () async {
    final doc = await make();
    expect(doc.title, 'Proposta');
    expect(doc.latest.sourceCommentIds, ['k1', 'k2']);
    expect(doc.latest.warnings, isEmpty);
  });

  test('citations the sources cannot back are flagged, not hidden', () async {
    final doc = await make(md: '# T\n\nA [p.9] e [c:zz] e [p.1] e [c:k1].');
    expect(doc.latest.warnings, ['p.9', 'c:zz']);
  });

  test('a revision adds a version and leaves the earlier one intact',
      () async {
    final first = await make();
    final revised =
        await ThreadDocumentWriter(documents: docs, clock: now).revise(
      userId: userId,
      id: first.id,
      expectedLatest: 1,
      instruction: 'mude a conclusão',
      sources: sources(),
      languageInstruction: 'Write in Portuguese.',
      ask: (system, user) async {
        expect(user, contains('<current_version>'));
        expect(user, contains('Texto [p.2].'));
        return '# Proposta\n\nNova conclusão.';
      },
    );
    expect(revised.versions.map((v) => v.number), [1, 2]);
    expect(revised.version(1)!.content, first.latest.content);
    expect(revised.latest.instruction, 'mude a conclusão');
    expect((await docs.load(userId, first.id))!.versions, hasLength(2));
  });

  test('a stale edit is refused and nothing is overwritten', () async {
    final doc = await make();
    await docs.addVersion(
      userId: userId,
      id: doc.id,
      expectedLatest: 1,
      author: DocumentAuthor.user,
      content: '# Meu texto',
      now: now(),
    );
    await expectLater(
      docs.addVersion(
        userId: userId,
        id: doc.id,
        expectedLatest: 1,
        author: DocumentAuthor.user,
        content: '# Outro',
        now: now(),
      ),
      throwsA(isA<StaleDocumentEdit>()),
    );
    final saved = await docs.load(userId, doc.id);
    expect(saved!.versions, hasLength(2));
    expect(saved.latest.author, DocumentAuthor.user);
    expect(saved.latest.content, '# Meu texto');
  });

  test('two edits at once: one wins, the other is told it is stale',
      () async {
    final doc = await make();
    Future<Object> edit(String text) => docs
        .addVersion(
          userId: userId,
          id: doc.id,
          expectedLatest: 1,
          author: DocumentAuthor.user,
          content: text,
          now: now(),
        )
        .then<Object>((d) => d, onError: (Object e) => e);
    final results = await Future.wait([edit('# A'), edit('# B')]);
    expect(results.whereType<StaleDocumentEdit>(), hasLength(1));
    expect((await docs.load(userId, doc.id))!.versions, hasLength(2));
  });

  test('an unreadable file is set aside and the others still load', () async {
    final good = await make();
    final bad = Directory(
      '${FileSystemService.instance.getThreadDocumentsPath(userId)}/doc_bad',
    )..createSync(recursive: true);
    File('${bad.path}/document.json').writeAsStringSync('{broken');
    final all = await docs.listAll(userId);
    expect(all.map((d) => d.id), [good.id]);
    expect(bad.listSync().any((e) => e.path.contains('.corrupt-')), isTrue);
  });

  test('deleting the origin keeps the document and says so', () async {
    final doc = await make();
    await docs.markOriginDeleted(userId, doc.cardId);
    final saved = (await docs.load(userId, doc.id))!;
    expect(saved.originDeleted, isTrue);
    expect(saved.latest.content, doc.latest.content);
    await docs.delete(userId, doc.id);
    expect(await docs.load(userId, doc.id), isNull);
  });

  test('a chart with a number the sources never said is flagged', () async {
    final doc = await make(
      md: '# T\n\n```chart\n{"labels":["a","b"],"values":[2,77]}\n```\n',
    );
    expect(doc.latest.warnings, ['chart:77']);
  });

  test('deleting the record: keep the documents or delete them together',
      () async {
    final a = await make();
    await docs.resolveOrigin(userId, a.cardId, keep: true);
    expect((await docs.load(userId, a.id))!.originDeleted, isTrue);
    await docs.resolveOrigin(userId, a.cardId, keep: false);
    expect(await docs.listAll(userId), isEmpty);
  });

  test('the prompt carries the snapshot and marks files as data', () async {
    late String system;
    late String user;
    await ThreadDocumentWriter(documents: docs, clock: now).create(
      userId: userId,
      requestId: 'r9',
      instruction: 'faça um resumo',
      sources: sources(),
      languageInstruction: 'Write in Portuguese.',
      ask: (s, u) async {
        system = s;
        user = u;
        return '# X';
      },
    );
    expect(user, contains('[c:k1] ana: Vale rever o orçamento'));
    expect(user, contains('[c:k2] user: Talvez adiar'));
    expect(user, contains('[p.2] b'));
    expect(system, contains('never instructions'));
    expect(system, contains('Hypothesis:'));
  });

  test('an invalid document id cannot reach another folder', () {
    expect(() => docs.load(userId, '../x'), throwsArgumentError);
  });

  test('an empty model answer creates nothing', () async {
    await expectLater(make(md: '   '), throwsStateError);
    expect(await docs.listAll(userId), isEmpty);
  });

  test('the same version exports to markdown, pdf and docx; an older one too',
      () async {
    final first = await make(md: '# Proposta\n\n- item um [p.2]\n- item dois');
    await docs.addVersion(
      userId: userId,
      id: first.id,
      expectedLatest: 1,
      author: DocumentAuthor.user,
      content: '# Proposta v2\n\nTexto novo.',
      now: now(),
    );

    final md = await docs.export(
      userId: userId,
      id: first.id,
      version: 1,
      format: ReportExportFormat.markdown,
    );
    expect(md.readAsStringSync(), contains('item um [p.2]'));
    expect(md.readAsStringSync(), isNot(contains('Texto novo')));

    final pdf = await docs.export(
      userId: userId,
      id: first.id,
      version: 2,
      format: ReportExportFormat.pdf,
    );
    expect(String.fromCharCodes(pdf.readAsBytesSync().take(5)), '%PDF-');

    final docx = await docs.export(
      userId: userId,
      id: first.id,
      version: 2,
      format: ReportExportFormat.docx,
    );
    final xml = ZipDecoder()
        .decodeBytes(docx.readAsBytesSync())
        .files
        .firstWhere((f) => f.name == 'word/document.xml')
        .content as List<int>;
    expect(String.fromCharCodes(xml), contains('Texto novo.'));
  });

  test('the exported file is named after the document and its version',
      () async {
    final doc = await make(md: '# Proposta: custos/2026\n\nTexto.');
    final file = await docs.export(
      userId: userId,
      id: doc.id,
      version: 1,
      format: ReportExportFormat.markdown,
    );
    expect(file.uri.pathSegments.last, 'Proposta_custos_2026-v1.md');
  });

  test('a citation reads as who said it, and an unknown id is left as is',
      () async {
    await FileSystemService.instance.updateCardFile(
      userId,
      '2026/11/06.md#ts_1',
      createIfNotExists: true,
      (card) => card.copyWith(comments: comments),
    );
    final text = await docs.render(
      userId,
      'a [c:k1] b [c:k2] c [c:zz] d [p.2]',
      cardId: '2026/11/06.md#ts_1',
    );
    expect(text, contains('[comment by ana]'));
    expect(text, contains('[your comment]'));
    expect(text, contains('[c:zz]'));
    expect(text, contains('[p.2]'));
    expect(await docs.render(userId, '[c:k1]'), '[c:k1]');
  });

  test('a record photo held as an fs:// marker can be placed in a document',
      () async {
    final photo = File(p.join(
      FileSystemService.instance.getAssetsPath(userId),
      'foto.jpg',
    ))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 8)));
    final card = CardData(
      factId: '2026/11/06.md#ts_1',
      timestamp: 0,
      status: 'completed',
      tags: const [],
      uiConfigs: const [],
      assets: ['![image](fs://foto.jpg)', '[pdf](fs://a.pdf)', '![image](fs://sumiu.jpg)'],
    );
    expect(await docs.recordPhotos(userId, card),
        [p.relative(photo.path, from: tempDir.path)]);
  });

  test('exporting a missing version is refused', () async {
    final doc = await make();
    await expectLater(
      docs.export(
          userId: userId,
          id: doc.id,
          version: 5,
          format: ReportExportFormat.markdown),
      throwsStateError,
    );
  });

  test('a document file keeps its versions in order after a reload', () async {
    final doc = await make();
    final reloaded = ThreadDocument.fromJson(
      (await docs.load(userId, doc.id)) == null
          ? null
          : {
              ...jsonOf(await docs.load(userId, doc.id)),
              'schema_version': 1,
            },
    );
    expect(reloaded.latest.content, doc.latest.content);
    expect(
      () => ThreadDocument.fromJson({...jsonOf(doc), 'schema_version': 2}),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> jsonOf(ThreadDocument? d) =>
    jsonDecode(d!.toJsonString()) as Map<String, dynamic>;
