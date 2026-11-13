import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/todo_item.dart';

void main() {
  test('round trips all fields needed by a robust Todo task', () {
    final item = TodoItem(
      id: 'task-stable-1',
      text: 'Revisar proposta',
      due: '2026-11-20 09:30',
      dueDate: '2026-11-20',
      dueTime: '09:30',
      timeZone: todoTimeZone,
      alertMinutes: 20,
      priority: TodoPriority.urgent,
      subtasks: [
        const TodoSubtask(
          id: 'subtask-1',
          text: 'Conferir valores',
          done: true,
        ),
      ],
      recurrence: TodoRecurrence.weekly([1, 3, 5]),
      seriesId: 'series-stable-1',
      done: true,
      createdAt: '2026-11-13T09:00:00.000',
      doneAt: '2026-11-13T10:00:00.000',
      source: const TodoSource(
        sessionId: 'synthetic-session',
        itemId: 'synthetic-item',
        excerpt: 'synthetic source excerpt',
        clock: '00:01:02',
      ),
      sourceStale: true,
      version: 4,
      deletedAt: '2026-11-13T11:00:00.000',
    );

    final restored = TodoItem.fromJson(item.toJson());

    expect(restored.id, 'task-stable-1');
    expect(restored.dueDate, '2026-11-20');
    expect(restored.dueTime, '09:30');
    expect(restored.timeZone, 'America/Sao_Paulo');
    expect(restored.alertMinutes, 20);
    expect(restored.priority, TodoPriority.urgent);
    expect(restored.subtasks.single.id, 'subtask-1');
    expect(restored.subtasks.single.done, isTrue);
    expect(restored.recurrence?.frequency, TodoRepeatFrequency.weekly);
    expect(restored.recurrence?.weekdays, [1, 3, 5]);
    expect(restored.seriesId, 'series-stable-1');
    expect(restored.source?.sessionId, 'synthetic-session');
    expect(restored.source?.itemId, 'synthetic-item');
    expect(restored.source?.clock, '00:01:02');
    expect(restored.sourceStale, isTrue);
    expect(restored.version, 4);
    expect(restored.isTombstoned, isTrue);
  });

  test('legacy task without a date gets safe Todo defaults', () {
    final item = TodoItem.fromJson({
      'id': 'legacy-id',
      'text': 'Tarefa legada',
      'due': '',
      'done': false,
      'created_at': '2026-11-01T09:00:00.000',
    });

    expect(item.id, 'legacy-id');
    expect(item.dueDate, isNull);
    expect(item.dueTime, isNull);
    expect(item.hasAlarmTime, isFalse);
    expect(item.timeZone, 'America/Sao_Paulo');
    expect(item.alertMinutes, 20);
    expect(item.priority, TodoPriority.normal);
    expect(item.version, 1);
    expect(item.isTombstoned, isFalse);
  });

  test('keeps monthly day 31 in the recurrence rule', () {
    expect(TodoRecurrence.monthly(31).dayOfMonth, 31);
    expect(() => TodoRecurrence.monthly(0), throwsArgumentError);
    expect(() => TodoRecurrence.monthly(32), throwsArgumentError);
  });
}
