import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/insight_trigger.dart';
import 'package:memex/domain/models/knowledge_insight_card.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    EventBusService.instance.clearHandlers();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  tearDown(EventBusService.instance.clearHandlers);

  Future<void> untilIdle(InsightViewModel vm) async {
    while (vm.analyzing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('analyzing waits for the run to end, then reloads the list', () async {
    final router = _RunRouter(
      runs: [
        const InsightRunStatus(running: true),
        const InsightRunStatus(running: true),
        InsightRunStatus(
          outcome: InsightOutcome.noPattern,
          detail: 'sem padrao',
          at: DateTime(2026, 11, 8),
        ),
      ],
    );
    final vm = InsightViewModel(router: router)
      ..pollEvery = const Duration(milliseconds: 5);
    addTearDown(vm.dispose);

    final started = vm.analyzeNow();
    expect(vm.analyzing, isTrue);
    await started;
    await untilIdle(vm);

    expect(router.requests, 1);
    expect(router.loads, 1, reason: 'the list is reloaded once at the end');
    expect(vm.lastRun!.outcome, InsightOutcome.noPattern);
    expect(vm.lastRun!.detail, 'sem padrao');
  });

  test('a second tap while analyzing asks for nothing more', () async {
    final router = _RunRouter(runs: [const InsightRunStatus(running: true)]);
    final vm = InsightViewModel(router: router)
      ..pollEvery = const Duration(milliseconds: 5)
      ..maxPolls = 2;
    addTearDown(vm.dispose);

    final first = vm.analyzeNow();
    await vm.analyzeNow();
    await first;
    await untilIdle(vm);

    expect(router.requests, 1);
  });

  test('a failed request leaves the screen idle with a message', () async {
    final router = _RunRouter(runs: const [], requestFails: true);
    final vm = InsightViewModel(router: router);
    addTearDown(vm.dispose);

    await vm.analyzeNow();

    expect(vm.analyzing, isFalse);
    expect(vm.errorMessage, UserStorage.l10n.insightAnalyzeFailed);
  });
}

class _RunRouter implements MemexRouter {
  _RunRouter({required this.runs, this.requestFails = false});

  final List<InsightRunStatus> runs;
  final bool requestFails;
  var requests = 0;
  var loads = 0;

  @override
  Future<Result<bool>> requestInsightAnalysis() async {
    requests++;
    return requestFails ? Error(StateError('down')) : const Ok(true);
  }

  @override
  Future<Result<InsightRunStatus?>> latestInsightRun() async {
    final run = runs.length > 1 ? runs.removeAt(0) : runs.firstOrNull;
    return Ok(run);
  }

  @override
  Future<Result<List<KnowledgeInsightCard>>> fetchKnowledgeInsights() async {
    loads++;
    return const Ok([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
