import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/floating_chat/view_models/floating_todo_complete_viewmodel.dart';

import '../../../helpers/floating_todo_fakes.dart';

void main() {
  test('completes the task once, through the router', () async {
    final router = FakeTodoRouter([todoTask('a', 'Pagar', date: '2026-11-14')]);
    final viewModel =
        FloatingTodoCompleteViewModel(router: router, todoId: 'a');

    expect(await viewModel.complete(), isTrue);

    expect(router.completedIds, ['a']);
    expect(router.items.single.done, isTrue);
    expect(viewModel.completed, isTrue);
  });

  test('a task that is already done stays done and counts as completed',
      () async {
    final router = FakeTodoRouter([
      todoTask('a', 'Pagar', date: '2026-11-14')
          .copyWith(done: true, doneAt: '2026-11-14T10:00:00.000Z'),
    ]);
    final viewModel =
        FloatingTodoCompleteViewModel(router: router, todoId: 'a');

    expect(await viewModel.complete(), isTrue);

    expect(router.items.single.done, isTrue);
  });

  test('an unknown id is logged and reports no completion, without throwing',
      () async {
    final router = FakeTodoRouter();
    final viewModel =
        FloatingTodoCompleteViewModel(router: router, todoId: 'sumiu');

    expect(await viewModel.complete(), isFalse);

    expect(router.completedIds, ['sumiu']);
    expect(viewModel.completed, isFalse);
  });

  test('a failing router reports no completion and does not throw', () async {
    final router = FakeTodoRouter([todoTask('a', 'Pagar')])
      ..failCompletion = true;
    final viewModel =
        FloatingTodoCompleteViewModel(router: router, todoId: 'a');

    expect(await viewModel.complete(), isFalse);
  });

  test('an empty id never reaches the router', () async {
    final router = FakeTodoRouter();
    final viewModel = FloatingTodoCompleteViewModel(router: router, todoId: '');

    expect(await viewModel.complete(), isFalse);

    expect(router.completedIds, isEmpty);
  });
}
