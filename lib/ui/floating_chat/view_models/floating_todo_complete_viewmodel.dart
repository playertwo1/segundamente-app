import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/result.dart';

/// Completes one Todo task from the home-screen widget (F15-05). It goes
/// through the router, like the Todo screen, so the widget snapshot follows.
class FloatingTodoCompleteViewModel extends ChangeNotifier {
  FloatingTodoCompleteViewModel({
    required MemexRouter router,
    required this.todoId,
  }) : _router = router;

  static final _logger = getLogger('FloatingTodoComplete');

  final MemexRouter _router;
  final String todoId;

  /// True once the task is done, including when it was already done.
  bool completed = false;

  /// Runs once from the widget's circle. An unknown or empty id is logged and
  /// leaves the list as it is; it never throws.
  Future<bool> complete() async {
    if (todoId.isEmpty) return false;
    final result = await _router.setTodoDone(id: todoId, done: true);
    completed = result.when(
      onOk: (_) => true,
      onError: (error, stackTrace) {
        _logger.warning(
            'Could not complete Todo from the widget', error, stackTrace);
        return false;
      },
    );
    notifyListeners();
    return completed;
  }
}
