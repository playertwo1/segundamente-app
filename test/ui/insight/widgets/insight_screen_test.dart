import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/insight_trigger.dart';
import 'package:memex/domain/models/knowledge_insight_card.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/insight/widgets/insight_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    EventBusService.instance.clearHandlers();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('insight_screen_test_user');
    await UserStorage.setLocale(const Locale('en'));
  });

  tearDown(() {
    EventBusService.instance.clearHandlers();
  });

  testWidgets('shows all insights without activity statistics navigation', (
    tester,
  ) async {
    final viewModel = InsightViewModel(router: MemexRouter())
      ..isLoading = false
      ..insights = [
        _insight(id: 'first', quote: 'First insight'),
        _insight(id: 'second', quote: 'Second insight'),
      ];
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InsightScreen(
            viewModel: viewModel,
            isEmbedded: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('First insight'), findsOneWidget);
    expect(find.text('Second insight'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user_stats_overview_card')),
      findsNothing,
    );
    expect(find.text('Activity stats'), findsNothing);
  });

  testWidgets('empty insight state contains no sample records', (tester) async {
    final viewModel = InsightViewModel(router: MemexRouter())
      ..isLoading = false
      ..insights = [];
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InsightScreen(viewModel: viewModel, isEmbedded: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(UserStorage.l10n.insightEmptyTitle), findsOneWidget);
    expect(find.text(UserStorage.l10n.insightEmptyBody), findsOneWidget);
    // Insights come on their own, and the user can ask for one now.
    expect(find.byKey(const ValueKey('insight_analyze_now')), findsOneWidget);
    expect(find.byKey(const ValueKey('insight_last_run')), findsNothing);
  });

  testWidgets('the empty state says why the last analysis found nothing',
      (tester) async {
    final viewModel = InsightViewModel(router: MemexRouter())
      ..isLoading = false
      ..insights = []
      ..lastRun = InsightRunStatus(
        outcome: InsightOutcome.noPattern,
        detail: 'Only one record about Atlas.',
        at: DateTime(2026, 11, 8, 17, 5),
      );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InsightScreen(viewModel: viewModel, isEmbedded: true),
        ),
      ),
    );
    await tester.pump();

    final message = tester
        .widget<Text>(find.byKey(const ValueKey('insight_last_run')))
        .data!;
    expect(message, contains('08/11 17:05'));
    expect(message, contains('Only one record about Atlas.'));
  });

  testWidgets('with insights the analyze button stays pinned while scrolling',
      (tester) async {
    final viewModel = InsightViewModel(router: MemexRouter())
      ..isLoading = false
      ..insights = List.generate(
        20,
        (index) => _insight(id: 'insight-$index', quote: 'Insight $index'),
      )
      ..lastRun = const InsightRunStatus(outcome: InsightOutcome.saved);
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InsightScreen(viewModel: viewModel, isEmbedded: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Insight 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('insight_analyze_now')), findsOneWidget);
  });

  testWidgets('while analyzing the button gives way to a progress note',
      (tester) async {
    final viewModel = InsightViewModel(router: MemexRouter())
      ..isLoading = false
      ..insights = []
      ..analyzing = true;
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InsightScreen(viewModel: viewModel, isEmbedded: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('insight_analyze_now')), findsNothing);
    expect(find.text(UserStorage.l10n.insightAnalyzing), findsOneWidget);
  });

  testWidgets('insight actions use labeled open buttons and can be dismissed',
      (tester) async {
    final viewModel = InsightViewModel(router: MemexRouter())
      ..isLoading = false
      ..insights = [_insight(id: 'first', quote: 'First insight')]
      ..activeCardId = 'first';
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InsightScreen(viewModel: viewModel, isEmbedded: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(UserStorage.l10n.reorderInsights), findsOneWidget);
    expect(find.text(UserStorage.l10n.delete), findsOneWidget);
    expect(find.byTooltip(UserStorage.l10n.cancel), findsOneWidget);

    await tester.tap(find.byTooltip(UserStorage.l10n.cancel));
    await tester.pump();
    expect(viewModel.activeCardId, isNull);
  });
}

KnowledgeInsightCard _insight({
  required String id,
  required String quote,
}) {
  return KnowledgeInsightCard(
    id: id,
    title: quote,
    html: '',
    createdAt: 0,
    isPinned: false,
    sortOrder: 0,
    tags: const [],
    widgetType: 'native',
    widgetTemplate: 'highlight_card_v1',
    widgetData: {'quote_content': quote},
  );
}
