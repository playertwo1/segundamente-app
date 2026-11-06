import 'package:flutter/material.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/session_report_screen.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key, required this.viewModel});

  final TodoViewModel viewModel;

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.viewModel.load();
    });
  }

  Future<void> _addOrEdit([TodoItem? item]) async {
    final saved = await showDialog<({String text, String due})>(
      context: context,
      builder: (_) => _TodoDialog(item: item),
    );
    if (saved == null) return;
    if (item == null) {
      await widget.viewModel.add(text: saved.text, due: saved.due);
    } else {
      await widget.viewModel.edit(item, text: saved.text, due: saved.due);
    }
  }

  Future<void> _remove(TodoItem item) async {
    final l10n = UserStorage.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(l10n.confirmDelete),
        content: Text(l10n.todoDeleteMessage),
        actions: [
          TextButton(
            key: const ValueKey('todo_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('todo_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true) await widget.viewModel.remove(item);
  }

  Future<void> _calendar(TodoItem item) async {
    final opened = await widget.viewModel.addToCalendar(item);
    if (!opened && mounted) {
      ToastHelper.showError(context, UserStorage.l10n.addToCalendarFailed);
    }
  }

  Future<void> _reminder(TodoItem item) async {
    final l10n = UserStorage.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(l10n.todoReminderTitle),
        content: Text(l10n.todoReminderBody(item.text, item.due)),
        actions: [
          TextButton(
            key: const ValueKey('todo_reminder_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.sendBack),
          ),
          TextButton(
            key: const ValueKey('todo_reminder_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.todoReminderConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final outcome = await widget.viewModel.addReminder(item);
    if (!mounted) return;
    switch (outcome) {
      case ReminderOutcome.created:
        ToastHelper.showSuccess(context, l10n.todoReminderCreated);
      case ReminderOutcome.permissionDenied:
        ToastHelper.showError(
            context, l10n.permissionRequired(l10n.reminders));
      case ReminderOutcome.noExactTime:
      case ReminderOutcome.failed:
        ToastHelper.showError(context, l10n.writeToSystemFailed);
    }
  }

  void _openSource(TodoItem item) {
    Navigator.of(context).push(
      SessionReportScreen.route(
        router: widget.viewModel.router,
        sessionId: item.source!.sessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.todoTitle),
        actions: [
          IconButton(
            key: const ValueKey('todo_add'),
            tooltip: l10n.todoAdd,
            icon: const Icon(Icons.add),
            onPressed: _addOrEdit,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final viewModel = widget.viewModel;
          if (viewModel.loading && !viewModel.hasAny) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = viewModel.items;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const ValueKey('todo_search'),
                  decoration: InputDecoration(hintText: l10n.todoSearchHint),
                  onChanged: viewModel.search,
                ),
              ),
              if (viewModel.errorMessage != null)
                Text(
                  viewModel.errorMessage!,
                  key: const ValueKey('todo_error'),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            viewModel.hasAny
                                ? l10n.todoNoResults
                                : l10n.todoEmpty,
                            textAlign: TextAlign.center,
                            key: const ValueKey('todo_empty'),
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final item in items) _tile(item, l10n),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(TodoItem item, AppLocalizations l10n) {
    final source = item.source;
    return ListTile(
      key: ValueKey('todo_${item.id}'),
      leading: Checkbox(
        key: ValueKey('todo_done_${item.id}'),
        value: item.done,
        onChanged: (_) => widget.viewModel.toggleDone(item),
      ),
      title: Text(
        item.text,
        style: item.done
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.due),
          if (source != null)
            InkWell(
              key: ValueKey('todo_source_${item.id}'),
              onTap: () => _openSource(item),
              child: Text(
                '${l10n.todoOpenSource}: ${source.clock ?? ''} '
                '"${source.excerpt}"',
              ),
            ),
        ],
      ),
      onTap: () => _addOrEdit(item),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!item.done && calendarSlotFor(item.due) != null)
            IconButton(
              key: ValueKey('todo_calendar_${item.id}'),
              tooltip: l10n.addToCalendar,
              icon: const Icon(Icons.event_outlined),
              onPressed: () => _calendar(item),
            ),
          if (!item.done && TodoViewModel.reminderTimeFor(item.due) != null)
            IconButton(
              key: ValueKey('todo_reminder_${item.id}'),
              tooltip: l10n.addToReminders,
              icon: const Icon(Icons.alarm_add_outlined),
              onPressed: () => _reminder(item),
            ),
          IconButton(
            key: ValueKey('todo_remove_${item.id}'),
            tooltip: l10n.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _remove(item),
          ),
        ],
      ),
    );
  }
}

class _TodoDialog extends StatefulWidget {
  const _TodoDialog({this.item});

  final TodoItem? item;

  @override
  State<_TodoDialog> createState() => _TodoDialogState();
}

class _TodoDialogState extends State<_TodoDialog> {
  late final _text = TextEditingController(text: widget.item?.text ?? '');
  late final _due = TextEditingController(
    text: widget.item == null || widget.item!.due == reportDueUnknown
        ? ''
        : widget.item!.due,
  );

  @override
  void dispose() {
    _text.dispose();
    _due.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(widget.item == null ? l10n.todoAdd : l10n.todoEdit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('todo_text'),
            controller: _text,
            decoration: InputDecoration(hintText: l10n.todoTextHint),
          ),
          TextField(
            key: const ValueKey('todo_due'),
            controller: _due,
            decoration: InputDecoration(hintText: l10n.todoDueHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('todo_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('todo_dialog_save'),
          onPressed: () {
            if (_text.text.trim().isEmpty) return;
            Navigator.of(context).pop((text: _text.text, due: _due.text));
          },
          child: Text(l10n.todoSave),
        ),
      ],
    );
  }
}
