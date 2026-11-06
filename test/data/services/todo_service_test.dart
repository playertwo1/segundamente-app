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
    ReportItemKind kind = ReportItemKind.task,
    ReportItemStatus status = ReportItemStatus.approved,
    String due = '2026-11-21',
  }) =>
      ReportItem(
        id: 'item_1',
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

  test('starts empty and keeps a hand-typed item across reloads', () async {
    expect(await todos.load(userId), isEmpty);
    await todos.add(userId: userId, text: '  Pagar o seguro  ');
    final loaded = await todos.load(userId);
    expect(loaded.single.text, 'Pagar o seguro');
    expect(loaded.single.due, reportDueUnknown);
    expect(loaded.single.done, isFalse);
    expect(loaded.single.source, isNull);
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
  });

  test('changing an item that does not exist fails loudly', () async {
    await expectLater(
      todos.setDone(userId: userId, id: 'todo_nope', done: true),
      throwsStateError,
    );
  });

  test('deleting a session removes only the items that came from it', () async {
    await todos.addFromReport(
        userId: userId, sessionId: 'pdf_1', item: reportItem());
    await todos.addFromReport(
        userId: userId, sessionId: 'pdf_2', item: reportItem());
    await todos.add(userId: userId, text: 'Item manual');

    await todos.deleteForSession(userId: userId, sessionId: 'pdf_1');

    final left = await todos.load(userId);
    expect(left.map((t) => t.source?.sessionId), ['pdf_2', null]);
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
