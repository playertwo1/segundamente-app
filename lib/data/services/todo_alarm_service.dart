import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Abstraction over platform local notifications so [TodoAlarmService] can be
/// tested deterministically without Android channels.
abstract interface class TodoAlarmBackend {
  bool get isSupported;

  Future<bool?> initialize({
    required TodoAlarmActionHandler onAction,
  });

  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails();

  Future<TodoAlarmStatus> readStatus({required String channelId});

  Future<bool?> areNotificationsEnabled();

  Future<bool?> openAppNotificationSettings();

  Future<bool?> requestNotificationsPermission();

  Future<bool?> requestExactAlarmsPermission();

  Future<List<PendingNotificationRequest>> pendingNotificationRequests();

  Future<List<ActiveNotification>> getActiveNotifications();

  Future<void> cancel({required int id});

  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    required String payload,
  });
}

class _PluginTodoAlarmBackend implements TodoAlarmBackend {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _androidNotifications =>
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<bool?> initialize({required TodoAlarmActionHandler onAction}) =>
      _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_todo_notification'),
        ),
        onDidReceiveNotificationResponse: onAction,
      );

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() =>
      _notifications.getNotificationAppLaunchDetails();

  @override
  Future<TodoAlarmStatus> readStatus({required String channelId}) async {
    final android = _androidNotifications;
    if (android == null) return TodoAlarmStatus.unavailable;
    final appNotificationsEnabled =
        await android.areNotificationsEnabled() ?? false;
    final channels = await android.getNotificationChannels();
    final todoChannel = channels?.where((channel) => channel.id == channelId);
    final todoChannelEnabled = todoChannel == null ||
        todoChannel.isEmpty ||
        todoChannel.first.importance != Importance.none;
    final exactAlarmsEnabled =
        await android.canScheduleExactNotifications() ?? false;
    return switch ((
      appNotificationsEnabled && todoChannelEnabled,
      exactAlarmsEnabled,
    )) {
      (true, true) => TodoAlarmStatus.ready,
      (false, false) => TodoAlarmStatus.bothPermissionsDenied,
      (false, true) => TodoAlarmStatus.notificationsDenied,
      (true, false) => TodoAlarmStatus.exactAlarmsDenied,
    };
  }

  @override
  Future<bool?> areNotificationsEnabled() async =>
      _androidNotifications?.areNotificationsEnabled();

  @override
  Future<bool?> openAppNotificationSettings() async =>
      _androidNotifications?.openAppNotificationSettings();

  @override
  Future<bool?> requestNotificationsPermission() async =>
      _androidNotifications?.requestNotificationsPermission();

  @override
  Future<bool?> requestExactAlarmsPermission() async =>
      _androidNotifications?.requestExactAlarmsPermission();

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() =>
      _notifications.pendingNotificationRequests();

  @override
  Future<List<ActiveNotification>> getActiveNotifications() =>
      _notifications.getActiveNotifications();

  @override
  Future<void> cancel({required int id}) => _notifications.cancel(id: id);

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    required String payload,
  }) =>
      _notifications.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: androidScheduleMode,
        payload: payload,
      );
}

class TodoAlarmService {
  TodoAlarmService._({
    TodoAlarmBackend? backend,
    DateTime Function()? now,
  })  : _backend = backend ?? _PluginTodoAlarmBackend(),
        _now = now ?? DateTime.now;

  @visibleForTesting
  TodoAlarmService.forTesting({
    required TodoAlarmBackend backend,
    DateTime Function()? now,
  }) : this._(backend: backend, now: now);

  static final TodoAlarmService instance = TodoAlarmService._();
  static const _payloadPrefix = 'todoAlarm:';
  static const _channelId = 'todo_reminders';
  static const _notificationIdBase = 1000000000;
  static const _notificationIdRange = 1000000000;

