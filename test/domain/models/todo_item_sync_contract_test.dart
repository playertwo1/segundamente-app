import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';

// Keeps the synthetic examples of the sync contract (section 8) in step with
// TodoItem. If the model gains or loses a field, this test fails until the
// contract follows.
const _contractPath = 'docs/lumen/CONTRATO-SYNC.md';

void main() {
  final examples = _loadSyntheticExamples();

  group('sync contract synthetic examples', () {
    test('there are exactly three JSON examples in section 8', () {
      expect(examples, hasLength(3));
    });

    test('each example has exactly the envelope keys and valid values', () {
      for (final example in examples) {
        expect(example.keys.toSet(), _envelopeKeys);
        expect(example.containsKey('op'), isFalse);
        expect(example['contract_version'], 1);
        expect(example['mutation_id'], matches(_mutationIdPattern));
        expect(example['device_id'], isA<String>());
        expect(example['origin_role'], anyOf('pc', 'phone'));
        expect(example['entity_type'], 'task');

        final payload = _payloadOf(example);
        expect(example['entity_id'], payload['id']);

        final baseVersion = example['base_version'] as int;
        final newVersion = example['new_version'] as int;
        expect(baseVersion, greaterThanOrEqualTo(0));
        expect(newVersion, baseVersion + 1);
        expect(newVersion, payload['version']);

        final updatedAt = example['updated_at'] as String;
        expect(DateTime.parse(updatedAt), isA<DateTime>());
        expect(updatedAt, endsWith('Z'));
      }
    });

    test('TodoItem.fromJson keeps the fields the contract transmits', () {
      for (final example in examples) {
        final payload = _payloadOf(example);
        final item = TodoItem.fromJson(payload);

        expect(item.id, payload['id']);
        expect(item.text, payload['text']);
        expect(item.dueDate, payload['due_date']);
        expect(item.dueTime, payload['due_time']);
        expect(item.timeZone, payload['time_zone']);
        expect(item.alertMinutes, payload['alert_minutes']);
        expect(item.priority.name, payload['priority']);

        final rawSubtasks =
            (payload['subtasks'] as List).cast<Map<String, dynamic>>();
        expect(item.subtasks.map((s) => s.id), rawSubtasks.map((s) => s['id']));
        expect(
          item.subtasks.map((s) => s.text),
          rawSubtasks.map((s) => s['text']),
        );
        expect(
          item.subtasks.map((s) => s.done),
          rawSubtasks.map((s) => s['done']),
        );

        final rawRecurrence = payload['recurrence'] as Map<String, dynamic>?;
        if (rawRecurrence == null) {
          expect(item.recurrence, isNull);
        } else {
          expect(item.recurrence!.frequency.name, rawRecurrence['frequency']);
          expect(item.recurrence!.weekdays, rawRecurrence['weekdays'] ?? []);
          expect(item.recurrence!.dayOfMonth, rawRecurrence['day_of_month']);
        }

        expect(item.seriesId, payload['series_id']);
        expect(item.done, payload['done']);
        expect(item.doneAt, payload['done_at']);
        expect(item.snoozedUntil, payload['snoozed_until']);
        expect(item.version, payload['version']);
        expect(item.deletedAt, payload['deleted_at']);
      }
    });

    test('toJson and the contract have the same task fields', () {
      for (final example in examples) {
        final payload = _payloadOf(example);
        expect(
          payload.keys.toSet().difference(_taskFields),
          isEmpty,
          reason: 'payload has fields the contract does not define',
        );

        final json = TodoItem.fromJson(payload).toJson();
        expect(
          json.keys.toSet().difference(_taskFields),
          isEmpty,
          reason: 'toJson emits fields the contract does not define',
        );
        expect(
          _taskFields.difference(json.keys.toSet()).difference(_optionalFields),
          isEmpty,
          reason: 'toJson lacks a required contract field',
        );
      }
    });

    test('example 3 without source and source_stale reads as no source', () {
      final payload = _payloadOf(examples[2]);
      expect(payload.containsKey('source'), isFalse);
      expect(payload.containsKey('source_stale'), isFalse);

      final item = TodoItem.fromJson(payload);
      expect(item.source, isNull);
      expect(item.sourceStale, isFalse);
    });

    test(
        'current Dart behavior: an empty due is read as reportDueUnknown; '
        'writing "" back on transmission is for F12-04 (contract 7.1)', () {
      expect(_payloadOf(examples[2])['due'], '');

      final item = TodoItem.fromJson(_payloadOf(examples[2]));
      expect(item.due, reportDueUnknown);
      expect(item.dueDate, isNull);
      expect(item.dueTime, isNull);
    });

    test('example 2 continues example 1 for the same task', () {
      final first = examples[0];
      final second = examples[1];

      expect(second['entity_id'], first['entity_id']);
      expect(second['base_version'], first['new_version']);

      final payload = _payloadOf(second);
      expect(payload['done'], isTrue);
      expect(payload['done_at'], isNotNull);
    });
  });
}

const _envelopeKeys = {
  'contract_version',
  'mutation_id',
  'device_id',
  'origin_role',
  'entity_type',
  'entity_id',
  'base_version',
  'new_version',
  'updated_at',
  'payload',
};

const _taskFields = {
  'id',
  'text',
  'due',
  'due_date',
  'due_time',
  'time_zone',
  'alert_minutes',
  'priority',
  'subtasks',
  'recurrence',
  'series_id',
  'done',
  'created_at',
  'done_at',
  'snoozed_until',
  'source',
  'source_stale',
  'version',
  'deleted_at',
};

const _optionalFields = {'source', 'source_stale'};

final _mutationIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,48}$');

Map<String, dynamic> _payloadOf(Map<String, dynamic> example) =>
    example['payload'] as Map<String, dynamic>;

List<Map<String, dynamic>> _loadSyntheticExamples() {
  final text = File(_contractPath).readAsStringSync().replaceAll('\r\n', '\n');
  final start = text.indexOf('## 8. Exemplos sintéticos (v1)');
  final end = text.indexOf('\n## 9.', start);
  if (start < 0 || end < start) {
    throw StateError('section 8 of $_contractPath not found');
  }

  final section = text.substring(start, end);
  final blocks = RegExp(r'```json\n([\s\S]*?)```')
      .allMatches(section)
      .map((match) => match.group(1)!)
      .toList();
  return [
    for (final block in blocks) jsonDecode(block) as Map<String, dynamic>,
  ];
}
