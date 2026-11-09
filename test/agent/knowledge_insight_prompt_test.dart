import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/prompts.dart';

void main() {
  group('Knowledge insight language prompts', () {
    const zhInstruction =
        '**Important**: All output text must be in **zh-CN (Simplified Chinese)**.';

    test('skill prompt interpolates the configured language instruction', () {
      final prompt = Prompts.knowledgeInsightSkillPrompt(
        zhInstruction,
      );

      expect(prompt, contains(zhInstruction));
      expect(prompt, isNot(contains(r'$instruction')));
    });

    test('the long skill prompt repeats no line and no section title', () {
      final prompt = Prompts.knowledgeInsightSkillPrompt('x');
      final lines = prompt
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^[\s*\-]+'), '').trim())
          .where((l) => l.length > 25)
          .toList();
      final repeated = {
        for (final l in lines)
          if (lines.where((o) => o == l).length > 1) l
      };
      expect(repeated, isEmpty);
      final titles = prompt.split('\n').where((l) => l.startsWith('## ')).toList();
      expect(titles.toSet().length, titles.length);
    });

    test('the automatic prompt keeps the evidence rules and the language', () {
      final prompt = Prompts.knowledgeInsightAutoSkillPrompt(zhInstruction);
      expect(prompt, contains(zhInstruction));
      expect(prompt, contains('at least two'));
      expect(prompt, isNot(contains('Nostalgic')));
    });
  });
}
