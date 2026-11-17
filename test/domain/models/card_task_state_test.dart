import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_task_state.dart';

void main() {
  test('round-trips added and dismissed states', () {
    const added = CardTaskState(
      status: CardTaskStatus.added,
      todoIds: ['t1', 't2'],
    );
    const dismissed = CardTaskState(status: CardTaskStatus.dismissed);

    final addedBack = CardTaskState.fromJson(added.toJson())!;
    final dismissedBack = CardTaskState.fromJson(dismissed.toJson())!;

    expect(addedBack.status, CardTaskStatus.added);
    expect(addedBack.todoIds, ['t1', 't2']);
    expect(dismissedBack.status, CardTaskStatus.dismissed);
    expect(dismissedBack.todoIds, isEmpty);
  });

  test('returns null for input that is not a map', () {
    expect(CardTaskState.fromJson(null), isNull);
    expect(CardTaskState.fromJson('added'), isNull);
    expect(CardTaskState.fromJson(42), isNull);
    expect(CardTaskState.fromJson(['added']), isNull);
  });

  test('returns null for an unknown status', () {
    expect(CardTaskState.fromJson({'status': 'deleted'}), isNull);
    expect(CardTaskState.fromJson({'todo_ids': <String>[]}), isNull);
  });

  test('tolerates bad todo ids', () {
    final state = CardTaskState.fromJson({
      'status': 'added',
      'todo_ids': ['ok', '', 7, null, 'also-ok'],
    })!;

    expect(state.todoIds, ['ok', 'also-ok']);
  });

  test('treats a missing or non-list todo_ids as empty', () {
    final missing = CardTaskState.fromJson({'status': 'added'})!;
    final wrongType = CardTaskState.fromJson({
      'status': 'added',
      'todo_ids': 'nope',
    })!;

    expect(missing.todoIds, isEmpty);
    expect(wrongType.todoIds, isEmpty);
  });
}
