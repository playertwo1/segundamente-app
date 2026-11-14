import 'package:flutter/widgets.dart';

/// Where [AgentChatDialog] runs when it is the floating sheet (F15-02). The
/// host decides what closing and opening in the app mean; the dialog only
/// reports the taps.
class FloatingChatHost {
  const FloatingChatHost({required this.onClose, required this.onOpenInApp});

  /// Close button, backdrop tap and system back.
  final VoidCallback onClose;

  /// Passes the current conversation id, or null when nothing was sent yet.
  final void Function(String? sessionId) onOpenInApp;
}
