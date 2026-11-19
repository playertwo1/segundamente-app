import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/todo_widget_snapshot_service.dart';
import 'package:memex/domain/models/todo_item.dart';

import '../../helpers/floating_todo_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 14 Nov 2026, 10:00 in America/Sao_Paulo (UTC-3, no DST).
  final now = DateTime.utc(2026, 11, 14, 13, 0);

  List<Map<String, Object?>> itemsOf(List<TodoItem> items, DateTime at) =>
      (TodoWidgetSnapshotService.buildSnapshot(items, now: at)['items'] as List)
          .cast<Map<String, Object?>>();

  group('snapshot content', () {
    test('carries only id, title, dates, status and time zone', () {
      final snapshot = itemsOf([
        todoTask('a', 'Enviar proposta', date: '2026-11-14', time: '15:00'),
      ], now)
          .single;

      expect(snapshot.keys.toSet(),
          {'id', 'title', 'dueDate', 'dueTime', 'status', 'timeZone'});
      expect(snapshot, {
        'id': 'a',
        'title': 'Enviar proposta',
        'dueDate': '2026-11-14',
        'dueTime': '15:00',
        'status': 'today',
        'timeZone': 'America/Sao_Paulo',
      });
    });

    test('includes open tasks from records without a due date', () {
      final done = todoTask('done', 'Feito', date: '2026-11-14')
          .copyWith(done: true, doneAt: '2026-11-14T10:00:00.000Z');
      final deleted = todoTask('gone', 'Apagada', date: '2026-11-14')
          .copyWith(deletedAt: '2026-11-14T10:00:00.000Z');
      final undated = todoTask('undated', 'Sem data');
      final open = todoTask('open', 'Aberta', date: '2026-11-14');

      expect(
        itemsOf([done, deleted, undated, open], now).map((i) => i['id']),
        ['open', 'undated'],
      );
    });

    test('orders by date, then time, with untimed tasks after the timed ones',
        () {
      final snapshot = itemsOf([
        todoTask('late', 'Tarde', date: '2026-11-14', time: '18:00'),
        todoTask('untimed', 'Sem hora', date: '2026-11-14'),
        todoTask('next', 'Amanhã', date: '2026-11-15', time: '08:00'),
        todoTask('early', 'Cedo', date: '2026-11-14', time: '09:00'),
        todoTask('old', 'Atrasada', date: '2026-11-10'),
      ], now);

      expect(snapshot.map((i) => i['id']),
          ['old', 'early', 'late', 'untimed', 'next']);
    });

    test('keeps only the earliest ten open dated tasks', () {
      final tasks = [
        for (var day = 1; day <= 12; day++)
          todoTask('t$day', 'Dia $day',
              date: '2026-11-${day.toString().padLeft(2, '0')}'),
      ];

      final ids = itemsOf(tasks.reversed.toList(), now).map((i) => i['id']);

      expect(ids, [for (var day = 1; day <= 10; day++) 't$day']);
    });
  });

  group('status and midnight', () {
    test('a task due today is overdue from the next local day', () {
      final task = todoTask('a', 'Hoje', date: '2026-11-14');

      // 23:59 in São Paulo on the 14th, then 00:01 on the 15th.
      expect(
          itemsOf([task], DateTime.utc(2026, 11, 15, 2, 59)).single['status'],
          'today');
      expect(itemsOf([task], DateTime.utc(2026, 11, 15, 3, 1)).single['status'],
          'overdue');
    });

    test('a timed task turns overdue when its time passes', () {
      final task = todoTask('a', 'Reunião', date: '2026-11-14', time: '09:30');

      expect(
          itemsOf([task], DateTime.utc(2026, 11, 14, 12, 29)).single['status'],
          'today');
      expect(
          itemsOf([task], DateTime.utc(2026, 11, 14, 12, 31)).single['status'],
          'overdue');
    });
  });

  group('push', () {
    const channel = MethodChannel('test/todo_widget_snapshot');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sends the JSON snapshot as updateSnapshot', () async {
      final service = TodoWidgetSnapshotService.forTesting(channel: channel);
      await service.push(
        [todoTask('a', 'Pagar', date: '2026-11-14', time: '10:00')],
        now: now,
      );

      expect(calls.single.method, 'updateSnapshot');
      expect(calls.single.arguments as String, contains('"title":"Pagar"'));
    });

    test('a missing bridge or a platform error never throws', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw MissingPluginException());
      await TodoWidgetSnapshotService.forTesting(channel: channel)
          .push(const [], now: now);

      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'boom'));
      await TodoWidgetSnapshotService.forTesting(channel: channel)
          .push(const [], now: now);
    });
  });
}
