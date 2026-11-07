import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/thread_document.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/thread_document/view_models/thread_document_viewmodel.dart';
import 'package:memex/ui/thread_document/widgets/thread_document_prompts.dart';
import 'package:memex/ui/thread_document/widgets/thread_document_screen.dart';
import 'package:memex/ui/thread_document/widgets/thread_documents_section.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps documents in memory; the real storage and queue have their own tests.
class _FakeRouter implements MemexRouter {
  _FakeRouter(this.docs);

  List<ThreadDocument> docs;
  final requests = <Map<String, Object?>>[];
  var deleted = false;
  var staleOnEdit = false;

  @override
  Future<Result<List<ThreadDocument>>> listThreadDocuments(String cardId) async =>
      Ok([...docs]);

  @override
  Future<Result<ThreadDocument?>> loadThreadDocument(String id) async =>
      Ok(docs.firstWhere((d) => d.id == id));

  @override
  Future<Result<String>> requestThreadDocument({
    required String cardId,
    required String instruction,
    String? docId,
    int? expectedLatest,
    List<String> relatedIds = const [],
  }) async {
    requests.add({
      'instruction': instruction,
      'docId': docId,
      if (relatedIds.isNotEmpty) 'related': relatedIds,
    });
    return const Ok('req');
  }

  @override
  Future<Result<ThreadDocument>> editThreadDocument({
    required String id,
    required int expectedLatest,
    required String content,
  }) async {
    if (staleOnEdit) return Error(StaleDocumentEdit(expectedLatest, 9));
    final doc = docs.single.withVersion(_version(2, content,
        author: DocumentAuthor.user));
    docs = [doc];
    return Ok(doc);
  }

  @override
  Future<Result<String>> renderThreadDocument(String markdown) async =>
      Ok(markdown);

  var large = <({String asset, int bytes})>[];
  final confirmedPdfs = <String>[];

  @override
  Future<Result<List<({String asset, int bytes})>>> largePdfsAwaiting(
          String cardId) async =>
      Ok(large);

  @override
  Future<Result<void>> confirmLargePdf(String asset) async {
    confirmedPdfs.add(asset);
    large = [];
    return const Ok.v();
  }

  @override
  Future<Result<List<({String id, String title})>>> findRelatedRecords(
          String cardId, String query) async =>
      const Ok([(id: 'r1', title: 'Outra nota'), (id: 'r2', title: 'Mais uma')]);

