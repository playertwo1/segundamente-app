import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/prompts.dart';

void main() {
  test('card prompt asks for a clean, topic-based write-up of documents', () {
    final prompt = Prompts.timelineCardSkillSystemPrompt('templates', 'lang');

    expect(prompt, contains('Lead with the conclusion'));
    expect(prompt, contains('exactly one owner'));
    expect(prompt, contains('columns Owner, Action, Due'));
    expect(prompt, contains('not stated'));
    expect(prompt, contains('Never add facts'));
    expect(prompt, contains('never under Decisions'));
  });

  test('pkm prompt keeps meeting records in one stable structure', () {
    final prompt = Prompts.pkmSkillSystemPrompt('/wd', 'tree', 'lang', 'lang');

    expect(prompt, contains('Meeting records'));
    expect(prompt, contains('update it in place'));
  });
}
