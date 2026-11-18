import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/card_task_state.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/card_task_extractor.dart';
import 'package:memex/utils/result.dart';
import 'package:uuid/uuid.dart';

enum CardTasksPhase { loading, selecting, added, hidden }

/// Turns the task candidates of one record into Todo tasks without date or
/// time, once the user confirms. Nothing is written before [addSelected].
class CardTasksViewModel extends ChangeNotifier {
  CardTasksViewModel({
    required MemexRouter router,
    required String cardId,
    required List<CardTaskCandidate> candidates,
  })  : _router = router,
        _cardId = cardId,
        candidates = List.unmodifiable(candidates),
        _selected = List.filled(candidates.length, true);

  final MemexRouter _router;
  final String _cardId;
  final List<CardTaskCandidate> candidates;
  final List<bool> _selected;

  CardTasksPhase _phase = CardTasksPhase.loading;
  List<String> _todoIds = const [];
  int _addedCount = 0;
  bool _busy = false;
  String? _errorMessage;
  bool _disposed = false;

  CardTasksPhase get phase => _phase;
  bool isSelected(int index) => _selected[index];
  int get selectedCount => _selected.where((on) => on).length;
  int get addedCount => _addedCount;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;

  /// Picks the phase from the saved state. A failed read hides the block, so
  /// a read error can never lead to the tasks being added twice.
  Future<void> load() async {
    if (candidates.isEmpty) {
      _show(CardTasksPhase.hidden);
      return;
    }
    final stateResult = await _router.loadCardTaskState(_cardId);
    if (_disposed) return;
    if (stateResult.isError) {
      _show(CardTasksPhase.hidden);
      return;
    }
    final state = stateResult.valueOrThrow;
    if (state == null) {
      _selected.fillRange(0, _selected.length, true);
      _show(CardTasksPhase.selecting);
      return;
    }
    if (state.status == CardTaskStatus.dismissed) {
      _show(CardTasksPhase.hidden);
      return;
    }
    _todoIds = state.todoIds;
    final live = switch (await _liveTodoIds(_todoIds)) {
      Ok(:final value) => value,
      Error() => <String>{},
    };
    if (_disposed) return;
    _addedCount = live.length;
    _show(live.isEmpty ? CardTasksPhase.hidden : CardTasksPhase.added);
  }

  void toggle(int index) {
    if (_phase != CardTasksPhase.selecting || _busy) return;
    _selected[index] = !_selected[index];
    _notify();
  }

  /// Creates the selected candidates as Todo tasks with no date. Tasks that
  /// were created stay saved even when a later one fails.
  Future<bool> addSelected() async {
    if (_busy || _phase != CardTasksPhase.selecting || selectedCount == 0) {
      return false;
    }
    _busy = true;
    _errorMessage = null;
    _notify();

    final created = <String>[];
    String? failure;
    for (var i = 0; i < candidates.length && failure == null; i++) {
      if (!_selected[i]) continue;
      final candidate = candidates[i];
      final result = await _router.addTodo(
        text: candidate.text,
        due: '',
        subtasks: [
          for (final subtask in candidate.subtasks)
            TodoSubtask(
              id: const Uuid().v4(),
              text: subtask.text,
              done: subtask.done,
            ),
        ],
      );
      switch (result) {
        case Ok(:final value):
          created.add(value.id);
        case Error(:final error):
          failure = '$error';
      }
    }

    if (created.isNotEmpty) {
      _todoIds = created;
      _addedCount = created.length;
      _show(CardTasksPhase.added);
      final saveError = await _save(
        CardTaskState(status: CardTaskStatus.added, todoIds: created),
      );
      failure ??= saveError;
    }

    _busy = false;
    _errorMessage = failure;
    _notify();
    return failure == null;
  }

  /// Removes the tasks this block created and returns to the list. Tasks the
  /// user already deleted are skipped. After a failed removal the rest stay
  /// saved, so a retry still knows about them.
  Future<bool> undo() async {
    if (_busy || _phase != CardTasksPhase.added) return false;
    _busy = true;
    _errorMessage = null;
    _notify();

    String? failure;
    var remaining = <String>[];
    final live = await _liveTodoIds(_todoIds);
    if (live case Error(:final error)) {
      failure = '$error';
      remaining = _todoIds;
    } else if (live case Ok(:final value)) {
      final toRemove = [
        for (final id in _todoIds)
          if (value.contains(id)) id,
      ];
      for (var i = 0; i < toRemove.length; i++) {
        final removed = await _router.removeTodo(toRemove[i]);
        if (removed case Error(:final error)) {
          failure = '$error';
          remaining = toRemove.sublist(i);
          break;
        }
      }
    }

    final saveError = await _save(
      remaining.isEmpty
          ? null
          : CardTaskState(status: CardTaskStatus.added, todoIds: remaining),
    );
    failure ??= saveError;
    _todoIds = remaining;
    _addedCount = remaining.length;
    if (remaining.isEmpty) {
      _selected.fillRange(0, _selected.length, true);
      _phase = CardTasksPhase.selecting;
    }
    _busy = false;
    _errorMessage = failure;
    _notify();
    return failure == null;
  }

  /// Hides the block for this record from now on.
  Future<bool> dismiss() async {
    if (_busy) return false;
    _busy = true;
    _notify();
    final saveError = await _save(
      const CardTaskState(status: CardTaskStatus.dismissed),
    );
    _busy = false;
    _phase = CardTasksPhase.hidden;
    _errorMessage = saveError;
    _notify();
    return saveError == null;
  }

  /// Ids in [ids] that are live Todo tasks (not deleted).
  Future<Result<Set<String>>> _liveTodoIds(List<String> ids) async {
    final result = await _router.loadTodos();
    return result.when<Result<Set<String>>>(
      onOk: (items) => Ok<Set<String>>({
        for (final item in items)
          if (!item.isTombstoned && ids.contains(item.id)) item.id,
      }),
      onError: (error, _) => Error<Set<String>>(error),
    );
  }

  /// Writes the record's state. Returns the error text, or null when saved.
  Future<String?> _save(CardTaskState? state) async {
    final result = await _router.saveCardTaskState(_cardId, state);
    return result.when<String?>(
      onOk: (_) => null,
      onError: (error, _) => '$error',
    );
  }

  void _show(CardTasksPhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