  @override
  Future<Result<void>> deleteThreadDocument(String id) async {
    deleted = true;
    return const Ok.v();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DocumentVersion _version(
  int n,
  String content, {
  DocumentAuthor author = DocumentAuthor.model,
  List<String> warnings = const [],
}) =>
    DocumentVersion(
      number: n,
      author: author,
      content: content,
      createdAt: DateTime(2026, 11, 6, 12, n).toIso8601String(),
      warnings: warnings,
    );

ThreadDocument _doc({bool originDeleted = false, List<String> warnings = const []}) =>
    ThreadDocument(
      id: 'doc_1',
      requestId: 'r1',
      cardId: 'card',
      title: 'Proposta',
      createdAt: DateTime(2026, 11, 6).toIso8601String(),
      versions: [_version(1, '# Proposta\n\nTexto original.', warnings: warnings)],
      originDeleted: originDeleted,
    );

void main() {
  setUp(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  Future<void> pumpScreen(WidgetTester tester, _FakeRouter router) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ThreadDocumentScreen(
        viewModel: ThreadDocumentViewModel(router: router, docId: 'doc_1'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the text, the warnings and the origin note', (tester) async {
    await pumpScreen(
        tester, _FakeRouter([_doc(originDeleted: true, warnings: ['p.9'])]));
    expect(find.textContaining('Texto original.'), findsOneWidget);
    expect(find.byKey(const ValueKey('thread_doc_warnings')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('thread_doc_origin_deleted')), findsOneWidget);
  });

  testWidgets('a manual edit becomes version 2 and the old one stays',
      (tester) async {
    final router = _FakeRouter([_doc()]);
    await pumpScreen(tester, router);
    await tester.tap(find.byKey(const ValueKey('thread_doc_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('thread_doc_edit_text')), '# Meu texto');
    await tester.tap(find.byKey(const ValueKey('thread_doc_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Meu texto'), findsOneWidget);
    expect(find.byKey(const ValueKey('thread_doc_version_1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thread_doc_version_1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Texto original.'), findsOneWidget);
    expect(find.byKey(const ValueKey('thread_doc_edit')), findsNothing);
  });

  testWidgets('a stale edit shows the message and keeps the text', (tester) async {
    final router = _FakeRouter([_doc()])..staleOnEdit = true;
    await pumpScreen(tester, router);
    await tester.tap(find.byKey(const ValueKey('thread_doc_edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thread_doc_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thread_doc_stale')), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('thread_doc_stale')))
          .hasFlag(SemanticsFlag.isLiveRegion),
      isTrue,
    );
    semantics.dispose();
    expect(find.textContaining('Texto original.'), findsOneWidget);
  });

  testWidgets('revising queues a request for this document', (tester) async {
    final router = _FakeRouter([_doc()]);
    await pumpScreen(tester, router);
    await tester.enterText(
        find.byKey(const ValueKey('thread_doc_revise_text')), 'mais curto');
    await tester.tap(find.byKey(const ValueKey('thread_doc_revise')));
    await tester.pump();
    expect(router.requests.single,
        {'instruction': 'mais curto', 'docId': 'doc_1'});
    expect(find.byKey(const ValueKey('thread_doc_waiting')), findsOneWidget);
  });

  testWidgets('export offers markdown, pdf and docx', (tester) async {
    await pumpScreen(tester, _FakeRouter([_doc()]));
    await tester.tap(find.byKey(const ValueKey('thread_doc_export')));
    await tester.pumpAndSettle();
    for (final f in ['markdown', 'pdf', 'docx']) {
      expect(find.byKey(ValueKey('thread_doc_export_$f')), findsOneWidget);
    }
  });

  testWidgets('delete asks first and only then removes', (tester) async {
    final router = _FakeRouter([_doc()]);
    await pumpScreen(tester, router);
    await tester.tap(find.byKey(const ValueKey('thread_doc_delete')));
    await tester.pumpAndSettle();
    expect(router.deleted, isFalse);
    await tester.tap(find.byKey(const ValueKey('thread_doc_delete_confirm')));
    await tester.pumpAndSettle();
    expect(router.deleted, isTrue);
  });

  group('prompts', () {
    Future<bool?> ask(
        WidgetTester tester, Future<bool?> Function(BuildContext) open,
        String tapKey) async {
      bool? answer = true;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await open(context),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(tapKey)));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('deleting a record with documents: keep, delete or back out',
        (tester) async {
      expect(await ask(tester, (c) => askKeepDocuments(c, 2), 'thread_doc_keep_yes'), isTrue);
      expect(await ask(tester, (c) => askKeepDocuments(c, 2), 'thread_doc_keep_no'), isFalse);
      expect(await ask(tester, (c) => askKeepDocuments(c, 2), 'thread_doc_keep_cancel'), isNull);
    });

    testWidgets('a comment that asks for a document: create or just comment',
        (tester) async {
      expect(await ask(tester, askCreateFromText, 'thread_doc_text_yes'), isTrue);
      expect(await ask(tester, askCreateFromText, 'thread_doc_text_no'), isFalse);
    });
  });

  group('section on the record', () {
    Future<void> pumpSection(WidgetTester tester, _FakeRouter router) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ThreadDocumentsSection(router: router, cardId: 'card'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the documents of the record', (tester) async {
      await pumpSection(tester, _FakeRouter([_doc()]));
      expect(find.byKey(const ValueKey('thread_doc_doc_1')), findsOneWidget);
    });

    testWidgets('nothing is queued until the user confirms', (tester) async {
      final router = _FakeRouter([]);
      await pumpSection(tester, router);
      await tester.tap(find.byKey(const ValueKey('thread_doc_create')));
      await tester.pumpAndSettle();
      expect(router.requests, isEmpty);
      await tester.tap(find.byKey(const ValueKey('thread_doc_create_cancel')));
      await tester.pumpAndSettle();
      expect(router.requests, isEmpty);

      await tester.tap(find.byKey(const ValueKey('thread_doc_create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('thread_doc_create_confirm')));
      await tester.pump();
      expect(router.requests, hasLength(1));
      expect(find.byKey(const ValueKey('thread_docs_preparing')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only the ticked related records are sent', (tester) async {
      final router = _FakeRouter([]);
      await pumpSection(tester, router);
      await tester.tap(find.byKey(const ValueKey('thread_doc_create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('thread_doc_related_find')));
      await tester.pumpAndSettle();
      expect(router.requests, isEmpty);
      await tester.tap(find.byKey(const ValueKey('thread_doc_related_r2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('thread_doc_create_confirm')));
      await tester.pump();
      expect(router.requests.single['related'], ['r2']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a large PDF waits for the user before it is sent',
        (tester) async {
      final router = _FakeRouter([])
        ..large = [(asset: 'a/big.pdf', bytes: 12 * 1024 * 1024)];
      await pumpSection(tester, router);
      expect(find.textContaining('12.0'), findsOneWidget);
      expect(router.confirmedPdfs, isEmpty);
      await tester.tap(find.byKey(const ValueKey('thread_doc_large_pdf_send')));
      await tester.pumpAndSettle();
      expect(router.confirmedPdfs, ['a/big.pdf']);
      expect(find.byKey(const ValueKey('thread_doc_large_pdf_send')), findsNothing);
    });
  });
}
