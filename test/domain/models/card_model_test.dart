import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/todo_proposal.dart';

void main() {
  test('CardComment preserves a Todo proposal in its additive JSON field', () {
    final comment = CardComment(
      id: 'comment-1',
      content: 'Posso deixar isso como tarefa para você revisar.',
      isAi: true,
      timestamp: 1,
      todoProposal: TodoProposal(
        id: 'proposal-1',
        title: 'Enviar relatório',
        dateState: TodoProposalDateState.ambiguous,
        datePhrase: 'sexta',
        timeState: TodoProposalTimeState.unspecified,
      ),
    );

    final restored = CardComment.fromJson(comment.toJson());

    expect(restored.todoProposal?.id, 'proposal-1');
    expect(restored.todoProposal?.datePhrase, 'sexta');
    expect(restored.content, comment.content);
  });

  test('ignores a malformed proposal field without rejecting old comments', () {
    final comment = CardComment.fromJson({
      'id': 'legacy-comment',
      'content': 'Comentário existente',
      'is_ai': true,
      'timestamp': 1,
      'todo_proposal': {'id': 'incompleto'},
    });

    expect(comment.todoProposal, isNull);
    expect(comment.content, 'Comentário existente');
  });

  test('ignores proposal maps with non-string keys in stored comments', () {
    final cardComment = CardComment.fromJson({
      'id': 'legacy-comment',
      'content': 'Comentário existente',
      'is_ai': true,
      'timestamp': 1,
      'todo_proposal': {1: 'malformada'},
    });
    final detailComment = Comment.fromJson({
      'id': 'legacy-comment',
      'content': 'Comentário existente',
      'is_ai': true,
      'timestamp': 1,
      'todo_proposal': {1: 'malformada'},
    });

    expect(cardComment.todoProposal, isNull);
    expect(detailComment.todoProposal, isNull);
  });

  test('card detail comments retain an attached Todo proposal', () {
    final comment = Comment.fromJson({
      'id': 'comment-2',
      'content': 'Quer que eu coloque isso na lista?',
      'is_ai': true,
      'timestamp': 2,
      'todo_proposal': {
        'id': 'proposal-2',
        'title': 'Enviar relatório',
        'date_state': 'unspecified',
        'time_state': 'unspecified',
      },
    });

    expect(comment.todoProposal?.id, 'proposal-2');
    expect(comment.todoProposal?.dateState, TodoProposalDateState.unspecified);
  });
}
