import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/todo/view_models/todo_proposal_viewmodel.dart';
import 'package:memex/ui/todo/widgets/todo_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';

class TodoProposalCard extends StatefulWidget {
  const TodoProposalCard({
    super.key,
    required this.proposal,
    required this.viewModel,
  });

  final TodoProposal proposal;
  final TodoProposalViewModel viewModel;

  @override
  State<TodoProposalCard> createState() => _TodoProposalCardState();
}

class _TodoProposalCardState extends State<TodoProposalCard> {
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.viewModel.loading && widget.viewModel.settings == null) {
      widget.viewModel.load();
    }
  }

  Future<void> _reviewAndConfirm() async {
    final settings = widget.viewModel.settings;
    if (settings == null) {
      await widget.viewModel.load();
      if (!mounted || widget.viewModel.settings == null) {
        setState(() => _error = UserStorage.l10n.todoProposalSaveFailed);
        return;
      }
    }
    final saved = await showTodoEditorDialog(
      context: context,
      proposal: widget.proposal,
      settings: widget.viewModel.settings!,
    );
    if (saved == null || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    (await widget.viewModel.confirm(
      proposal: widget.proposal,
      text: saved.text,
      due: saved.due,
      priority: saved.priority,
      subtasks: saved.subtasks,
      alertMinutes: saved.alertMinutes,
      recurrence: saved.recurrence,
    ))
        .when(
      onOk: (item) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error =
              item.isTombstoned ? UserStorage.l10n.todoProposalDeleted : null;
        });
      },
      onError: (error, _) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = UserStorage.l10n.todoProposalSaveFailed;
        });
      },
    );
    await widget.viewModel.load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final existing = widget.viewModel.taskFor(widget.proposal.id);
        final added = existing != null && !existing.isTombstoned;
        final deleted = existing?.isTombstoned == true;
        final locale = Localizations.localeOf(context).toString();
        final date = widget.proposal.dateState == TodoProposalDateState.explicit
            ? DateFormat.yMMMd(locale).format(
                DateTime.parse(widget.proposal.dueDate!),
              )
            : widget.proposal.dateState == TodoProposalDateState.ambiguous
                ? widget.proposal.datePhrase ?? l10n.todoProposalDateUnclear
                : l10n.todoProposalNoDate;
        final time = switch (widget.proposal.timeState) {
          TodoProposalTimeState.explicit => widget.proposal.dueTime!,
          TodoProposalTimeState.ambiguous =>
            widget.proposal.timePhrase ?? l10n.todoProposalTimeUnclear,
          TodoProposalTimeState.unspecified => l10n.todoNoTime,
        };

        return Container(
          key: ValueKey('todo_proposal_${widget.proposal.id}'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.todoProposalHeading,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.proposal.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$date · $time',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              if (widget.proposal.timeState == TodoProposalTimeState.explicit)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.todoProposalAlertHint(
                      widget.viewModel.settings?.defaultAlertMinutes ?? 20,
                    ),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('todo_proposal_error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (widget.viewModel.loading && existing == null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                )
              else if (added)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.todoProposalAdded,
                    key: const ValueKey('todo_proposal_added'),
                  ),
                )
              else if (deleted)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.todoProposalDeleted,
                    key: const ValueKey('todo_proposal_deleted'),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonal(
                      key: const ValueKey('todo_proposal_review'),
                      onPressed: _saving ? null : _reviewAndConfirm,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.todoProposalReview),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
