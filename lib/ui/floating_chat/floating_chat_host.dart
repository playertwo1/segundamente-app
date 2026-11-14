import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/routing/routes.dart';

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

/// Closes a floating sheet (chat or capture): the native close runs first, then
/// the sheet is popped so the screen below (where the app was) shows again. A
/// cold start has nothing below it, so it goes home. Either way the home screen
/// is never painted over the sheet.
Future<void> closeFloatingSheet(
  BuildContext context,
  FloatingChatService service,
) async {
  final router = GoRouter.of(context);
  await service.close();
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(AppRoutes.home);
  }
}
