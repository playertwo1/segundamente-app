import 'package:flutter/material.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/ui/core/widgets/content_notice.dart';
import 'package:memex/ui/floating_chat/floating_chat_host.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/ui/todo/widgets/todo_screen.dart';

/// "+ tarefa" over the home screen (F15-05): the Todo editor the Todo screen
/// uses, shown as a dialog over the translucent sheet. A saved draft goes through
/// the router; cancelling or tapping outside only closes the sheet.
class FloatingTodoAddScreen extends StatefulWidget {
  const FloatingTodoAddScreen({
    super.key,
    required this.viewModel,
    this.service,
  });

  final TodoViewModel viewModel;
  final FloatingChatService? service;

  @override
  State<FloatingTodoAddScreen> createState() => _FloatingTodoAddScreenState();
}

class _FloatingTodoAddScreenState extends State<FloatingTodoAddScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _add());
  }

  Future<void> _add() async {
    final viewModel = widget.viewModel;
    await viewModel.refreshShortcutSettings();
    if (!mounted) return;
    final draft = await showTodoEditorDialog(
      context: context,
      settings: viewModel.shortcutSettings,
      notice: const ContentNoticeCaption(),
    );
    if (draft != null) {
      await viewModel.add(
        text: draft.text,
        due: draft.due,
        recurrence: draft.recurrence,
        priority: draft.priority,
        subtasks: draft.subtasks,
        alertMinutes: draft.alertMinutes,
      );
    }
    if (!mounted) return;
    await closeFloatingSheet(
      context,
      widget.service ?? FloatingChatService.instance,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}
