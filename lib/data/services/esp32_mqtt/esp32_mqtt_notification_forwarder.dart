import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kEsp32NotifChannelName = 'com.memexlab.memex/esp32_notif';

/// Same key as the F16 BLE bridge, so the user's app choice survives the switch.
const String kEsp32NotifAllowedAppsPrefsKey = 'esp32_ble_allowed_apps';
const Set<String> kEsp32NotifDefaultApps = {
  'whatsapp',
  'call',
  'ligacao',
  'calendar',
};
const Set<String> kEsp32NotifSupportedApps = {
  'whatsapp',
  'call',
  'ligacao',
  'msg',
  'alert',
  'calendar',
};
const int kEsp32NotifMaxTitleBytes = 63;
const int kEsp32NotifMaxBodyBytes = 159;

const int _kMaxQueuedNotifications = 20;

/// Truncates [input] so its UTF-8 encoding fits within [maxBytes], never
/// cutting a character in half.
String esp32Utf8Truncate(String input, int maxBytes) {
  if (maxBytes <= 0 || input.isEmpty) return '';
  if (utf8.encode(input).length <= maxBytes) return input;
  final out = StringBuffer();
  var used = 0;
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final len = utf8.encode(ch).length;
    if (used + len > maxBytes) break;
    out.write(ch);
    used += len;
  }
  return out.toString();
}

/// Source of Android notifications selected by the native listener.
abstract class Esp32NotificationSource {
  Future<bool> hasNotificationAccess();
  Future<void> openNotificationAccessSettings();
  void setOnNotification(
    void Function(String app, String title, String body)? handler,
  );
}

