import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef TodoAlarmActionHandler = FutureOr<void> Function(
  NotificationResponse response,
);

class TodoAlarmService {
  TodoAlarmService._();

  static final TodoAlarmService instance = TodoAlarmService._();
  static const _payloadPrefix = 'todoAlarm:';
  static const _channelId = 'todo_reminders';
  static const _notificationIdBase = 1000000000;
  static const _notificationIdRange = 1000000000;

  final Logger _logger = getLogger('TodoAlarmService');
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _requestedNotificationPermission = false;
  NotificationResponse? _launchResponse;
  TodoAlarmActionHandler? _actionHandler;

  Future<NotificationResponse?> initialize({
    TodoAlarmActionHandler? onAction,
  }) async {
    if (onAction != null) _actionHandler = onAction;
    if (!Platform.isAndroid) return null;
    if (!_initialized) {
      tzdata.initializeTimeZones();
      final initialized = await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_todo_notification'),
        ),
        onDidReceiveNotificationResponse: _dispatchAction,
      );
      if (initialized != true) {
        throw StateError('Todo notifications failed to initialize');
      }
      _initialized = true;
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _launchResponse = launch?.notificationResponse;
      }
    }
    final response = _launchResponse;
    _launchResponse = null;
    return response;
  }

  Future<TodoAlarmStatus> status() async {
    if (!Platform.isAndroid) return TodoAlarmStatus.unsupported;
    try {
      await initialize();
      return await _readStatus();
    } catch (error, stackTrace) {
      _logger.warning(
          'Could not read Todo alarm permissions', error, stackTrace);
      return TodoAlarmStatus.unavailable;
    }
  }

  Future<TodoAlarmStatus> requestPermissions() async {
    if (!Platform.isAndroid) return TodoAlarmStatus.unsupported;
    try {
      await initialize();
      final android = _androidNotifications;
      if (android == null) return TodoAlarmStatus.unavailable;

      var permissions = await _readPermissions(android);
      if (!permissions.$1) {
        final appNotificationsEnabled =
            await android.areNotificationsEnabled() ?? false;
        if (appNotificationsEnabled || _requestedNotificationPermission) {
          await android.openAppNotificationSettings();
        } else {
          _requestedNotificationPermission = true;
          await android.requestNotificationsPermission();
        }
        permissions = await _readPermissions(android);
        if (!permissions.$1) return _statusFor(permissions);
      }

      if (!permissions.$2) {
        await android.requestExactAlarmsPermission();
        permissions = await _readPermissions(android);
      }
      return _statusFor(permissions);
    } catch (error, stackTrace) {
      _logger.warning(
          'Could not request Todo alarm permissions', error, stackTrace);
      return TodoAlarmStatus.unavailable;
    }
  }

  Future<TodoAlarmStatus> synchronize(List<TodoItem> items) async {
    if (!Platform.isAndroid) return TodoAlarmStatus.unsupported;
    try {
      await initialize();
      final status = await _readStatus();
      final pending = await _notifications.pendingNotificationRequests();
      final active = [
        for (final item in items)
          if (!item.done && !item.isTombstoned && item.hasAlarmTime) item,
      ];
      final now = DateTime.now();
      final scheduledDates = <String, tz.TZDateTime>{};
      for (final item in active) {
        final date = TodoScheduleCalculator.alarmDateTimeFor(
          dueDate: item.dueDate,
          dueTime: item.dueTime,
          timeZone: item.timeZone,
          alertMinutes: item.alertMinutes,
          snoozedUntil: item.snoozedUntil,
          now: now,
        );
        if (date != null) scheduledDates[item.id] = date;
      }
      final ids = _notificationIds(active);
      for (final request in pending) {
        final payload = request.payload;
        if (payload?.startsWith(_payloadPrefix) != true) continue;
        final taskId = payload!.substring(_payloadPrefix.length);
        if (status != TodoAlarmStatus.ready ||
            !scheduledDates.containsKey(taskId) ||
            request.id != ids[taskId]) {
          await _notifications.cancel(id: request.id);
        }
      }
      if (status != TodoAlarmStatus.ready) return status;

      for (final item in active) {
        final scheduledDate = scheduledDates[item.id];
        if (scheduledDate == null) continue;
        await _notifications.zonedSchedule(
          id: ids[item.id]!,
          title: UserStorage.l10n.todoAlarmNotificationTitle,
          body: UserStorage.l10n.todoAlarmNotificationBody(
            item.text,
            item.dueTime!,
          ),
          scheduledDate: scheduledDate,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              UserStorage.l10n.todoAlarmChannelName,
              channelDescription: UserStorage.l10n.todoAlarmChannelDescription,
              icon: 'ic_todo_notification',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
              visibility: NotificationVisibility.private,
              actions: [
                AndroidNotificationAction(
                  'snooze',
                  UserStorage.l10n.todoAlarmSnoozeAction,
                  showsUserInterface: true,
                ),
                AndroidNotificationAction(
                  'complete',
                  UserStorage.l10n.todoAlarmCompleteAction,
                  showsUserInterface: true,
                ),
                AndroidNotificationAction(
                  'open',
                  UserStorage.l10n.todoAlarmOpenAction,
                  showsUserInterface: true,
                ),
              ],
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: '$_payloadPrefix${item.id}',
        );
      }
      return TodoAlarmStatus.ready;
    } catch (error, stackTrace) {
      _logger.warning('Could not synchronize Todo alarms', error, stackTrace);
      return TodoAlarmStatus.unavailable;
    }
  }

  void _dispatchAction(NotificationResponse response) {
    final handler = _actionHandler;
    if (handler != null) {
      unawaited(Future.sync(() => handler(response)).catchError(
        (Object error, StackTrace stackTrace) {
          _logger.warning(
              'Could not handle Todo alarm action', error, stackTrace);
        },
      ));
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidNotifications =>
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<TodoAlarmStatus> _readStatus() async {
    final android = _androidNotifications;
    if (android == null) return TodoAlarmStatus.unavailable;
    return _statusFor(await _readPermissions(android));
  }

  Future<(bool, bool)> _readPermissions(
    AndroidFlutterLocalNotificationsPlugin android,
  ) async {
    final appNotificationsEnabled =
        await android.areNotificationsEnabled() ?? false;
    final channels = await android.getNotificationChannels();
    final todoChannel = channels?.where((channel) => channel.id == _channelId);
    final todoChannelEnabled = todoChannel == null ||
        todoChannel.isEmpty ||
        todoChannel.first.importance != Importance.none;
    return (
      appNotificationsEnabled && todoChannelEnabled,
      await android.canScheduleExactNotifications() ?? false,
    );
  }

  TodoAlarmStatus _statusFor((bool, bool) permissions) => switch (permissions) {
        (true, true) => TodoAlarmStatus.ready,
        (false, false) => TodoAlarmStatus.bothPermissionsDenied,
        (false, true) => TodoAlarmStatus.notificationsDenied,
        (true, false) => TodoAlarmStatus.exactAlarmsDenied,
      };

  Map<String, int> _notificationIds(Iterable<TodoItem> items) {
    final ids = items.map((item) => item.id).toList()..sort();
    final used = <int>{};
    final result = <String, int>{};
    for (final id in ids) {
      var candidate = _notificationId('todo:$id');
      while (!used.add(candidate)) {
        candidate = candidate == _notificationIdBase + _notificationIdRange - 1
            ? _notificationIdBase
            : candidate + 1;
      }
      result[id] = candidate;
    }
    return result;
  }

  int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return _notificationIdBase + hash % _notificationIdRange;
  }
}
