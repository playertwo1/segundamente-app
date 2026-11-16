import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/use_cases/daily_briefing_builder.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/todo/view_models/todo_proposal_viewmodel.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/ui/todo/widgets/active_assistant_settings_page.dart';
import 'package:memex/ui/todo/widgets/todo_proposal_card.dart';
import 'package:memex/utils/user_storage.dart';

Future<void> showActiveAssistantSheet({
  required BuildContext context,
  required TodoViewModel viewModel,
  MemexRouter? router,
  TodoProposalViewModel? proposalViewModel,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => ActiveAssistantSheet(
      viewModel: viewModel,
      router: router,
      proposalViewModel: proposalViewModel,
    ),
  );
}

class ActiveAssistantSheet extends StatefulWidget {
  const ActiveAssistantSheet({
    super.key,
    required this.viewModel,
    this.router,
    this.proposalViewModel,
  });

  final TodoViewModel viewModel;
  final MemexRouter? router;
  final TodoProposalViewModel? proposalViewModel;

  @override
  State<ActiveAssistantSheet> createState() => _ActiveAssistantSheetState();
}

class _ActiveAssistantSheetState extends State<ActiveAssistantSheet> {
  late final TodoProposalViewModel _proposalViewModel;
  late final bool _ownsProposalViewModel;

  @override
  void initState() {
    super.initState();
    if (widget.proposalViewModel != null) {
      _proposalViewModel = widget.proposalViewModel!;
      _ownsProposalViewModel = false;
    } else {
      _proposalViewModel = TodoProposalViewModel(
        router: widget.router ?? widget.viewModel.router,
      );
      _ownsProposalViewModel = true;
    }
    _proposalViewModel.load();
  }

  @override
  void dispose() {
    if (_ownsProposalViewModel) {
      _proposalViewModel.dispose();
    }
    super.dispose();
  }

  bool _isSilenced() {
    final settings = widget.viewModel.activeAssistantState.settings;
    if (settings.silencedUntilIso != null) {
      final parsed = DateTime.tryParse(settings.silencedUntilIso!);
      if (parsed != null && parsed.isAfter(DateTime.now())) {
        return true;
      }
    }
    return settings.isSilencedAt(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;

    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final state = widget.viewModel.activeAssistantState;
        final briefing = state.briefing;
        final stalledNudges = state.stalledNudges;
        final personaSuggestions = state.personaSuggestions;
        final isSilenced = _isSilenced();

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.assistant_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.activeAssistantTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('active_assistant_sheet_silence'),
                          tooltip: isSilenced
                              ? l10n.activeAssistantClearSilence
                              : l10n.activeAssistantSilenceToday,
                          icon: Icon(
                            isSilenced
                                ? Icons.notifications_active
                                : Icons.notifications_off_outlined,
                            size: 20,
                          ),
                          onPressed: () async {
                            if (isSilenced) {
                              await widget.viewModel.activeAssistantService
                                  .saveSettings(
                                state.settings.copyWith(
                                  clearSilencedUntil: true,
                                ),
                              );
                              await widget.viewModel
                                  .refreshActiveAssistantState();
                            } else {
                              await widget.viewModel
                                  .silenceActiveAssistantFor(
                                const Duration(hours: 12),
                              );
                            }
                          },
                        ),
                        IconButton(
                          key: const ValueKey(
                            'active_assistant_sheet_open_settings',
                          ),
                          tooltip: l10n.activeAssistantSettingsTitle,
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ActiveAssistantSettingsPage(
                                  service:
                                      widget.viewModel.activeAssistantService,
                                ),
                              ),
                            );
                            if (mounted) {
                              await widget.viewModel
                                  .refreshActiveAssistantState();
                            }
                          },
                        ),
                        IconButton(
                          key: const ValueKey('active_assistant_sheet_close'),
                          tooltip: l10n.activeAssistantDismiss,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      shrinkWrap: true,
                      children: [
                        if (isSilenced)
                          Container(
                            key: const ValueKey(
                              'active_assistant_silenced_banner',
                            ),
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.notifications_off_outlined,
                                  color: AppColors.warning,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    l10n.activeAssistantSilencedNotice,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (briefing != null)
                          Container(
                            key: const ValueKey(
                              'active_assistant_briefing_card',
                            ),
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      briefing.period ==
                                              DailyBriefingPeriod.morning
                                          ? l10n.activeAssistantMorningBriefing
                                          : l10n
                                              .activeAssistantAfternoonBriefing,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    TextButton(
                                      key: const ValueKey(
                                        'active_assistant_briefing_dismiss',
                                      ),
                                      onPressed: () => widget.viewModel
                                          .dismissDailyBriefing(briefing),
                                      child: Text(l10n.activeAssistantDismiss),
                                    ),
                                  ],
                                ),
                                if (briefing.overdueTasks.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.activeAssistantOverdueGroup,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final task in briefing.overdueTasks)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.circle,
                                            size: 6,
                                            color: AppColors.danger,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              task.text,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (task.dueTime != null)
                                            Text(
                                              task.dueTime!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                                if (briefing.todayCommitments.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.activeAssistantCommitmentsGroup,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final task
                                      in briefing.todayCommitments)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.access_time,
                                            size: 14,
                                            color: AppColors.warning,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              task.text,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (task.dueTime != null)
                                            Text(
                                              task.dueTime!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                                if (briefing.priorityTasks.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.activeAssistantPrioritiesGroup,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final task in briefing.priorityTasks)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.flag_outlined,
                                            size: 14,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              task.text,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        if (stalledNudges.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              l10n.activeAssistantStalledSection,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          for (final nudge in stalledNudges)
                            Container(
                              key: ValueKey(
                                'active_assistant_stalled_${nudge.task.id}',
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          nudge.task.text,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.cardBackground,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          l10n.activeAssistantStalledDays(
                                            nudge.stalledDays,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        key: ValueKey(
                                          'stalled_snooze_${nudge.task.id}',
                                        ),
                                        onPressed: () => widget.viewModel
                                            .snoozeStalledTaskNudge(
                                          nudge.task.id,
                                        ),
                                        child: Text(
                                          l10n.activeAssistantStalledSnooze,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        key: ValueKey(
                                          'stalled_do_today_${nudge.task.id}',
                                        ),
                                        onPressed: () => widget.viewModel
                                            .scheduleStalledTaskForToday(
                                          nudge.task,
                                        ),
                                        child: Text(
                                          l10n.activeAssistantStalledDoToday,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (personaSuggestions.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              l10n.activeAssistantPersonaSection,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          for (final suggestion in personaSuggestions)
                            Container(
                              key: ValueKey(
                                'active_assistant_suggestion_${suggestion.id}',
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.person_outline,
                                        size: 18,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          suggestion.characterName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'suggestion_dismiss_${suggestion.id}',
                                        ),
                                        tooltip: l10n.activeAssistantDismiss,
                                        icon: const Icon(
                                          Icons.close,
                                          size: 18,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 48,
                                          minHeight: 48,
                                        ),
                                        onPressed: () => widget.viewModel
                                            .dismissPersonaSuggestion(
                                          suggestion.id,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (suggestion.message.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      suggestion.message,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  TodoProposalCard(
                                    proposal: suggestion.proposal,
                                    viewModel: _proposalViewModel,
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (briefing == null &&
                            stalledNudges.isEmpty &&
                            personaSuggestions.isEmpty &&
                            !isSilenced)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 36,
                              horizontal: 16,
                            ),
                            child: Center(
                              key: const ValueKey(
                                'active_assistant_empty_state',
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 48,
                                    color: AppColors.textTertiary,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.activeAssistantEmptyState,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
