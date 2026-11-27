import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';

void main() {
  const userId = 'observer-user';
  late Directory tempDir;
  late TodoService todos;
  final calls = <({String userId, List<TodoItem> changed})>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memex_todo_observer_');
    await FileSystemService.init(tempDir.path);
    todos = TodoService();
    calls.clear();
    TodoService.alarmSynchronizer = (_) async => TodoAlarmStatus.unavailable;
    TodoService.localMutationObserver = (id, changed) {
      calls.add((userId: id, changed: changed));
    };
  });

  tearDown(() async {
    TodoService.localMutationObserver = null;
    await TodoService.waitForAlarmSync();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('add reports the new item to the observer', () async {
    final item = await todos.add(userId: userId, text: 'Pagar aluguel');

    expect(calls, hasLength(1));
    expect(calls.single.userId, userId);
    expect(calls.single.changed.single.id, item.id);
    expect(calls.single.changed.single.text, 'Pagar aluguel');
  });

  test('setDone reports the completed item to the observer', () async {
    final item = await todos.add(userId: userId, text: 'Enviar relatório');
    calls.clear();

    await todos.setDone(userId: userId, id: item.id, done: true);

    expect(calls, hasLength(1));
    expect(calls.single.changed.single.id, item.id);
    expect(calls.single.changed.single.done, isTrue);
  });

  test('remove reports the tombstoned item to the observer', () async {
    final item = await todos.add(userId: userId, text: 'Ligar para o banco');
    calls.clear();

    await todos.remove(userId: userId, id: item.id);

    expect(calls, hasLength(1));
    expect(calls.single.changed.single.id, item.id);
    expect(calls.single.changed.single.isTombstoned, isTrue);
  });

  test('remote batches do not notify the observer', () async {
    final item = await todos.add(userId: userId, text: 'Tarefa remota');
    calls.clear();

    await todos.applyRemoteMutationBatch(userId, (current) {
      return [
        for (final todo in current)
          if (todo.id == item.id)
            todo.copyWith(text: 'Tarefa remota 2')
          else
            todo,
      ];
    });

    expect(calls, isEmpty);
  });

  test('a throwing observer does not break the Todo write', () async {
    TodoService.localMutationObserver = (_, __) => throw StateError('boom');

    final item = await todos.add(userId: userId, text: 'Continua salvando');

    final loaded = await todos.load(userId);
    expect(loaded.map((todo) => todo.id), contains(item.id));
  });
}
