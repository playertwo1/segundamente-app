import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';

void main() {
  const userId = 'todo-user';
  late Directory tempDir;
  late TodoService todos;

  ReportItem reportItem({
    String id = 'item_1',
    ReportItemKind kind = ReportItemKind.task,
    ReportItemStatus status = ReportItemStatus.approved,
    String due = '2026-11-21',
  }) =>
      ReportItem(
        id: id,
        kind: kind,
        text: 'Enviar a proposta',
        status: status,
        assignee: 'Carlos',
        due: due,
        source: const ReportSource(
          segmentId: 'seg_0',
          excerpt: 'Carlos envia a proposta',
          clock: 'p.2',
        ),
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memex_todo_');
    await FileSystemService.init(tempDir.path);
    todos = TodoService();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> installLegacyFixture(String name, String fixtureName) async {
    final content =
        await File('test/fixtures/todo/$fixtureName.json').readAsString();
    final file = File(FileSystemService.instance.getLegacyTodoFilePath(name));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return content;
  }

  test('starts empty and keeps a hand-typed item across reloads', () async {
    expect(await todos.load(userId), isEmpty);
    await todos.add(userId: userId, text: '  Pagar o seguro  ');
    final loaded = await todos.load(userId);
    expect(loaded.single.text, 'Pagar o seguro');
    expect(loaded.single.due, reportDueUnknown);
    expect(loaded.single.done, isFalse);
    expect(loaded.single.source, isNull);
  });

  test('keeps concurrent additions from separate service instances', () async {
    await Future.wait([
      for (var index = 0; index < 8; index++)
        TodoService().add(userId: userId, text: 'Tarefa $index'),
    ]);

    expect(await todos.load(userId), hasLength(8));
  });

  test('refuses an empty text', () async {
    await expectLater(
      todos.add(userId: userId, text: '   '),
      throwsArgumentError,
    );
  });

  test('an approved task goes in with its source and only once', () async {
    final first = await todos.addFromReport(
      userId: userId,
      sessionId: 'pdf_1',
      item: reportItem(),
    );
    final again = await todos.addFromReport(
      userId: userId,
      sessionId: 'pdf_1',
      item: reportItem(),
    );
    expect(again.id, first.id);
    final loaded = await todos.load(userId);
    expect(loaded, hasLength(1));
    expect(loaded.single.source?.sessionId, 'pdf_1');
    expect(loaded.single.source?.clock, 'p.2');
    expect(loaded.single.source?.excerpt, 'Carlos envia a proposta');
    expect(loaded.single.due, '2026-11-21');
  });

  test('unconfirmed, discarded and non-task items never get in', () async {
    for (final item in [
      reportItem(status: ReportItemStatus.unconfirmed),
      reportItem(status: ReportItemStatus.discarded),
      reportItem(kind: ReportItemKind.decision),
    ]) {
      await expectLater(
        todos.addFromReport(userId: userId, sessionId: 'pdf_1', item: item),
        throwsStateError,
      );
    }
    expect(await todos.load(userId), isEmpty);
  });

  test('complete, reopen, edit and remove', () async {
    final item = await todos.add(userId: userId, text: 'Ligar para Rui');
    await todos.setDone(userId: userId, id: item.id, done: true);
    var loaded = (await todos.load(userId)).single;
    expect(loaded.done, isTrue);
    expect(loaded.doneAt, isNotNull);

    await todos.setDone(userId: userId, id: item.id, done: false);
    loaded = (await todos.load(userId)).single;
    expect(loaded.done, isFalse);
    expect(loaded.doneAt, isNull);

    await todos.edit(
        userId: userId, id: item.id, text: 'Ligar para o Rui', due: '');
    loaded = (await todos.load(userId)).single;
    expect(loaded.text, 'Ligar para o Rui');
    expect(loaded.due, reportDueUnknown);

    await todos.remove(userId: userId, id: item.id);
    expect(await todos.load(userId), isEmpty);
    final tombstone = (await todos.load(userId, includeDeleted: true)).single;
    expect(tombstone.id, item.id);
    expect(tombstone.isTombstoned, isTrue);
    expect(tombstone.deletedAt, isNotNull);
    expect(tombstone.version, greaterThan(item.version));
  });

  test('changing an item that does not exist fails loudly', () async {
    await expectLater(
      todos.setDone(userId: userId, id: 'todo_nope', done: true),
      throwsStateError,
    );
  });

  test('deleting a session removes open copies and keeps completed history',
      () async {
    final completed = await todos.addFromReport(
      userId: userId,
      sessionId: 'pdf_1',
      item: reportItem(),
    );
    await todos.setDone(userId: userId, id: completed.id, done: true);
    await todos.addFromReport(
      userId: userId,
      sessionId: 'pdf_1',
      item: reportItem(id: 'item_2'),
    );
    await todos.addFromReport(
        userId: userId, sessionId: 'pdf_2', item: reportItem());
    await todos.add(userId: userId, text: 'Item manual');

    await todos.deleteForSession(userId: userId, sessionId: 'pdf_1');

    final left = await todos.load(userId);
    expect(left, hasLength(3));
    expect(left.first.done, isTrue);
    expect(left.first.source, isNull);
    expect(left[1].source?.sessionId, 'pdf_2');
    expect(left.last.source, isNull);
  });

  for (final fixtureName in [
    'empty',
    'missing_due',
    'completed',
    'f9_linked',
  ]) {
    test('migrates $fixtureName legacy fixture once and keeps its backup',
        () async {
      final fixtureUserId = '$userId-$fixtureName';
      final legacyContent =
          await installLegacyFixture(fixtureUserId, fixtureName);
      final legacy =
          File(FileSystemService.instance.getLegacyTodoFilePath(fixtureUserId));
      final backup = File(
        FileSystemService.instance.getLegacyTodoBackupPath(fixtureUserId),
      );
      final v2 =
          File(FileSystemService.instance.getTodoV2FilePath(fixtureUserId));

      final migrated = await todos.load(fixtureUserId);
      final loadedAgain = await todos.load(fixtureUserId);

      expect(await legacy.readAsString(), legacyContent);
      expect(await backup.readAsString(), legacyContent);
      expect(await v2.exists(), isTrue);
      expect(
          loadedAgain.map((item) => item.id), migrated.map((item) => item.id));
      expect(loadedAgain, hasLength(migrated.length));
      expect(migrated.every((item) => item.timeZone == 'America/Sao_Paulo'),
          isTrue);
      expect(migrated.every((item) => item.priority == TodoPriority.normal),
          isTrue);
      switch (fixtureName) {
        case 'empty':
          expect(migrated, isEmpty);
        case 'missing_due':
          expect(migrated.single.id, 'legacy-undated');
          expect(migrated.single.dueDate, isNull);
          expect(migrated.single.dueTime, isNull);
          expect(migrated.single.hasAlarmTime, isFalse);
        case 'completed':
          expect(migrated.single.id, 'legacy-completed');
          expect(migrated.single.done, isTrue);
          expect(migrated.single.doneAt, '2026-11-02T09:00:00.000');
          expect(migrated.single.dueDate, '2026-11-20');
          expect(migrated.single.dueTime, '14:30');
        case 'f9_linked':
          expect(migrated.single.id, 'legacy-f9-task');
          expect(migrated.single.source?.sessionId, 'synthetic-session');
          expect(migrated.single.source?.itemId, 'synthetic-item');
          expect(migrated.single.source?.excerpt, 'synthetic source excerpt');
          expect(migrated.single.source?.clock, 'p.2');
      }
    });
  }

  test('corrupt legacy migration retains original and backup and reports error',
      () async {
    final legacyContent = await installLegacyFixture(userId, 'corrupt');
    final legacy =
        File(FileSystemService.instance.getLegacyTodoFilePath(userId));
    final backup =
        File(FileSystemService.instance.getLegacyTodoBackupPath(userId));
    final v2 = File(FileSystemService.instance.getTodoV2FilePath(userId));

    await expectLater(todos.load(userId), throwsFormatException);

    expect(await legacy.readAsString(), legacyContent);
    expect(await backup.readAsString(), legacyContent);
    expect(await v2.exists(), isFalse);
    await expectLater(
      todos.add(userId: userId, text: 'Nova tarefa'),
      throwsFormatException,
    );
  });

  test('report edits mark linked Todo copies as stale', () async {
    final item = await todos.addFromReport(
      userId: userId,
      sessionId: 'pdf_1',
      item: reportItem(),
    );

    await todos.markReportItemStale(
      userId: userId,
      sessionId: 'pdf_1',
      itemId: 'item_1',
    );

    final loaded = (await todos.load(userId)).single;
    expect(loaded.id, item.id);
    expect(loaded.sourceStale, isTrue);
  });

  test('search ignores accents and case; open items sort before done ones',
      () async {
    final a = await todos.add(
      userId: userId,
      text: 'Revisar orçamento',
      now: DateTime(2026, 11, 1),
    );
    await todos.add(
      userId: userId,
      text: 'Comprar café',
      now: DateTime(2026, 11, 2),
    );
    await todos.setDone(userId: userId, id: a.id, done: true);

    final all = await todos.load(userId);
    expect(sortTodos(all).map((t) => t.text),
        ['Comprar café', 'Revisar orçamento']);
    expect(searchTodos(all, 'ORCAMENTO').map((t) => t.text),
        ['Revisar orçamento']);
    expect(searchTodos(all, '  '), hasLength(2));
    expect(searchTodos(all, 'nada'), isEmpty);
  });
}
