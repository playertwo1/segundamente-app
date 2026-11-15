import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/todo_alarm_service.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

class _RecordedSchedule {
  const _RecordedSchedule({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.payload,
    required this.scheduleMode,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledDate;
  final String payload;
  final AndroidScheduleMode scheduleMode;
}

class _FakeTodoAlarmBackend implements TodoAlarmBackend {
  bool supported = true;
  TodoAlarmStatus alarmStatus = TodoAlarmStatus.ready;
  Object? getActiveError;

  final List<String> operations = [];
  final List<int> cancelledIds = [];
  final List<_RecordedSchedule> scheduledCalls = [];
  final Map<int, PendingNotificationRequest> pending = {};
  final Map<int, ActiveNotification> active = {};

  @override
  bool get isSupported => supported;

  @override
  Future<bool?> initialize({required TodoAlarmActionHandler onAction}) async =>
      true;

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async =>
          const NotificationAppLaunchDetails(false);

  @override
  Future<TodoAlarmStatus> readStatus({required String channelId}) async =>
      alarmStatus;

  @override
  Future<bool?> areNotificationsEnabled() async => true;

  @override
  Future<bool?> openAppNotificationSettings() async => true;

  @override
  Future<bool?> requestNotificationsPermission() async => true;

  @override
  Future<bool?> requestExactAlarmsPermission() async => true;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      pending.values.toList(growable: false);

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async {
    if (getActiveError != null) {
      throw getActiveError!;
    }
    return active.values.toList(growable: false);
  }

  @override
  Future<void> cancel({required int id}) async {
    operations.add('cancel:$id');
    cancelledIds.add(id);
    pending.remove(id);
    active.remove(id);
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    required String payload,
  }) async {
    final utcIso = scheduledDate.toUtc().toIso8601String();
    operations.add('schedule:$id@$utcIso');
    scheduledCalls.add(
      _RecordedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        payload: payload,
        scheduleMode: androidScheduleMode,
      ),
    );
    pending[id] = PendingNotificationRequest(id, title, body, payload);
  }

  /// Simulates an alarm that already fired on Android: leaves pending queue
  /// and stays visible in the notification tray on the `todo_reminders` channel.
  void simulateFiredNotification(int id, {bool keepInTray = true}) {
    final old = pending.remove(id);
    if (keepInTray) {
      active[id] = ActiveNotification(
        id: id,
        channelId: 'todo_reminders',
        title: old?.title ?? 'Lembrete de tarefa',
        body: old?.body ?? 'Tarefa',
      );
    }
  }
}

