import 'package:memex/domain/models/session_report.dart';

const todoSchemaVersion = 1;

/// Where a Todo item came from; null for an item typed by hand.
class TodoSource {
  const TodoSource({
    required this.sessionId,
    required this.itemId,
    required this.excerpt,
    this.clock,
  });

  final String sessionId;
  final String itemId;
  final String excerpt;
  final String? clock;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'item_id': itemId,
        'excerpt': excerpt,
        'clock': clock,
      };

  static TodoSource fromJson(Map<String, dynamic> json) => TodoSource(
        sessionId: _text(json['session_id']),
        itemId: _text(json['item_id']),
        excerpt: _text(json['excerpt']),
        clock: json['clock']?.toString(),
      );
}

class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    required this.due,
    required this.done,
    required this.createdAt,
    this.doneAt,
    this.source,
  });

  final String id;
  final String text;

  /// Free text, as in the report; [reportDueUnknown] when none was given.
  final String due;
  final bool done;
  final String createdAt;
  final String? doneAt;
  final TodoSource? source;

  TodoItem copyWith({String? text, String? due, bool? done, String? doneAt}) {
    final nextDone = done ?? this.done;
    return TodoItem(
      id: id,
      text: text ?? this.text,
      due: due ?? this.due,
      done: nextDone,
      createdAt: createdAt,
      doneAt: nextDone ? (doneAt ?? this.doneAt) : null,
      source: source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'due': due,
        'done': done,
        'created_at': createdAt,
        'done_at': doneAt,
        if (source != null) 'source': source!.toJson(),
      };

  static TodoItem fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    final due = json['due']?.toString().trim() ?? '';
    return TodoItem(
      id: _text(json['id']),
      text: _text(json['text']),
      due: due.isEmpty ? reportDueUnknown : due,
      done: json['done'] == true,
      createdAt: _text(json['created_at']),
      doneAt: json['done_at']?.toString(),
      source: source is Map ? TodoSource.fromJson(source.cast()) : null,
    );
  }
}

String _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) throw const FormatException('todo field is empty');
  return text;
}

/// Open items first, then done ones; each group keeps creation order.
List<TodoItem> sortTodos(List<TodoItem> items) {
  final sorted = [...items];
  sorted.sort((a, b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    return a.createdAt.compareTo(b.createdAt);
  });
  return sorted;
}

// shortcut: plain accent-blind substring match over text, due and quote;
// no ranking. Add it to the semantic index only if the list gets long.
List<TodoItem> searchTodos(List<TodoItem> items, String query) {
  final needle = _fold(query);
  if (needle.isEmpty) return items;
  return [
    for (final item in items)
      if (_fold('${item.text} ${item.due} ${item.source?.excerpt ?? ''}')
          .contains(needle))
        item,
  ];
}

String _fold(String value) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final buffer = StringBuffer();
  for (final ch in value.toLowerCase().trim().split('')) {
    final at = from.indexOf(ch);
    buffer.write(at >= 0 ? to[at] : ch);
  }
  return buffer.toString();
}
