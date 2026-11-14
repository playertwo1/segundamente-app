import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/utils/logger.dart';

/// Bridge to the Android floating chat sheet (F15-02, D-065).
///
/// The native side keeps the pending mode from the launch intent. Dart asks
/// for it once at start-up ([takePendingMode]) and again on each `open` signal
/// that arrives while the app is already running ([openRequests]).
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
  final StreamController<FloatingChatMode> _openController =
      StreamController<FloatingChatMode>.broadcast();

  /// Modes requested while the app is running (the sheet was opened again).
  Stream<FloatingChatMode> get openRequests => _openController.stream;

  /// Installs the handler for native `open` signals. Call once at start-up.
  void initialize() {
    _channel.setMethodCallHandler(_handleCall);
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method != 'open') return null;
    final mode = await takePendingMode();
    if (mode != null) _openController.add(mode);
    return null;
  }

  /// The mode waiting to be shown, cleared on read. Null when none is pending
  /// or the platform bridge is missing (iOS, tests).
  Future<FloatingChatMode?> takePendingMode() async {
    try {
      final raw = await _channel.invokeMethod<String>('takePendingMode');
      final mode = FloatingChatMode.parse(raw);
      if (raw != null && mode == null) {
        _logger.warning('Ignoring unknown floating chat mode: $raw');
      }
      return mode;
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
