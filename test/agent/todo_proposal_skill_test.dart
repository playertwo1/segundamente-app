import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/propose_todo/todo_proposal_skill.dart';
import 'package:memex/data/model/chat_artifact.dart';

void main() {
  test('creates only an artifact and retains an ambiguous weekday', () async {
    final tool = TodoProposalSkill().tools!.single;
    final result = await Function.apply(tool.executable!, [
      'Enviar relatório',
      'ambiguous',
      'unspecified',
      null,
      'sexta',
      null,
      null,
    ]) as AgentToolResult;

    final rawArtifact = result.metadata!['artifact'] as Map;
    final artifact = ChatArtifact.fromJson(
      Map<String, dynamic>.from(rawArtifact),
    );

    expect(artifact?.kind, ChatArtifact.kindTodoProposal);
    expect(artifact?.todoProposal?.datePhrase, 'sexta');
    expect(artifact?.todoProposal?.dueDate, isNull);
  });
}