TodoItem _makeTask({
  required String id,
  String text = 'Revisar proposta',
  String dueDate = '2026-11-16',
  String dueTime = '09:00',
  int alertMinutes = 20,
  bool done = false,
  String? doneAt,
  String? deletedAt,
  String? snoozedUntil,
}) =>
    TodoItem(
      id: id,
      text: text,
      due: '$dueDate $dueTime',
      dueDate: dueDate,
      dueTime: dueTime,
      timeZone: todoTimeZone,
      alertMinutes: alertMinutes,
      done: done,
      createdAt: '2026-11-15T08:00:00Z',
      doneAt: doneAt,
      deletedAt: deletedAt,
      snoozedUntil: snoozedUntil,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeTodoAlarmBackend backend;
  late DateTime fakeNow;
  late TodoAlarmService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();
    backend = _FakeTodoAlarmBackend();
    fakeNow = DateTime.utc(2026, 11, 15, 12, 0, 0);
    service = TodoAlarmService.forTesting(
      backend: backend,
      now: () => fakeNow,
    );
  });

  test('schedules exact alarm at due minus alertMinutes in task timezone',
      () async {
    final task = _makeTask(
      id: 'task-future-1',
      text: 'Reunião de alinhamento',
      dueDate: '2026-11-16',
      dueTime: '09:00',
      alertMinutes: 20,
    );

    final status = await service.synchronize([task]);

    expect(status, TodoAlarmStatus.ready);
    expect(backend.cancelledIds, isEmpty);
    expect(backend.scheduledCalls, hasLength(1));
    final call = backend.scheduledCalls.single;
    expect(call.payload, 'todoAlarm:task-future-1');
    expect(call.scheduleMode, AndroidScheduleMode.exactAllowWhileIdle);
    // 09:00 America/Sao_Paulo (UTC-3) - 20 min = 08:40 BRT = 11:40 UTC.
    expect(call.scheduledDate.toUtc(), DateTime.utc(2026, 11, 16, 11, 40));
    expect(call.scheduledDate.hour, 8);
    expect(call.scheduledDate.minute, 40);
    expect(backend.pending.keys, [call.id]);
  });

  test('idempotent resynchronization preserves schedule without cancel churn',
      () async {
    final task = _makeTask(id: 'task-idem-1');

    await service.synchronize([task]);
    final firstId = backend.scheduledCalls.single.id;
    final firstUtc = backend.scheduledCalls.single.scheduledDate.toUtc();
    backend.operations.clear();
    backend.cancelledIds.clear();
    backend.scheduledCalls.clear();

    final status = await service.synchronize([task]);

    expect(status, TodoAlarmStatus.ready);
    expect(backend.cancelledIds, isEmpty);
    expect(backend.scheduledCalls, hasLength(1));
    expect(backend.scheduledCalls.single.id, firstId);
    expect(backend.scheduledCalls.single.scheduledDate.toUtc(), firstUtc);
    expect(backend.pending.keys, [firstId]);
  });

  test(
      'cancels fired alarm for completed or deleted task even absent from pendingNotificationRequests',
      () async {
    final taskDone = _makeTask(id: 'task-done-fired');
    final taskDeleted = _makeTask(id: 'task-deleted-fired');
    await service.synchronize([taskDone, taskDeleted]);
    final doneId = backend.scheduledCalls
        .firstWhere((c) => c.payload == 'todoAlarm:task-done-fired')
        .id;
    final deletedId = backend.scheduledCalls
        .firstWhere((c) => c.payload == 'todoAlarm:task-deleted-fired')
        .id;

    // Both fired earlier: neither is in pendingNotificationRequests anymore.
    // Simulate one absent even from getActiveNotifications() and one in tray.
    backend.simulateFiredNotification(doneId, keepInTray: false);
    backend.simulateFiredNotification(deletedId, keepInTray: true);
    expect(backend.pending, isEmpty);

    backend.cancelledIds.clear();
    backend.scheduledCalls.clear();
    backend.operations.clear();

    final status = await service.synchronize([
      _makeTask(
        id: taskDone.id,
        done: true,
        doneAt: '2026-11-15T12:05:00Z',
      ),
      _makeTask(
        id: taskDeleted.id,
        deletedAt: '2026-11-15T12:06:00Z',
      ),
    ]);

    expect(status, TodoAlarmStatus.ready);
    expect(backend.scheduledCalls, isEmpty);
    expect(backend.cancelledIds, containsAll([doneId, deletedId]));
    expect(backend.cancelledIds, hasLength(2));
    expect(backend.active, isEmpty);
  });

  test(
      'cancels orphan active notifications only on todo_reminders channel and tolerates getActiveNotifications failure',
      () async {
    final activeTask = _makeTask(id: 'task-keep-active');
    await service.synchronize([activeTask]);
    final activeTaskId = backend.scheduledCalls.single.id;
    backend.simulateFiredNotification(activeTaskId, keepInTray: true);

    const orphanTodoId = 1099112233;
    const otherChannelId = 424242;
    backend.active[orphanTodoId] = const ActiveNotification(
      id: orphanTodoId,
      channelId: 'todo_reminders',
      title: 'Antiga',
      body: 'Órfã',
    );
    backend.active[otherChannelId] = const ActiveNotification(
      id: otherChannelId,
      channelId: 'agent_background',
      title: 'Outro canal',
      body: 'Manter',
    );
    backend.cancelledIds.clear();

    await service.synchronize([activeTask]);

    expect(backend.cancelledIds, [orphanTodoId]);
    expect(backend.active.containsKey(orphanTodoId), isFalse);
    // Valid active task reminder and unrelated channel stay untouched.
    expect(backend.active.containsKey(activeTaskId), isTrue);
    expect(backend.active.containsKey(otherChannelId), isTrue);

    // If getActiveNotifications throws on older OS, sync still cancels done items.
    backend.getActiveError = UnimplementedError('unsupported');
    backend.cancelledIds.clear();
    final status = await service.synchronize([
      _makeTask(
        id: activeTask.id,
        done: true,
        doneAt: '2026-11-15T12:10:00Z',
      ),
    ]);
    expect(status, TodoAlarmStatus.ready);
    expect(backend.cancelledIds, [activeTaskId]);
  });

  test('T05: snoozed task cancels prior notification before rescheduling snooze',
      () async {
    final task = _makeTask(id: 'task-snooze-1');
    await service.synchronize([task]);
    final id = backend.scheduledCalls.single.id;
    backend.simulateFiredNotification(id, keepInTray: true);

    backend.operations.clear();
    backend.cancelledIds.clear();
    backend.scheduledCalls.clear();

    const snoozeIso = '2026-11-15T12:10:00.000Z';
    final snoozed = _makeTask(
      id: task.id,
      snoozedUntil: snoozeIso,
    );

    final status = await service.synchronize([snoozed]);

    expect(status, TodoAlarmStatus.ready);
    expect(backend.cancelledIds, [id]);
    expect(backend.active, isEmpty);
    expect(backend.scheduledCalls, hasLength(1));
    expect(
      backend.scheduledCalls.single.scheduledDate.toUtc(),
      DateTime.utc(2026, 11, 15, 12, 10),
    );
    expect(
      backend.operations,
      ['cancel:$id', 'schedule:$id@2026-11-15T12:10:00.000Z'],
    );
  });

  test('unsupported platform returns unsupported without touching backend',
      () async {
    backend.supported = false;
    final status = await service.synchronize([_makeTask(id: 'task-unsupported')]);
    expect(status, TodoAlarmStatus.unsupported);
    expect(backend.scheduledCalls, isEmpty);
    expect(backend.cancelledIds, isEmpty);
  });

  test('denied exact alarms cancels pending requests and skips scheduling',
      () async {
    final task = _makeTask(id: 'task-denied-exact');
    await service.synchronize([task]);
    final id = backend.scheduledCalls.single.id;
    backend.scheduledCalls.clear();
    backend.cancelledIds.clear();
    backend.alarmStatus = TodoAlarmStatus.exactAlarmsDenied;

    final status = await service.synchronize([task]);

    expect(status, TodoAlarmStatus.exactAlarmsDenied);
    expect(backend.cancelledIds, [id]);
    expect(backend.scheduledCalls, isEmpty);
    expect(backend.pending, isEmpty);
  });

  test('cancels active task whose due time already passed even without pending request',
      () async {
    final futureTask = _makeTask(
      id: 'task-expired',
      dueDate: '2026-11-15',
      dueTime: '13:00',
    );
    await service.synchronize([futureTask]);
    final id = backend.scheduledCalls.single.id;
    backend.simulateFiredNotification(id, keepInTray: false);
    backend.cancelledIds.clear();
    backend.scheduledCalls.clear();

    // Advance clock past dueTime (13:00 BRT = 16:00 UTC).
    fakeNow = DateTime.utc(2026, 11, 15, 16, 5);
    final status = await service.synchronize([futureTask]);

    expect(status, TodoAlarmStatus.ready);
    expect(backend.cancelledIds, [id]);
    expect(backend.scheduledCalls, isEmpty);
  });
}
