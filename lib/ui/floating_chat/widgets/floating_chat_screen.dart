import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/services/app_action_service.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/chat/widgets/agent_chat_dialog.dart';
import 'package:memex/ui/chat/widgets/open_super_agent_dialog.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/floating_chat/floating_chat_host.dart';
import 'package:memex/ui/floating_chat/view_models/listen_once_viewmodel.dart';

/// The floating chat sheet (F15-02): the super agent conversation drawn over
/// the screen that was below it. Closing returns to the home route.
class FloatingChatScreen extends StatefulWidget {
  const FloatingChatScreen({
    super.key,
    required this.mode,
    this.service,
    this.listenOnceForTesting,
    this.loadSessionId,
  });

  final FloatingChatMode mode;
  final FloatingChatService? service;
  @visibleForTesting
  final Future<String?> Function()? loadSessionId;

  @visibleForTesting
  final ListenOnceViewModel? listenOnceForTesting;

  @override
  State<FloatingChatScreen> createState() => _FloatingChatScreenState();
}

class _FloatingChatScreenState extends State<FloatingChatScreen> {
  late final Future<String?> _sessionId =
      (widget.loadSessionId ?? latestSuperAgentSessionId)();

  FloatingChatService get _service =>
      widget.service ?? FloatingChatService.instance;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FutureBuilder<String?>(
          future: _sessionId,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: AgentLogoLoading(size: 56));
            }
            final mode = widget.mode;
            return AgentChatDialog(
              key: ValueKey(mode),
              initialSessionId: snapshot.data,
              floatingHost: FloatingChatHost(
                fillsWindow: mode == FloatingChatMode.bubble,
                onClose: () => _close(context),
                onOpenInApp: (sessionId) => _openInApp(context, sessionId),
              ),
              autofocusInput: mode == FloatingChatMode.type,
              listenOnStart: mode == FloatingChatMode.talk,
              listenOnceForTesting: widget.listenOnceForTesting,
            );
          },
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
