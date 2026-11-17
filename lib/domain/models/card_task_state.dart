enum CardTaskStatus { added, dismissed }

/// What the user decided about the task list suggested by one record.
class CardTaskState {
  const CardTaskState({required this.status, this.todoIds = const []});

  final CardTaskStatus status;

  /// Todo ids created from the record; empty unless [status] is added.
  final List<String> todoIds;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'todo_ids': todoIds,
      };

  /// Returns null for anything that is not a known state. Bad ids are dropped.
  static CardTaskState? fromJson(Object? json) {
    if (json is! Map) return null;
    final status = CardTaskStatus.values.asNameMap()[json['status']];
    if (status == null) return null;
    final ids = json['todo_ids'];
    final todoIds = ids is List
        ? [
            for (final id in ids)
              if (id is String && id.isNotEmpty) id,
          ]
        : const <String>[];
    return CardTaskState(status: status, todoIds: todoIds);
  }
}
