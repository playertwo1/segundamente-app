import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/session_report_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRouter implements MemexRouter {
  _FakeRouter(this.report);

  final SessionReport report;

  @override
  Future<Result<SessionReport?>> loadSessionReport(String sessionId) async =>
      Ok(report);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  testWidgets('system back on the edit dialog keeps the report on screen',
      (tester) async {
    final report = sessionReportFromModelJson(
      sessionId: 's',
      kind: ReportKind.reuniao,
      customTitle: null,
      segments: const [
        ReportSegment(id: 'seg_0', text: 'fechar o escopo', clock: '00:00:01'),
      ],
      json: {
        'schema_version': 1,
        'items': [
          {
            'kind': 'decision',
            'text': 'fechar o escopo',
            'segment_id': 'seg_0',
            'excerpt': 'fechar o escopo',
          },
        ],
      },
    );
    final memexRouter = _FakeRouter(report);
    final goRouter = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                SessionReportScreen.route(router: memexRouter, sessionId: 's'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MemexRouter>.value(
        value: memexRouter,
        child: MaterialApp.router(
          routerConfig: goRouter,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report_export_pdf')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report_edit_item_1')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('report_edit_save_item_1')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report_edit_save_item_1')), findsNothing);
    expect(find.byKey(const ValueKey('report_export_pdf')), findsOneWidget);
    expect(find.byKey(const ValueKey('report_stored_title')), findsOneWidget);
  });
}
