import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/services/app_action_service.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/chat/widgets/agent_chat_dialog.dart';
import 'package:memex/ui/floating_chat/floating_chat_host.dart';
import 'package:memex/ui/floating_chat/view_models/listen_once_viewmodel.dart';

/// The floating chat sheet (F15-02): the super agent conversation drawn over
/// the screen that was below it. Closing returns to the home route.
class FloatingChatScreen extends StatelessWidget {
  const FloatingChatScreen({
    super.key,
    required this.mode,
    this.service,
    this.listenOnceForTesting,
  });

  final FloatingChatMode mode;
  final FloatingChatService? service;

  @visibleForTesting
  final ListenOnceViewModel? listenOnceForTesting;

  FloatingChatService get _service => service ?? FloatingChatService.instance;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AgentChatDialog(
          initialSessionId: null,
          floatingHost: FloatingChatHost(
            onClose: () => _close(context),
            onOpenInApp: (sessionId) => _openInApp(context, sessionId),
          ),
          autofocusInput: mode == FloatingChatMode.type,
          listenOnStart: mode == FloatingChatMode.talk,
          listenOnceForTesting: listenOnceForTesting,
        ),
      ),
    );
  }

  /// The native close runs first, then the sheet is popped so the screen below
  /// (where the app was) shows again. A cold start has nothing below it, so it
  /// goes home. Either way the home screen is never painted over the sheet.
  Future<void> _close(BuildContext context) =>
      closeFloatingSheet(context, _service);

  /// Opens the full app. A conversation that was started is shown there
  /// through the quick note action, which opens the super agent.
  Future<void> _openInApp(BuildContext context, String? sessionId) async {
    final router = GoRouter.of(context);
    router.go(AppRoutes.home);
    if (sessionId != null) {
      AppActionService.instance.handleAction(
        AppActionService.quickNoteAction,
        source: 'floating_chat',
      );
    }
    await _service.openInApp();
  }
}