class MethodChannelEsp32NotificationSource implements Esp32NotificationSource {
  MethodChannelEsp32NotificationSource({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(kEsp32NotifChannelName);

  final MethodChannel _channel;
  void Function(String app, String title, String body)? _handler;

  @override
  void setOnNotification(
    void Function(String app, String title, String body)? handler,
  ) {
    _handler = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onNotification') return null;
    final raw = call.arguments;
    if (raw is Map) {
      _handler?.call(
        raw['app']?.toString() ?? '',
        raw['title']?.toString() ?? '',
        raw['body']?.toString() ?? '',
      );
    }
    return null;
  }

  @override
  Future<bool> hasNotificationAccess() async =>
      await _channel.invokeMethod<bool>('hasNotificationAccess') ?? false;

  @override
  Future<void> openNotificationAccessSettings() =>
      _channel.invokeMethod<void>('openNotificationAccessSettings');
}

class _QueuedNotification {
  _QueuedNotification(this.payload, this.queuedAt);

  /// Plaintext JSON, sealed again on each publish.
  final String payload;
  final DateTime queuedAt;
}

/// Sends selected Android notifications to the ESP32 board over MQTT
/// (`sm/<sala>/notif`, F17). Notifications that cannot be sent now wait in a
/// short in-memory queue and go out when the link is back.
class Esp32MqttNotificationForwarder {
  Esp32MqttNotificationForwarder({
    required Esp32MqttService service,
    Esp32NotificationSource? source,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime Function()? now,
    this.queueTtl = const Duration(minutes: 5),
    this.backgroundIdle = const Duration(seconds: 60),
    Timer Function(Duration, void Function())? timerFactory,
  })  : _service = service,
        _source = source ?? MethodChannelEsp32NotificationSource(),
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now,
        _timerFactory = timerFactory ?? _defaultTimer;

  static final Esp32MqttNotificationForwarder instance =
      Esp32MqttNotificationForwarder(service: Esp32MqttService.instance);

  static final _logger = getLogger('Esp32MqttNotificationForwarder');

  final Esp32MqttService _service;
  final Esp32NotificationSource _source;
  final Future<SharedPreferences> Function() _prefsProvider;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _timerFactory;

  /// Queued notifications older than this are dropped on reconnect.
  final Duration queueTtl;

  /// Time in the background after the last send before the link is closed.
  final Duration backgroundIdle;

  Set<String> _allowedApps = Set<String>.from(kEsp32NotifDefaultApps);
  final List<_QueuedNotification> _queue = <_QueuedNotification>[];
  bool _started = false;
  bool _flushing = false;
  bool _appInForeground = true;
  StreamSubscription<void>? _connectedSub;
  Timer? _idleTimer;

  /// Whether the app is in the foreground. While false, the forwarder closes
  /// the link [backgroundIdle] after its last send.
  bool get appInForeground => _appInForeground;

  set appInForeground(bool value) {
    _appInForeground = value;
    if (value) {
      _idleTimer?.cancel();
      _idleTimer = null;
    }
  }

  /// Number of notifications waiting for the link. For tests and diagnostics.
  int get queuedCount => _queue.length;

  /// Idempotent. Loads the allowed apps, listens for notifications and flushes
  /// the queue whenever the link comes up.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await loadAllowedApps();
    _source.setOnNotification(_onNotification);
    _connectedSub = _service.onConnected.listen((_) => unawaited(_flushQueue()));
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _source.setOnNotification(null);
    await _connectedSub?.cancel();
    _connectedSub = null;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  Future<Set<String>> loadAllowedApps() async {
    final prefs = await _prefsProvider();
    final saved = prefs.getStringList(kEsp32NotifAllowedAppsPrefsKey);
    if (saved == null) {
      _allowedApps = Set<String>.from(kEsp32NotifDefaultApps);
    } else {
      _allowedApps = saved
          .map((e) => e.trim().toLowerCase())
          .where(kEsp32NotifSupportedApps.contains)
          .toSet();
    }
    return Set<String>.from(_allowedApps);
  }

  Future<void> saveAllowedApps(Set<String> apps) async {
    final normalized = apps
        .map((e) => e.trim().toLowerCase())
        .where(kEsp32NotifSupportedApps.contains)
        .toSet();
    _allowedApps = normalized;
    final prefs = await _prefsProvider();
    await prefs.setStringList(
      kEsp32NotifAllowedAppsPrefsKey,
      normalized.toList()..sort(),
    );
  }

  Future<bool> hasNotificationAccess() => _source.hasNotificationAccess();

  Future<void> openNotificationAccessSettings() =>
      _source.openNotificationAccessSettings();

  /// Publishes one notification if its app is supported and allowed. Returns
  /// true only when it was published now. Otherwise it is queued (when paired)
  /// and sent after the next connection.
  Future<bool> forward({
    required String app,
    required String title,
    required String body,
    bool silent = false,
  }) async {
    final normApp = app.trim().toLowerCase();
    if (!kEsp32NotifSupportedApps.contains(normApp) ||
        !_allowedApps.contains(normApp)) {
      return false;
    }

    final payload = jsonEncode(<String, dynamic>{
      'app': normApp,
      'title': esp32Utf8Truncate(title.trim(), kEsp32NotifMaxTitleBytes),
      'body': esp32Utf8Truncate(body.trim(), kEsp32NotifMaxBodyBytes),
      'silent': silent,
    });

    if (_service.status.value.link == Esp32MqttLinkState.connected) {
      final ok = await _service.publishEncrypted('notif', payload);
      if (ok) {
        _logger.fine('Notification sent for app $normApp');
        _armIdleDisconnect();
        return true;
      }
      _enqueue(payload);
      return false;
    }

    if (!_service.status.value.paired) return false;
    _enqueue(payload);
    _logger.fine('Notification queued for app $normApp (link down)');
    unawaited(_connectForQueue());
    return false;
  }

  Future<void> _connectForQueue() async {
    if (await _service.connect()) await _flushQueue();
  }

  void _onNotification(String app, String title, String body) {
    unawaited(forward(app: app, title: title, body: body));
  }

  void _enqueue(String payload) {
    _queue.add(_QueuedNotification(payload, _now()));
    _trimQueue();
  }

  void _trimQueue() {
    while (_queue.length > _kMaxQueuedNotifications) {
      _queue.removeAt(0);
    }
  }

  void _dropExpired() {
    final cutoff = _now().subtract(queueTtl);
    _queue.removeWhere((item) => item.queuedAt.isBefore(cutoff));
  }

  /// Publishes the queue in order. Stops at the first failed publish and keeps
  /// the rest for the next connection.
  Future<void> _flushQueue() async {
    if (_flushing) return;
    _flushing = true;
    try {
      _dropExpired();
      var sent = 0;
      while (_queue.isNotEmpty) {
        final item = _queue.first;
        final ok = await _service.publishEncrypted('notif', item.payload);
        if (!ok) break;
        _queue.remove(item);
        sent++;
      }
      if (sent > 0) {
        _logger.fine('Queued notifications sent: $sent');
        _armIdleDisconnect();
      }
    } finally {
      _flushing = false;
    }
  }

  void _armIdleDisconnect() {
    if (_appInForeground) return;
    _idleTimer?.cancel();
    _idleTimer = _timerFactory(backgroundIdle, () {
      _idleTimer = null;
      if (_appInForeground) return;
      unawaited(_service.disconnect());
    });
  }

  static Timer _defaultTimer(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
