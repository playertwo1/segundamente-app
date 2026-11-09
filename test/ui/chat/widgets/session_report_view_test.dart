import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/session_report_view.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  const segments = [
    ReportSegment(
      id: 'seg_0',
      text: 'fechar o escopo',
      clock: '00:00:01',
    ),
    ReportSegment(
      id: 'seg_1',
      text: 'mandar o resumo',
      clock: '00:00:02',
    ),
  ];

  Future<void> pump(
    WidgetTester tester,
    SessionReport? report, {
    required Future<void> Function(ReportKind kind, String? customTitle)
        onDraft,
    required Future<void> Function({
      required String itemId,
      required String text,
      required String assignee,
      required String due,
      String? reason,
    }) onEdit,
    required Future<void> Function({
      required String itemId,
      required ReportItemStatus status,
      String? reason,
    }) onSetStatus,
    Future<void> Function(ReportExportFormat format, Set<String> itemIds)?
        onExport,
    Future<void> Function(String itemId)? onAddToTodo,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionReportView(
            report: report,
            onDraft: onDraft,
            onEdit: onEdit,
            onSetStatus: onSetStatus,
            onExport: onExport ?? (_, __) async {},
            onAddToTodo: onAddToTodo,
          ),
        ),
      ),
    );
  }

  testWidgets('a meeting and a study report show different sections',
      (tester) async {
    // Tall enough that the lazy list builds every section header.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final meeting = draftSessionReport(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: segments,
    );
    await pump(
      tester,
      meeting,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
    );

    expect(
        find.byKey(const ValueKey('report_section_decision')), findsOneWidget);
    expect(find.byKey(const ValueKey('report_section_question')), findsNothing);
    expect(find.text('Relatório de reunião'), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionReportView)),
    )!;
    expect(
      find.text(l10n.reportImagesUnavailable),
      findsOneWidget,
    );

    final study = draftSessionReport(
      sessionId: 's',
      kind: ReportKind.estudo,
      customTitle: null,
      segments: segments,
    );
    await pump(
      tester,
      study,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
    );
    expect(
        find.byKey(const ValueKey('report_section_question')), findsOneWidget);
    expect(find.byKey(const ValueKey('report_section_decision')), findsNothing);
    expect(find.text('Relatório de estudo'), findsOneWidget);
  });

  testWidgets('tapping a decision shows the exact source excerpt',
      (tester) async {
    final report = sessionReportFromModelJson(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: segments,
      json: {
        'schema_version': 1,
        'items': [
          {
            'kind': 'decision',
            'text': 'fechar o escopo',
            'segment_id': 'seg_0',
            'excerpt': 'fechar o escopo',
            'clock': '00:00:01',
          },
        ],
      },
    );
    await pump(
      tester,
      report,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
    );

    await tester.tap(find.byKey(const ValueKey('report_item_item_1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('report_source_excerpt_item_1')),
      findsOneWidget,
    );
    expect(find.text('fechar o escopo'), findsWidgets);
    expect(find.byKey(const ValueKey('report_source_clock_item_1')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('report_item_clock_item_1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('report_definitive_item_1')), findsNothing);
  });

  group('accessibility', () {
    SessionReport sample() => sessionReportFromModelJson(
          sessionId: 's',
          kind: ReportKind.reuniao,
          customTitle: null,
          segments: segments,
          json: {
            'schema_version': 1,
            'items': [
              {
                'kind': 'task',
                'text': 'mandar o resumo',
                'segment_id': 'seg_1',
                'excerpt': 'mandar o resumo',
                'clock': '00:00:02',
              },
            ],
          },
        );

    testWidgets('tap targets are large and labeled', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_Host(initial: sample()).wrap());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('large text does not overflow', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_Host(initial: sample()).wrap());
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a task becomes definitive only after approval', (tester) async {
    var report = sessionReportFromModelJson(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: segments,
      json: {
        'schema_version': 1,
        'items': [
          {
            'kind': 'task',
            'text': 'mandar o resumo',
            'segment_id': 'seg_1',
            'excerpt': 'mandar o resumo',
            'clock': '00:00:02',
            'status': 'approved',
            'assignee': 'Ana',
            'due': 'amanhã',
          },
        ],
      },
    );
    final host = _Host(initial: report);
    await tester.pumpWidget(host.wrap());
    expect(find.text(reportAssigneeUnknown), findsOneWidget);
    expect(find.text(reportDueUnknown), findsOneWidget);
    expect(
        find.byKey(const ValueKey('report_definitive_item_1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('report_approve_item_1')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('report_definitive_item_1')), findsOneWidget);
  });

  testWidgets('search hides other items and edit keeps the callback text',
      (tester) async {
    final report = draftSessionReport(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: segments,
    );
    String? edited;
    String? editReason;
    await pump(
      tester,
      report,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {
        edited = text;
        editReason = reason;
      },
      onSetStatus: ({required itemId, required status, reason}) async {},
    );

    await tester.enterText(
        find.byKey(const ValueKey('report_search')), 'fechar');
    await tester.pump();
    expect(find.byKey(const ValueKey('report_item_item_2')), findsNothing);
    expect(find.byKey(const ValueKey('report_item_item_1')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('report_search')), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report_edit_item_1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('report_edit_text_item_1')),
      'escopo fechado',
    );
    await tester.enterText(
      find.byKey(const ValueKey('report_edit_reason_item_1')),
      'alinhamento com liderança',
    );
    await tester.tap(find.byKey(const ValueKey('report_edit_save_item_1')));
    await tester.pumpAndSettle();
    expect(edited, 'escopo fechado');
    expect(editReason, 'alinhamento com liderança');
  });

  testWidgets('generate uses the selected kind', (tester) async {
    ReportKind? selected;
    await pump(
      tester,
      null,
      onDraft: (kind, _) async {
        selected = kind;
      },
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
    );

    await tester.tap(find.byKey(const ValueKey('report_kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report_kind_estudo')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report_generate')));
    await tester.pump();

    expect(selected, ReportKind.estudo);
  });

  testWidgets('export keeps only the checked item', (tester) async {
    final report = draftSessionReport(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: segments,
    );
    Set<String>? ids;
    ReportExportFormat? format;
    await pump(
      tester,
      report,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
      onExport: (nextFormat, nextIds) async {
        format = nextFormat;
        ids = nextIds;
      },
    );

    expect(find.byKey(const ValueKey('report_pdf_note')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report_export_item_item_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report_export_markdown')));
    await tester.pump();

    expect(format, ReportExportFormat.markdown);
    expect(ids, {'item_2'});
  });

  testWidgets('json export button passes only the checked items',
      (tester) async {
    final report = draftSessionReport(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: segments,
    );
    Set<String>? ids;
    ReportExportFormat? format;
    await pump(
      tester,
      report,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
      onExport: (nextFormat, nextIds) async {
        format = nextFormat;
        ids = nextIds;
      },
    );

    await tester.tap(find.byKey(const ValueKey('report_export_item_item_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report_export_docx')));
    await tester.pump();

    expect(format, ReportExportFormat.docx);
    expect(ids, {'item_2'});
  });

  SessionReport twoTasks() => SessionReport(
        schemaVersion: sessionReportSchemaVersion,
        sessionId: 's',
        kind: ReportKind.reuniao,
        title: 'Relatório de reunião',
        sections: sectionsFor(ReportKind.reuniao),
        items: const [
          ReportItem(
            id: 'item_1',
            kind: ReportItemKind.task,
            text: 'Enviar a proposta',
            status: ReportItemStatus.unconfirmed,
            assignee: 'Carlos',
            due: 'sexta',
            source: ReportSource(
              segmentId: 'seg_0',
              excerpt: 'Carlos envia a proposta',
              clock: 'p.1',
            ),
          ),
          ReportItem(
            id: 'item_2',
            kind: ReportItemKind.task,
            text: 'Enviar a proposta',
            status: ReportItemStatus.unconfirmed,
            assignee: reportAssigneeUnknown,
            due: '2026-11-21',
            duplicateOf: 'item_1',
            source: ReportSource(
              segmentId: 'seg_0',
              excerpt: 'Carlos envia a proposta',
              clock: 'p.1',
            ),
          ),
        ],
      );

  Future<List<String>> pumpTwoTasks(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final approved = <String>[];
    await pump(
      tester,
      twoTasks(),
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {
        if (status == ReportItemStatus.approved) approved.add(itemId);
      },
    );
    return approved;
  }

  testWidgets('a task with a loose due date asks before it is approved',
      (tester) async {
    final approved = await pumpTwoTasks(tester);

    await tester.tap(find.byKey(const ValueKey('report_approve_item_1')));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.reportAmbiguousDueTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report_ambiguous_back')));
    await tester.pumpAndSettle();
    expect(approved, isEmpty);

    await tester.tap(find.byKey(const ValueKey('report_approve_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report_ambiguous_confirm')));
    await tester.pumpAndSettle();
    expect(approved, ['item_1']);
  });

  testWidgets('an exact due date is approved without a question',
      (tester) async {
    final approved = await pumpTwoTasks(tester);
    await tester
        .ensureVisible(find.byKey(const ValueKey('report_approve_item_2')));
    await tester.tap(find.byKey(const ValueKey('report_approve_item_2')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(approved, ['item_2']);
  });

  testWidgets('only an approved task can be added to the to-do list',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final added = <String>[];
    final report = setReportItemStatus(
      twoTasks(),
      itemId: 'item_2',
      status: ReportItemStatus.approved,
    );
    await pump(
      tester,
      report,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
      onAddToTodo: (id) async => added.add(id),
    );
    expect(find.byKey(const ValueKey('report_add_todo_item_1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('report_add_todo_item_2')));
    await tester.pumpAndSettle();
    expect(added, ['item_2']);
  });

  testWidgets('without a to-do handler the button is not offered',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      setReportItemStatus(
        twoTasks(),
        itemId: 'item_2',
        status: ReportItemStatus.approved,
      ),
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
    );
    expect(find.byKey(const ValueKey('report_add_todo_item_2')), findsNothing);
  });

  testWidgets('a duplicate stays listed and says what it repeats',
      (tester) async {
    await pumpTwoTasks(tester);
    expect(
        find.byKey(const ValueKey('report_duplicate_item_2')), findsOneWidget);
    expect(find.byKey(const ValueKey('report_duplicate_item_1')), findsNothing);
    expect(find.byKey(const ValueKey('report_item_item_2')), findsOneWidget);
  });

  testWidgets('attached report images are labeled as visual references',
      (tester) async {
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('report_image_ui_'),
    ))!;
    addTearDown(() async {
      await LocalAssetServer.stopServer();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await tester.runAsync(() => FileSystemService.init(tempDir.path));
    final report = SessionReport(
      schemaVersion: sessionReportSchemaVersion,
      sessionId: 's',
      kind: ReportKind.reuniao,
      title: 'Relatório',
      sections: sectionsFor(ReportKind.reuniao),
      items: const [],
      images: const [
        ReportImage(
          relativePath: 'workspace/_test/Facts/assets/reference.png',
          name: 'reference.png',
          messageIndex: 2,
          messageTimestamp: '2026-11-02T15:01:00.000',
        ),
      ],
    );
    await pump(
      tester,
      report,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {},
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionReportView)),
    )!;
    expect(find.text(l10n.reportImagesDisclaimer), findsOneWidget);
    expect(
      find.text(l10n.reportImageSource(2, '2026-11-02T15:01:00.000')),
      findsOneWidget,
    );
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.initial});

  final SessionReport initial;

  Widget wrap() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: this),
    );
  }

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late SessionReport report = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SessionReportView(
      report: report,
      onDraft: (_, __) async {},
      onEdit: ({
        required itemId,
        required text,
        required assignee,
        required due,
        reason,
      }) async {},
      onSetStatus: ({required itemId, required status, reason}) async {
        setState(() {
          report = setReportItemStatus(
            report,
            itemId: itemId,
            status: status,
          );
        });
      },
    );
  }
}
