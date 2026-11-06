import 'dart:convert';
import 'dart:io';

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:path/path.dart' as p;

/// The personal Todo list: one JSON file in the user's workspace. Only the
/// user's own approved report tasks and hand-typed items live here; the
/// agents' internal task queue is a different thing and never reaches it.
class TodoService {
  TodoService({FileSystemService? fileService})
      : _files = fileService ?? FileSystemService.instance;

  final FileSystemService _files;

  Future<List<TodoItem>> load(String userId) async {
    final file = _file(userId);
    if (!await file.exists()) return const [];
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map || raw['items'] is! List) {
      throw const FormatException('todo file is malformed');
    }
    return [
      for (final item in raw['items'] as List)
        TodoItem.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<TodoItem> add({
    required String userId,
    required String text,
    String? due,
    TodoSource? source,
    DateTime? now,
  }) async {
    final items = await load(userId);
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('todo text is empty');
    final moment = now ?? DateTime.now();
    final item = TodoItem(
      id: 'todo_${moment.microsecondsSinceEpoch}',
      text: clean,
      due: _due(due),
      done: false,
      createdAt: moment.toIso8601String(),
      source: source,
    );
    await _write(userId, [...items, item]);
    return item;
  }

  /// Copies an approved task into the list. Asking twice for the same report
  /// item returns the existing entry instead of making a second one.
  Future<TodoItem> addFromReport({
    required String userId,
    required String sessionId,
    required ReportItem item,
    DateTime? now,
  }) async {
    if (item.kind != ReportItemKind.task ||
        item.status != ReportItemStatus.approved) {
      throw StateError('only an approved task can go to the Todo list');
    }
    final existing = (await load(userId)).where((todo) =>
        todo.source?.sessionId == sessionId && todo.source?.itemId == item.id);
    if (existing.isNotEmpty) return existing.first;
    return add(
      userId: userId,
      text: item.text,
      due: item.due,
      now: now,
      source: TodoSource(
        sessionId: sessionId,
        itemId: item.id,
        excerpt: item.source.excerpt,
        clock: item.source.clock,
      ),
    );
  }

  Future<void> edit({
    required String userId,
    required String id,
    required String text,
    required String due,
  }) {
    if (text.trim().isEmpty) throw ArgumentError('todo text is empty');
    return _change(
      userId,
      id,
      (item) => item.copyWith(text: text.trim(), due: _due(due)),
    );
  }

  Future<void> setDone({
    required String userId,
    required String id,
    required bool done,
    DateTime? now,
  }) {
    return _change(
      userId,
      id,
      (item) => item.copyWith(
        done: done,
        doneAt: done ? (now ?? DateTime.now()).toIso8601String() : null,
      ),
    );
  }

  Future<void> remove({required String userId, required String id}) async {
    final items = await load(userId);
    await _write(userId, [
      for (final item in items)
        if (item.id != id) item,
    ]);
  }

  /// Deleting a session also removes the Todo items that came from its report.
  Future<void> deleteForSession({
    required String userId,
    required String sessionId,
  }) async {
    final items = await load(userId);
    final kept = [
      for (final item in items)
        if (item.source?.sessionId != sessionId) item,
    ];
    if (kept.length != items.length) await _write(userId, kept);
  }

  Future<void> _change(
    String userId,
    String id,
    TodoItem Function(TodoItem) change,
  ) async {
    final items = await load(userId);
    if (!items.any((item) => item.id == id)) {
      throw StateError('todo item not found: $id');
    }
    await _write(userId, [
      for (final item in items) item.id == id ? change(item) : item,
    ]);
  }

  String _due(String? due) {
    final clean = due?.trim() ?? '';
    return clean.isEmpty ? reportDueUnknown : clean;
  }

  File _file(String userId) =>
      File(p.join(_files.getTodoPath(userId), 'todo.json'));

  Future<void> _write(String userId, List<TodoItem> items) async {
    final file = _file(userId);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': todoSchemaVersion,
        'items': [for (final item in items) item.toJson()],
      }),
      flush: true,
    );
  }
}
