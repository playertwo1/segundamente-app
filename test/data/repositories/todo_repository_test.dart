import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/todo_repository.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/utils/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const userId = 'todo-repository-user';
  late Directory tempDir;
  late TodoRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('memex_todo_repository_');
    await FileSystemService.init(tempDir.path);
    repository = TodoRepository(service: TodoService());
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('persists the new task fields through the Result repository interface',
      () async {
    final result = await repository.add(
      userId: userId,
      text: 'Revisar proposta',
      dueDate: '2026-11-20',
      dueTime: '09:30',
      priority: TodoPriority.high,
      subtasks: const [TodoSubtask(id: 'sub-1', text: 'Conferir valores')],
      recurrence: TodoRecurrence.weekly([1, 3]),
    );

    expect(result.isOk, isTrue);
    final created = result.valueOrThrow;
    expect(created.id, isNotEmpty);
    expect(created.hasAlarmTime, isTrue);
    expect(created.timeZone, 'America/Sao_Paulo');
    expect(created.priority, TodoPriority.high);
    expect(created.subtasks.single.id, 'sub-1');
    expect(created.recurrence?.weekdays, [1, 3]);

    final reloaded = (await repository.load(userId)).valueOrThrow.single;
    expect(reloaded.id, created.id);
    expect(reloaded.dueDate, '2026-11-20');
    expect(reloaded.dueTime, '09:30');
    expect(reloaded.priority, TodoPriority.high);
    expect(reloaded.subtasks.single.text, 'Conferir valores');
    expect(reloaded.recurrence?.weekdays, [1, 3]);

    final editResult = await repository.edit(
      userId: userId,
      id: created.id,
      text: 'Revisar proposta revisada',
      due: '',
      dueDate: '2026-11-21',
      priority: TodoPriority.urgent,
      clearRecurrence: true,
    );
    expect(editResult.isOk, isTrue);

    final edited = (await repository.load(userId)).valueOrThrow.single;
    expect(edited.id, created.id);
    expect(edited.version, 2);
    expect(edited.text, 'Revisar proposta revisada');
    expect(edited.dueDate, '2026-11-21');
    expect(edited.dueTime, isNull);
    expect(edited.hasAlarmTime, isFalse);
    expect(edited.priority, TodoPriority.urgent);
    expect(edited.recurrence, isNull);
  });

  test('returns a Result error when legacy migration cannot parse the file',
      () async {
    final legacy =
        File(FileSystemService.instance.getLegacyTodoFilePath(userId));
    await legacy.parent.create(recursive: true);
    await legacy.writeAsString('{broken');

    final result = await repository.load(userId);

    expect(result.isError, isTrue);
    expect(
      await File(FileSystemService.instance.getLegacyTodoBackupPath(userId))
          .readAsString(),
      '{broken',
    );
  });

  test('restores a deleted Todo through the Result repository interface',
      () async {
    final added = await repository.add(userId: userId, text: 'Pagar aluguel');
    final item = added.valueOrThrow;
    expect((await repository.remove(userId: userId, id: item.id)).isOk, isTrue);

    final restored = await repository.restore(userId: userId, id: item.id);

    expect(restored.isOk, isTrue);
    expect((await repository.load(userId)).valueOrThrow.single.id, item.id);
  });

  test('persists shortcut preferences through Result repository methods',
      () async {
    final settings = TodoShortcutSettings(
      enabledDateShortcuts: const {TodoDateShortcut.today},
      timeShortcutsMinutes: const [510, 870, 1170],
      defaultAlertMinutes: 25,
    );

    expect((await repository.saveShortcutSettings(settings)).isOk, isTrue);
    final loaded = (await repository.loadShortcutSettings()).valueOrThrow;

    expect(loaded.enabledDateShortcuts, {TodoDateShortcut.today});
    expect(loaded.timeShortcutsMinutes, [510, 870, 1170]);
    expect(loaded.defaultAlertMinutes, 25);
  });
}
