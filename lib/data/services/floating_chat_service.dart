import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/utils/logger.dart';

enum ChatBubbleStatus { unsupported, off, posted, active, notifications }

/// Bridge to the Android floating sheets (F15-02, D-065; F15-05 Todo launches).
///
/// The native side keeps the pending launch from the intent. Dart asks for it
/// once at start-up ([takePendingLaunch]) and again on each `open` signal that
/// arrives while the app is already running ([openRequests]).
class FloatingChatService {
  FloatingChatService._() : _channel = _defaultChannel;

  @visibleForTesting
  FloatingChatService.forTesting({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static final FloatingChatService instance = FloatingChatService._();

  static const MethodChannel _defaultChannel =
      MethodChannel('com.memexlab.memex/floating_chat');

  static final _logger = getLogger('FloatingChatService');

  final MethodChannel _channel;
  final StreamController<FloatingLaunch> _openController =
      StreamController<FloatingLaunch>.broadcast();
  final _mainOpenedController = StreamController<void>.broadcast();

  /// Launches requested while the app is running (the sheet was opened again).
  Stream<FloatingLaunch> get openRequests => _openController.stream;
  Stream<void> get mainOpened => _mainOpenedController.stream;

  /// Installs the handler for native `open` signals. Call once at start-up.
  void initialize() {
    _channel.setMethodCallHandler(_handleCall);
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'mainOpened') {
      _mainOpenedController.add(null);
      return null;
    }
    if (call.method != 'open') return null;
    final launch = await takePendingLaunch();
    if (launch != null) _openController.add(launch);
    return null;
  }

  /// The mode waiting to be shown, cleared on read. Null when none is pending
  /// or the platform bridge is missing (iOS, tests).
  Future<FloatingChatMode?> takePendingMode() async =>
      (await takePendingLaunch())?.mode;

  /// The launch waiting to be shown (a mode and, for a Todo completion, its
  /// id), cleared on read. Null when none is pending or the bridge is missing.
  Future<FloatingLaunch?> takePendingLaunch() async {
    try {
      final raw = await _channel.invokeMethod<String>('takePendingMode');
      final launch = FloatingLaunch.parse(raw);
      if (raw != null && launch == null) {
        _logger.warning(
            'Ignoring unknown floating chat mode (length ${raw.length})');
      }
      return launch;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error, stackTrace) {
      _logger.warning('Could not read floating chat mode', error, stackTrace);
      return null;
    }
  }

  /// Finishes the floating sheet and returns to the screen that was below it.
  Future<void> close() => _invoke('close');

  /// Leaves the sheet for the full app.
  Future<void> openInApp() => _invoke('openInApp');

  Future<ChatBubbleStatus> bubbleStatus() => _readBubble('bubbleStatus');

  Future<ChatBubbleStatus> setBubbleVisible(bool visible) =>
      _readBubble(visible ? 'showBubble' : 'hideBubble');

  Future<void> openBubbleSettings({required bool notifications}) =>
      _channel.invokeMethod<void>('openBubbleSettings', {
        'notifications': notifications,
      });

  Future<ChatBubbleStatus> _readBubble(String method) async {
    try {
      final status = await _channel.invokeMethod<String>(method);
      return ChatBubbleStatus.values.firstWhere(
        (value) => value.name == status,
        orElse: () => ChatBubbleStatus.unsupported,
      );
    } on MissingPluginException {
      return ChatBubbleStatus.unsupported;
    }
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Not running inside the floating sheet (iOS, tests).
    } on PlatformException catch (error, stackTrace) {
      _logger.warning('Floating chat call $method failed', error, stackTrace);
    }
  }
}
