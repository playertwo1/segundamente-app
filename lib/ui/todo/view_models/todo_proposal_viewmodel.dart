import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/utils/result.dart';

class TodoProposalViewModel extends ChangeNotifier {
  TodoProposalViewModel({required MemexRouter router}) : _router = router;

  final MemexRouter _router;
  TodoShortcutSettings? settings;
  final Map<String, TodoItem> _tasksById = {};
  bool _disposed = false;
  bool loading = false;
  String? errorMessage;

  TodoItem? taskFor(String proposalId) => _tasksById[proposalId];

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();

    final settingsResult = await _router.loadTodoShortcutSettings();
    if (_disposed) return;
    settingsResult.when(
      onOk: (value) => settings = value,
      onError: (error, _) => errorMessage = '$error',
    );
    final todosResult = await _router.loadTodos(includeDeleted: true);
    if (_disposed) return;
    todosResult.when(
      onOk: (items) {
        _tasksById
          ..clear()
          ..addEntries(items.map((item) => MapEntry(item.id, item)));
      },
      onError: (error, _) => errorMessage ??= '$error',
    );

    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<Result<TodoItem>> confirm({
    required TodoProposal proposal,
    required String text,
    required String due,
    required TodoPriority priority,
    required List<TodoSubtask> subtasks,
    required int alertMinutes,
    TodoRecurrence? recurrence,
  }) =>
      _router.addTodo(
        id: proposal.id,
        text: text,
        due: due,
        priority: priority,
        subtasks: subtasks,
        alertMinutes: alertMinutes,
        recurrence: recurrence,
      );
}
