import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/insight_trigger.dart';

void main() {
  test('a finished task gives its outcome, reason and time', () {
    final run = InsightRunStatus.fromTask(
      status: 'completed',
      resultJson: '{"outcome":"noPattern","detail":"so um registro"}',
      completedAt: 1794168000,
    );
    expect(run.running, isFalse);
    expect(run.failed, isFalse);
    expect(run.outcome, InsightOutcome.noPattern);
    expect(run.detail, 'so um registro');
    expect(run.at, DateTime.fromMillisecondsSinceEpoch(1794168000 * 1000));
  });

  test('a waiting or retrying task is running; a failed one is not', () {
    for (final status in ['pending', 'processing', 'retrying']) {
      expect(InsightRunStatus.fromTask(status: status).running, isTrue,
          reason: status);
    }
    final failed = InsightRunStatus.fromTask(status: 'failed');
    expect(failed.running, isFalse);
    expect(failed.failed, isTrue);
  });

  test('an unreadable or unknown result only means no reason to show', () {
    expect(
      InsightRunStatus.fromTask(status: 'completed', resultJson: 'not json')
          .outcome,
      isNull,
    );
    expect(
      InsightRunStatus.fromTask(
              status: 'completed', resultJson: '{"outcome":"from_the_future"}')
          .outcome,
      isNull,
    );
  });

  test('the agent reason loses its no_op prefix', () {
    expect(insightReason('no_op - so ha um registro.'), 'so ha um registro.');
    expect(insightReason('`no_op`: sem padrao'), 'sem padrao');
    expect(insightReason('No_op. Registros de teste.'), 'Registros de teste.');
    expect(insightReason('completed'), 'completed');
  });
}
