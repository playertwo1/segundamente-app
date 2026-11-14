import 'package:flutter/material.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/ui/floating_chat/floating_chat_host.dart';
import 'package:memex/ui/floating_chat/view_models/floating_todo_complete_viewmodel.dart';

/// No UI (F15-05): the circle on the widget completes its task, then the
/// translucent Activity closes and the screen below shows again.
class FloatingTodoCompleteScreen extends StatefulWidget {
  const FloatingTodoCompleteScreen({
    super.key,
    required this.viewModel,
    this.service,
  });

  final FloatingTodoCompleteViewModel viewModel;
  final FloatingChatService? service;

  @override
  State<FloatingTodoCompleteScreen> createState() =>
      _FloatingTodoCompleteScreenState();
}

class _FloatingTodoCompleteScreenState
    extends State<FloatingTodoCompleteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    await widget.viewModel.complete();
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
