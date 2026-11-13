import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/todo_proposal.dart';

void main() {
  test('round trips an explicit date and time', () {
    final proposal = TodoProposal(
      id: 'proposal-1',
      title: 'Enviar relatório',
      dateState: TodoProposalDateState.explicit,
      dueDate: '2026-11-16',
      timeState: TodoProposalTimeState.explicit,
      dueTime: '14:00',
    );

    final decoded = TodoProposal.fromJson(proposal.toJson());

    expect(decoded.id, proposal.id);
    expect(decoded.title, proposal.title);
    expect(decoded.dueDate, '2026-11-16');
    expect(decoded.dueTime, '14:00');
  });

  test('keeps ambiguous relative language without inventing a date', () {
    final proposal = TodoProposal(
      id: 'proposal-2',
      title: 'Enviar relatório',
      dateState: TodoProposalDateState.ambiguous,
      datePhrase: 'sexta',
      timeState: TodoProposalTimeState.unspecified,
    );

    final decoded = TodoProposal.fromJson(proposal.toJson());

    expect(decoded.dateState, TodoProposalDateState.ambiguous);
    expect(decoded.dueDate, isNull);
    expect(decoded.datePhrase, 'sexta');
    expect(decoded.dueTime, isNull);
  });

  test('rejects invalid calendar dates and times', () {
    expect(
      () => TodoProposal(
        id: 'proposal-3',
        title: 'Tarefa',
        dateState: TodoProposalDateState.explicit,
        dueDate: '2026-02-31',
        timeState: TodoProposalTimeState.unspecified,
      ),
      throwsArgumentError,
    );
    expect(
      () => TodoProposal(
        id: 'proposal-4',
        title: 'Tarefa',
        dateState: TodoProposalDateState.explicit,
        dueDate: '2026-11-16',
        timeState: TodoProposalTimeState.explicit,
        dueTime: '25:00',
      ),
      throwsArgumentError,
    );
  });
}
