import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/prompts.dart';

void main() {
  test('the brief names the card file of each new record', () {
    expect(Prompts.cardFileOfFact('2026/11/07.md#ts_2'),
        '/Cards/2026/11/07_ts_2.yaml');
    final brief = Prompts.knowledgeInsightAutoTaskBrief(
        ['2026/11/07.md#ts_2', '2026/11/06.md#ts_10']);
    expect(brief, contains('/Cards/2026/11/07_ts_2.yaml'));
    expect(brief, contains('/Cards/2026/11/06_ts_10.yaml'));
  });

  test('an id in another shape is left as it is', () {
    expect(Prompts.cardFileOfFact('weird'), 'weird');
  });
}
