import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/utils/logger.dart';

/// Pushes the home-screen Todo widget's snapshot to Android (F15-05, D8).
///
/// The snapshot carries only what the widget shows: id, title, due date and
/// time, status and time zone, for up to [maxItems] open tasks. Up to three
/// undated tasks can fill spare widget rows. The native side keeps the last
/// snapshot in its own app-private storage.
class TodoWidgetSnapshotService {
  TodoWidgetSnapshotService._() : _channel = _defaultChannel;

  @visibleForTesting
  TodoWidgetSnapshotService.forTesting({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static final TodoWidgetSnapshotService instance =
      TodoWidgetSnapshotService._();

  static const MethodChannel _defaultChannel =
      MethodChannel('com.memexlab.memex/todo_widget');

  static const int snapshotVersion = 1;

  /// Keeps a buffer of dated tasks for the widget's next day rollover.
  static const int maxItems = 10;

  static final _logger = getLogger('TodoWidgetSnapshot');

  final MethodChannel _channel;

  /// The snapshot for [items] as seen at [now]. Pure: no I/O, no channel.
  static Map<String, Object?> buildSnapshot(
    List<TodoItem> items, {
    required DateTime now,
  }) {
    final open = items.where((item) => !item.done && !item.isTombstoned);
    final dated = open.where((item) => item.dueDate != null).toList()
      ..sort(_byDue);
    final undated = open.where((item) => item.dueDate == null).take(3).toList();
    return {
      'version': snapshotVersion,
      'items': [
        for (final item in [
          ...dated.take(maxItems - undated.length),
          ...undated
        ])
          {
            'id': item.id,
            'title': item.text,
            'dueDate': item.dueDate,
            'dueTime': item.dueTime,
            'status': TodoScheduleCalculator.statusFor(
              dueDate: item.dueDate,
              dueTime: item.dueTime,
              now: now,
              timeZone: item.timeZone,
            ).name,
            'timeZone': item.timeZone,
          },
      ],
    };
  }

  static int _byDue(TodoItem a, TodoItem b) {
    final byDate = a.dueDate!.compareTo(b.dueDate!);
    if (byDate != 0) return byDate;
    // "HH:mm" sorts as text; a task without a time comes after the timed ones.
    final byTime = (a.dueTime ?? '99:99').compareTo(b.dueTime ?? '99:99');
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  /// Sends the snapshot of [items]. The JSON is built and the call is made
  /// before the first await, so pushes reach the native side in call order.
  /// Errors are logged and never thrown: a widget problem must not fail a save.
  Future<void> push(List<TodoItem> items, {DateTime? now}) async {
    final json = jsonEncode(buildSnapshot(items, now: now ?? DateTime.now()));
    try {
      await _channel.invokeMethod<void>('updateSnapshot', json);
    } on MissingPluginException {
      // No widget bridge here (iOS, tests).
      _logger.fine('Todo widget bridge not available; snapshot not sent.');
    } on PlatformException catch (error, stackTrace) {
      _logger.warning('Could not update the Todo widget', error, stackTrace);
    }
  }
}
