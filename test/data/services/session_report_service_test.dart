import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:memex/data/repositories/chat.dart';
import 'package:memex/data/services/chat_session_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/data/services/session_report_export_service.dart';
import 'package:memex/data/services/session_report_service.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:memex/agent/built_in_tools/related_sessions_tool.dart';
import 'package:memex/data/services/glossary_service.dart';
import 'package:memex/data/services/related_sessions_service.dart';
import 'package:memex/data/services/saved_view_service.dart';
import 'package:memex/data/services/topic_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/data/services/transcript_correction_service.dart';
import 'package:memex/data/services/transcript_import_service.dart';
import 'package:memex/domain/models/report_memory.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/glossary.dart';
import 'package:memex/domain/models/saved_view.dart';
import 'package:memex/domain/models/topic.dart';
import 'package:memex/domain/models/transcript_correction.dart';
import 'package:memex/domain/models/transcript_import.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/report_export_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'session-report-user';
  const sessionId = 'txt_report';
  late Directory tempDir;
  late SessionReportService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    await UserStorage.saveUser(userId);
    tempDir = await Directory.systemTemp.createTemp('memex_session_report_');
    await FileSystemService.init(tempDir.path);
    service = SessionReportService();
  });

  tearDown(() async {
    await TodoService.waitForAlarmSync();
    await LocalAssetServer.stopServer();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> storeTranscript() async {
    const raw = '00:01\nfechar o escopo\n00:02\nmandar o resumo\n';
    final bytes = utf8.encode(raw);
    await TranscriptImportService().saveIfConfirmed(
      userId: userId,
      sessionId: sessionId,
      sources: [TranscriptImport.parse(bytes)],
      confirmed: true,
    );
    return File(
      p.join(
        FileSystemService.instance.getTranscriptImportsPath(userId),
        sessionId,
        '0',
        'original.bin',
      ),
    );
  }

  Future<String> storeImageAsset() async {
    final source = File(p.join(tempDir.path, 'report-image.png'));
    await source.writeAsBytes(
      image_codec.encodePng(image_codec.Image(width: 8, height: 8)),
    );
    return (await FileSystemService.instance.saveAssetFromFile(
      userId: userId,
      sourcePath: source.path,
      assetType: 'img',
    ))
        .$2;
  }

  Future<void> storeChatSessionWithImage(String relativePath) async {
    await ChatSessionStorage.instance.appendMessage(
      userId: userId,
      sessionId: sessionId,
      message: {
        'role': 'user',
        'timestamp': '2026-11-02T15:01:00.000',
        'content': [
          {
            'type': 'image_url',
            'name': 'meeting.png',
            'image_url': {'filePath': relativePath},
          },
        ],
      },
    );
  }

  test('draft, edit and model json keep the original bytes', () async {
    final original = await storeTranscript();
    final bytes = await original.readAsBytes();

    final meeting = await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    final study = await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.estudo,
      customTitle: null,
    );

    expect(meeting.title, isNot(study.title));
    expect(study.items[1].kind, ReportItemKind.question);
    expect(await original.readAsBytes(), bytes);

    final edited = await service.editItem(
      userId: userId,
      sessionId: sessionId,
      itemId: 'item_2',
      text: 'enviar depois',
      assignee: 'Rafael',
      due: 'sexta',
    );
    expect(edited.items[1].text, 'enviar depois');
    expect(edited.items[1].source.excerpt, 'mandar o resumo');
    expect(await original.readAsBytes(), bytes);

    final applied = await service.applyModelJson(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
      json: {
        'schema_version': 1,
        'items': [
          {
            'kind': 'task',
            'text': 'mandar o resumo',
            'segment_id': 'seg_1',
            'excerpt': 'resumo',
            'clock': '00:00:02',
            'status': 'approved',
            'assignee': 'Ana',
            'due': 'amanhã',
          },
        ],
      },
    );
    expect(applied.items.single.status, ReportItemStatus.unconfirmed);
    expect(applied.items.single.assignee, reportAssigneeUnknown);
    expect(applied.items.single.due, reportDueUnknown);
    expect(await original.readAsBytes(), bytes);
  });

  test('report images only include valid images attached by the user',
      () async {
    await storeTranscript();
    final relativePath = await storeImageAsset();
    await ChatSessionStorage.instance.appendMessage(
      userId: userId,
      sessionId: sessionId,
      message: {
        'role': 'user',
        'timestamp': '2026-11-02T15:01:00.000',
        'content': [
          {
            'type': 'image_url',
            'name': 'meeting.png',
            'image_url': {'filePath': relativePath},
          },
          {
            'type': 'image_url',
            'image_url': {'filePath': 'workspace/_other/Facts/assets/x.png'},
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'https://example.invalid/image.png'},
          },
        ],
      },
    );
    await ChatSessionStorage.instance.appendMessage(
      userId: userId,
      sessionId: sessionId,
      message: {
        'role': 'assistant',
        'timestamp': '2026-11-02T15:02:00.000',
        'content': [
          {
            'type': 'image_url',
            'image_url': {'filePath': relativePath},
          },
        ],
      },
    );

    final report = await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );

    expect(report.images, hasLength(1));
    expect(report.images.single.relativePath, relativePath);
    expect(report.images.single.name, 'meeting.png');
    expect(report.images.single.messageIndex, 2);
    expect(report.images.single.messageTimestamp, '2026-11-02T15:01:00.000');
  });

  test('loading a report hides image paths outside the owner assets', () async {
    await storeTranscript();
    final relativePath = await storeImageAsset();
    await storeChatSessionWithImage(relativePath);
    await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );

    final outsideImage = File(p.join(tempDir.path, 'private.png'));
    await outsideImage.writeAsBytes(
      await FileSystemService.instance.readUserImageAssetBytes(
        userId: userId,
        relativePath: relativePath,
      ),
    );
    final reportFile = File(p.join(
      FileSystemService.instance.getSessionReportsPath(userId),
      sessionId,
      'report.json',
    ));
    final stored = jsonDecode(await reportFile.readAsString()) as Map;
    final image = Map<String, dynamic>.from(
      (stored['images'] as List).single as Map,
    );
    stored['images'] = [
      image,
      {...image, 'relative_path': outsideImage.path, 'name': 'private.png'},
    ];
    await reportFile.writeAsString(jsonEncode(stored));

    final loaded = await service.load(userId: userId, sessionId: sessionId);
    expect(loaded!.images.map((image) => image.relativePath), [relativePath]);
  });

  test('editing a report task marks its copied Todo source as stale', () async {
    await storeTranscript();
    var report = await service.applyModelJson(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
      json: {
        'schema_version': 1,
        'items': [
          {
            'kind': 'task',
            'text': 'Mandar o resumo',
            'segment_id': 'seg_1',
            'excerpt': 'mandar o resumo',
            'clock': '00:00:02',
            'assignee': 'Rafael',
            'due': '2026-11-21',
          },
        ],
      },
    );
    report = await service.setStatus(
      userId: userId,
      sessionId: sessionId,
      itemId: report.items.single.id,
      status: ReportItemStatus.approved,
    );
    await TodoService().addFromReport(
      userId: userId,
      sessionId: sessionId,
      item: report.items.single,
    );

    await service.editItem(
      userId: userId,
      sessionId: sessionId,
      itemId: report.items.single.id,
      text: 'Mandar o resumo revisado',
      assignee: 'Rafael',
      due: '2026-11-21',
    );

    expect((await TodoService().load(userId)).single.sourceStale, isTrue);
  });

  test('an approved item blocks a new draft', () async {
    await storeTranscript();
    await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    await service.setStatus(
      userId: userId,
      sessionId: sessionId,
      itemId: 'item_1',
      status: ReportItemStatus.approved,
    );

    expect(
      () => service.draft(
        userId: userId,
        sessionId: sessionId,
        kind: ReportKind.estudo,
        customTitle: null,
      ),
      throwsStateError,
    );
    final kept = await service.load(userId: userId, sessionId: sessionId);
    expect(kept!.kind, ReportKind.reuniao);
  });

  test('version 0 on disk migrates to version 1', () async {
    final file = File(
      p.join(
        FileSystemService.instance.getSessionReportsPath(userId),
        sessionId,
        'report.json',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schema_version': 0,
        'session_id': sessionId,
        'type': 'study',
        'entries': [
          {
            'type': 'question',
            'body': 'qual o prazo',
            'segment_id': 'seg_0',
            'quote': 'qual o prazo',
          },
        ],
      }),
    );

    final loaded = await service.load(userId: userId, sessionId: sessionId);
    expect(loaded!.schemaVersion, sessionReportSchemaVersion);
    expect(loaded.kind, ReportKind.estudo);
    final stored = jsonDecode(await file.readAsString()) as Map;
    expect(stored['schema_version'], sessionReportSchemaVersion);
  });

  test('glossary terms persist and reach the model request', () async {
    await storeTranscript();
    await GlossaryService().update(
      userId,
      (t) => addGlossaryTerm(t, 'Alvarenga'),
    );
    String? system;
    await service.draftWithModel(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
      ask: (s, u) async {
        system = s;
        return '{"items":[]}';
      },
    );
    expect(system, contains('Alvarenga'));
    expect(await GlossaryService().load(userId), ['Alvarenga']);
  });

  test('corrections live in a separate file and never touch the original',
      () async {
    final original = await storeTranscript();
    final bytes = await original.readAsBytes();
    final corrections = TranscriptCorrectionService();

    expect(
      (await corrections.correctedSegments(userId, sessionId))[0].text,
      'fechar o escopo',
    );
    final corrected = await corrections.save(userId, sessionId, [
      const TextFix(segmentId: 'seg_0', from: 'escopo', to: 'escopo do site'),
    ]);
    expect(corrected[0].text, 'fechar o escopo do site');
    expect(await original.readAsBytes(), bytes);
    expect(
      File(p.join(original.parent.parent.path, 'corrections.json'))
          .existsSync(),
      isTrue,
    );
    expect(
      (await corrections.correctedSegments(userId, sessionId))[0].text,
      'fechar o escopo do site',
    );

    await expectLater(
      corrections.save(userId, sessionId, [
        const TextFix(segmentId: 'seg_0', from: 'nada', to: 'x'),
      ]),
      throwsA(isA<CorrectionRefused>()),
    );
    // The refused set did not replace the stored one.
    expect(await corrections.load(userId, sessionId), hasLength(1));
    expect(await original.readAsBytes(), bytes);
    await expectLater(
      corrections.save(userId, '../x', const []),
      throwsArgumentError,
    );
  });

  test('a report made after a correction reads the corrected text', () async {
    final original = await storeTranscript();
    final bytes = await original.readAsBytes();
    await GlossaryService()
        .update(userId, (t) => addGlossaryTerm(t, 'Escopos'));
    final corrections = TranscriptCorrectionService();
    final proposed = await corrections.suggest(userId, sessionId);
    expect(proposed.single.from, 'escopo');
    await corrections.save(userId, sessionId, proposed);

    final report = await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    expect(
        report.items.any((i) => i.source.excerpt.contains('Escopos')), isTrue);
    expect(await original.readAsBytes(), bytes);
  });

  test('saved views persist between loads', () async {
    expect(await SavedViewService().load(userId), isEmpty);
    await SavedViewService().update(
      userId,
      (v) => addSavedView(v, id: 'v1', name: 'Obra', tags: ['obra', 'tarefa']),
    );
    final back = await SavedViewService().load(userId);
    expect(back.single.name, 'Obra');
    expect(back.single.tags, ['obra', 'tarefa']);
  });

  test('related sessions: text seed, topic sibling, nothing for off-topic',
      () async {
    await storeTranscript();
    Future<void> store(String id, String line) =>
        TranscriptImportService().saveIfConfirmed(
          userId: userId,
          sessionId: id,
          sources: [TranscriptImport.parse(utf8.encode('00:01\n$line\n'))],
          confirmed: true,
        );
    await store('txt_irma', 'comprar cimento para a laje');
    await store('txt_solta', 'agendar o dentista');
    for (final id in [sessionId, 'txt_irma', 'txt_solta']) {
      await service.draft(
        userId: userId,
        sessionId: id,
        kind: ReportKind.reuniao,
        customTitle: null,
      );
    }
    await TopicService().update(userId, (t) {
      t = addTopic(t, id: 't1', name: 'Obra');
      t = linkSession(t, 't1', sessionId);
      return linkSession(t, 't1', 'txt_irma');
    });

    final found = await RelatedSessionsService().find(userId, 'escopo');
    expect(found.map((r) => r.sessionId), [sessionId, 'txt_irma']);
    expect(found.map((r) => r.isSeed), [true, false]);

    final report = await service.load(userId: userId, sessionId: 'txt_irma');
    final text = renderRelatedSession(found.last, report!);
    expect(text, contains('same topic'));
    expect(text, contains('cimento'));
    expect(text, isNot(contains('dentista')));

    expect(await RelatedSessionsService().find(userId, 'futebol'), isEmpty);
  });

  test('topics persist and deleting a session unlinks it from every topic',
      () async {
    await storeTranscript();
    final topics = TopicService();
    await topics.update(userId, (t) {
      t = addTopic(t, id: 't1', name: 'Obra', isProject: true);
      t = addTopic(t, id: 't2', name: 'Casa');
      t = linkSession(t, 't1', sessionId);
      t = linkSession(t, 't1', 'outra');
      return linkSession(t, 't2', sessionId);
    });
    final saved = await TopicService().load(userId);
    expect(saved.first.isProject, isTrue);
    expect(saved.first.sessionIds, [sessionId, 'outra']);

    expect(await deleteChatSessionEndpoint(sessionId), isTrue);
    final after = await topics.load(userId);
    expect(after.map((t) => t.name), ['Obra', 'Casa']);
    expect(after.first.sessionIds, ['outra']);
    expect(after.last.sessionIds, isEmpty);
  });

  test('deleting the session removes the report and the imported original',
      () async {
    final original = await storeTranscript();
    await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.livre,
      customTitle: null,
    );

    final removed = await deleteChatSessionEndpoint(sessionId);
    expect(removed, isTrue);
    expect(
      await service.load(userId: userId, sessionId: sessionId),
      isNull,
    );
    expect(await original.exists(), isFalse);
    expect(
      await ChatSessionStorage.instance.sessionExists(userId, sessionId),
      isFalse,
    );
  });

  test('export writes every format and delete removes the files', () async {
    final original = await storeTranscript();
    final bytes = await original.readAsBytes();
    final imagePath = await storeImageAsset();
    await storeChatSessionWithImage(imagePath);
    await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    final exporter = SessionReportExportService(
      loadFonts: testReportExportFonts,
    );
    final exportedAt = DateTime(2026, 11, 2, 15, 4);
    final written = <String>[];
    for (final format in ReportExportFormat.values) {
      final file = await exporter.write(
        userId: userId,
        sessionId: sessionId,
        format: format,
        exportedAt: exportedAt,
      );
      written.add(file.path);
      expect(await file.exists(), isTrue);
      expect(file.path, endsWith(reportExportFileName(format)));
      if (format == ReportExportFormat.markdown) {
        final markdown = await file.readAsString();
        expect(markdown, contains('![meeting.png](data:image/png;base64,'));
        expect(markdown, contains(UserStorage.l10n.reportImagesDisclaimer));
        expect(markdown, contains('Fonte: mensagem 2 2026-11-02T15:01:00.000'));
      } else if (format == ReportExportFormat.pdf) {
        expect(latin1.decode(await file.readAsBytes()),
            contains('/Subtype/Image'));
      } else if (format == ReportExportFormat.docx) {
        final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
        expect(archive.findFile('word/media/report-image-1.png'), isNotNull);
        final document = utf8.decode(
          archive.findFile('word/document.xml')!.content as List<int>,
        );
        expect(document, contains(UserStorage.l10n.reportImagesDisclaimer));
        expect(document, contains('Fonte: mensagem 2 2026-11-02T15:01:00.000'));
      }
    }
    expect(await original.readAsBytes(), bytes);

    final removed = await deleteChatSessionEndpoint(sessionId);
    expect(removed, isTrue);
    for (final path in written) {
      expect(await File(path).exists(), isFalse);
    }
    expect(await original.exists(), isFalse);
  });

  test('Markdown export states when no related images are available', () async {
    await storeTranscript();
    await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    final file = await SessionReportExportService().write(
      userId: userId,
      sessionId: sessionId,
      format: ReportExportFormat.markdown,
      exportedAt: DateTime(2026, 11, 2, 15, 4),
    );

    expect(
      await file.readAsString(),
      contains(UserStorage.l10n.reportImagesUnavailable),
    );
  });

  test('text search and revisions stay beside the report',
      () async {
    final original = await storeTranscript();
    const otherId = 'txt_other';
    await TranscriptImportService().saveIfConfirmed(
      userId: userId,
      sessionId: otherId,
      sources: [
        TranscriptImport.parse(utf8.encode('00:01\noutro assunto\n')),
      ],
      confirmed: true,
    );

    final meeting = await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    await service.draft(
      userId: userId,
      sessionId: otherId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    final followUp = meeting.items[1];

    await service.setStatus(
      userId: userId,
      sessionId: sessionId,
      itemId: followUp.id,
      status: ReportItemStatus.approved,
      at: '2026-11-02T15:04:00',
    );
    final found = await service.search(userId: userId, query: 'escopo');
    expect(found.single.sessionId, sessionId);
    expect(
        await service.search(userId: userId, query: 'assunto'), hasLength(1));

    await service.editItem(
      userId: userId,
      sessionId: sessionId,
      itemId: meeting.items.first.id,
      text: 'fechar depois',
      assignee: reportAssigneeUnknown,
      due: reportDueUnknown,
      at: '2026-11-02T15:05:00',
      reason: 'ajuste no cronograma',
    );
    await service.editItem(
      userId: userId,
      sessionId: sessionId,
      itemId: meeting.items.first.id,
      text: 'fechar depois',
      assignee: 'Ana',
      due: reportDueUnknown,
      at: '2026-11-02T15:06:00',
    );
    final changes = await service.latestTextChanges(userId: userId);
    final change = changes[reportHitKey(sessionId, meeting.items.first.id)];
    expect(change, isNotNull);
    expect(change!.before, 'fechar o escopo');
    expect(change.after, 'fechar depois');
    expect(change.reason, 'ajuste no cronograma');

    final loadedRevisions = await service.loadRevisions(
      userId: userId,
      sessionId: sessionId,
    );
    expect(loadedRevisions, isNotEmpty);
    expect(
        loadedRevisions.any((r) => r.reason == 'ajuste no cronograma'), isTrue);

    final byItem = await service.loadRevisions(
      userId: userId,
      sessionId: sessionId,
      itemId: meeting.items.first.id,
    );
    expect(byItem.first.reason, 'ajuste no cronograma');

    final nonExistent = await service.loadRevisions(
      userId: userId,
      sessionId: sessionId,
      itemId: 'non_existent',
    );
    expect(nonExistent, isEmpty);

    final revisions = File(
      p.join(
        FileSystemService.instance.getSessionReportsPath(userId),
        sessionId,
        'revisions.json',
      ),
    );
    expect(await revisions.exists(), isTrue);
    await service.deleteDerivatives(userId: userId, sessionId: sessionId);
    expect(await revisions.exists(), isFalse);
    expect(await original.exists(), isFalse);
  });

  test('model draft keeps verified items and fails over to the local draft',
      () async {
    await storeTranscript();
    String? sentText;

    final ok = await service.draftWithModel(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
      ask: (system, user) async {
        sentText = user;
        return '```json\n{"items":[{"kind":"decision","text":"Escopo fechado",'
            '"segment_id":"seg_0","excerpt":"fechar o escopo"}]}\n```';
      },
    );
    expect(sentText, contains('[seg_0 00:00:01] fechar o escopo'));
    expect(ok.modelError, isNull);
    expect(ok.report.items.single.kind, ReportItemKind.decision);
    expect(ok.report.items.single.status, ReportItemStatus.unconfirmed);

    final fallback = await service.draftWithModel(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
      ask: (system, user) async => '{"items":[{"kind":"decision","text":"x",'
          '"segment_id":"seg_0","excerpt":"texto que não existe"}]}',
    );
    expect(fallback.modelError, isA<FormatException>());
    expect(fallback.report.items.first.kind, ReportItemKind.summary);

    final failed = await service.draftWithModel(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
      ask: (system, user) async => throw const SocketException('offline'),
    );
    expect(failed.modelError, isA<SocketException>());
  });

  test('regenerating keeps every earlier version beside the report', () async {
    final original = await storeTranscript();
    final before = await original.readAsBytes();
    final dir = p.join(
      FileSystemService.instance.getSessionReportsPath(userId),
      sessionId,
    );

    final first = await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.reuniao,
      customTitle: null,
    );
    expect(File(p.join(dir, 'report.v1.json')).existsSync(), isFalse);

    await service.editItem(
      userId: userId,
      sessionId: sessionId,
      itemId: first.items.first.id,
      text: 'texto que eu corrigi',
      assignee: reportAssigneeUnknown,
      due: reportDueUnknown,
    );
    await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.brainstorm,
      customTitle: null,
    );
    await service.draft(
      userId: userId,
      sessionId: sessionId,
      kind: ReportKind.livre,
      customTitle: null,
    );

    final v1 =
        jsonDecode(File(p.join(dir, 'report.v1.json')).readAsStringSync());
    final v2 =
        jsonDecode(File(p.join(dir, 'report.v2.json')).readAsStringSync());
    expect(v1['items'].first['text'], 'texto que eu corrigi');
    expect(v1['kind'], 'reuniao');
    expect(v2['kind'], 'brainstorm');
    expect(File(p.join(dir, 'report.v3.json')).existsSync(), isFalse);
    expect(
      (await service.load(userId: userId, sessionId: sessionId))!.kind,
      ReportKind.livre,
    );
    // The user's own notes are the source and are never rewritten.
    expect(await original.readAsBytes(), before);

    await service.deleteDerivatives(userId: userId, sessionId: sessionId);
    expect(Directory(dir).existsSync(), isFalse);
  });

  test('a blank custom title or blank source never becomes a blank report', () {
    expect(
      () => titleFor(ReportKind.custom, '   '),
      throwsArgumentError,
    );
    expect(
      () => draftSessionReport(
        sessionId: sessionId,
        kind: ReportKind.livre,
        customTitle: null,
        segments: const [ReportSegment(id: 'seg_0', text: '  ')],
      ),
      throwsStateError,
    );
  });
}