  final Logger _logger = getLogger('TodoAlarmService');
  final TodoAlarmBackend _backend;
  final DateTime Function() _now;
  final Map<String, tz.TZDateTime> _lastScheduledDates = {};

  bool _initialized = false;
  bool _requestedNotificationPermission = false;
  NotificationResponse? _launchResponse;
  TodoAlarmActionHandler? _actionHandler;

  /// Cancels both pending alarms and displayed notifications for the given task IDs.
  Future<void> cancelNotificationsForTaskIds(Iterable<String> taskIds) async {
    if (!_backend.isSupported) return;
    final ids = taskIds.toSet();
    if (ids.isEmpty) return;
    await initialize();
    final allIds = notificationIdsForTaskIds(ids);
    for (final taskId in ids) {
      final notifId = allIds[taskId];
      if (notifId != null) {
        _lastScheduledDates.remove(taskId);
        await _backend.cancel(id: notifId);
      }
    }
  }

  Future<NotificationResponse?> initialize({
    TodoAlarmActionHandler? onAction,
  }) async {
    if (onAction != null) _actionHandler = onAction;
    if (!_backend.isSupported) return null;
    if (!_initialized) {
      tzdata.initializeTimeZones();
      final initialized = await _backend.initialize(
        onAction: _dispatchAction,
      );
      if (initialized != true) {
        throw StateError('Todo notifications failed to initialize');
      }
      _initialized = true;
      final launch = await _backend.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _launchResponse = launch?.notificationResponse;
      }
    }
    final response = _launchResponse;
    _launchResponse = null;
    return response;
  }

  Future<TodoAlarmStatus> status() async {
    if (!_backend.isSupported) return TodoAlarmStatus.unsupported;
    try {
      await initialize();
      return await _backend.readStatus(channelId: _channelId);
    } catch (error, stackTrace) {
      _logger.warning(
          'Could not read Todo alarm permissions', error, stackTrace);
      return TodoAlarmStatus.unavailable;
    }
  }

  Future<TodoAlarmStatus> requestPermissions() async {
    if (!_backend.isSupported) return TodoAlarmStatus.unsupported;
    try {
      await initialize();
      var currentStatus = await _backend.readStatus(channelId: _channelId);
      if (currentStatus == TodoAlarmStatus.unavailable) {
        return currentStatus;
      }

      if (!_hasNotificationPermission(currentStatus)) {
        final appNotificationsEnabled =
            await _backend.areNotificationsEnabled() ?? false;
        if (appNotificationsEnabled || _requestedNotificationPermission) {
          await _backend.openAppNotificationSettings();
        } else {
          _requestedNotificationPermission = true;
          await _backend.requestNotificationsPermission();
        }
        currentStatus = await _backend.readStatus(channelId: _channelId);
        if (!_hasNotificationPermission(currentStatus)) return currentStatus;
      }

      if (!_hasExactAlarmPermission(currentStatus)) {
        await _backend.requestExactAlarmsPermission();
        currentStatus = await _backend.readStatus(channelId: _channelId);
      }
      return currentStatus;
    } catch (error, stackTrace) {
      _logger.warning(
          'Could not request Todo alarm permissions', error, stackTrace);
      return TodoAlarmStatus.unavailable;
    }
  }

  Future<TodoAlarmStatus> synchronize(List<TodoItem> items) async {
    if (!_backend.isSupported) return TodoAlarmStatus.unsupported;
    try {
      await initialize();
      final status = await _backend.readStatus(channelId: _channelId);
      final pending = await _backend.pendingNotificationRequests();
      final activeNotifications = await _readActiveChannelNotifications();
      final active = [
        for (final item in items)
          if (!item.done && !item.isTombstoned && item.hasAlarmTime) item,
      ];
      final now = _now();
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
      final allIds = notificationIdsForTaskIds(items.map((item) => item.id));
      final itemById = <int, TodoItem>{
        for (final item in items) allIds[item.id]!: item,
      };
      final cancelledIds = <int>{};
      Future<void> cancelOnce(int id) async {
        if (cancelledIds.add(id)) {
          await _backend.cancel(id: id);
        }
      }

      for (final request in pending) {
        final payload = request.payload;
        if (payload?.startsWith(_payloadPrefix) != true) continue;
        final taskId = payload!.substring(_payloadPrefix.length);
        if (status != TodoAlarmStatus.ready ||
            !scheduledDates.containsKey(taskId) ||
            request.id != allIds[taskId]) {
          await cancelOnce(request.id);
        }
      }

      // Cancel by deterministic id even when the notification already fired
      // and left pendingNotificationRequests().
      for (final item in items) {
        final hasFutureSchedule = scheduledDates.containsKey(item.id);
        final nextSchedule = scheduledDates[item.id];
        final prevSchedule = _lastScheduledDates[item.id];
        final isRescheduled = hasFutureSchedule &&
            prevSchedule != null &&
            prevSchedule != nextSchedule;
        final isActiveSnoozed = !item.done &&
            !item.isTombstoned &&
            item.snoozedUntil != null &&
            hasFutureSchedule;
        if (item.done ||
            item.isTombstoned ||
            !hasFutureSchedule ||
            isActiveSnoozed ||
            isRescheduled) {
          await cancelOnce(allIds[item.id]!);
        }
        if (item.done || item.isTombstoned || !hasFutureSchedule) {
          _lastScheduledDates.remove(item.id);
        }
      }

      for (final notification in activeNotifications) {
        final id = notification.id;
        if (id == null) continue;
        final item = itemById[id];
        final nextSchedule = item == null ? null : scheduledDates[item.id];
        final prevSchedule = item == null ? null : _lastScheduledDates[item.id];
        final isRescheduled = nextSchedule != null &&
            prevSchedule != null &&
            prevSchedule != nextSchedule;
        final shouldKeep = item != null &&
            !item.done &&
            !item.isTombstoned &&
            scheduledDates.containsKey(item.id) &&
            item.snoozedUntil == null &&
            !isRescheduled;
        if (!shouldKeep) {
          await cancelOnce(id);
        }
      }

      if (status != TodoAlarmStatus.ready) return status;

      for (final item in active) {
        final scheduledDate = scheduledDates[item.id];
        if (scheduledDate == null) continue;
        _lastScheduledDates[item.id] = scheduledDate;
        await _backend.zonedSchedule(
          id: allIds[item.id]!,
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

  Future<List<ActiveNotification>> _readActiveChannelNotifications() async {
    try {
      final active = await _backend.getActiveNotifications();
      return [
        for (final notification in active)
          if (notification.channelId == _channelId) notification,
      ];
    } catch (error, stackTrace) {
      _logger.fine(
        'Active Todo notifications unavailable',
        error,
        stackTrace,
      );
      return const [];
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

  bool _hasNotificationPermission(TodoAlarmStatus status) =>
      status == TodoAlarmStatus.ready ||
      status == TodoAlarmStatus.exactAlarmsDenied;

  bool _hasExactAlarmPermission(TodoAlarmStatus status) =>
      status == TodoAlarmStatus.ready ||
      status == TodoAlarmStatus.notificationsDenied;

  static Map<String, int> notificationIdsForTaskIds(Iterable<String> taskIds) {
    final ids = taskIds.toSet().toList()..sort();
    final used = <int>{};
    final result = <String, int>{};
    for (final id in ids) {
      var candidate = deterministicNotificationId(id);
      while (!used.add(candidate)) {
        candidate = candidate == _notificationIdBase + _notificationIdRange - 1
            ? _notificationIdBase
            : candidate + 1;
      }
      result[id] = candidate;
    }
    return result;
  }

  static int deterministicNotificationId(String taskId) {
    var hash = 0x811c9dc5;
    for (final unit in 'todo:$taskId'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return _notificationIdBase + hash % _notificationIdRange;
  }
}
