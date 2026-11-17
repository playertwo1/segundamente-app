import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:memex/data/services/todo_sync_service.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_alarm_status.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/session_report_screen.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/local_image.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/ui/todo/widgets/active_assistant_sheet.dart';
import 'package:memex/ui/todo/widgets/todo_add_button.dart';
import 'package:memex/ui/todo/widgets/todo_done_circle.dart';
import 'package:memex/ui/todo/widgets/todo_priority_style.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:photo_view/photo_view.dart';
import 'package:uuid/uuid.dart';

typedef TodoDraft = ({
  String text,
  String due,
  TodoRecurrence? recurrence,
  TodoPriority priority,
  List<TodoSubtask> subtasks,
  int alertMinutes,
  List<String> attachments,
});

/// Opens the full-screen task editor. [notice] is shown under the fields; the
/// floating "+ tarefa" sheet passes the F11-06 content notice (F15-05). The
/// Todo screen passes none. [photos] adds the photo buttons when given (the
/// view model picks and stores them). Pops a [TodoDraft] on save, null on cancel.
Future<TodoDraft?> showTodoEditorDialog({
  required BuildContext context,
  required TodoShortcutSettings settings,
  TodoItem? item,
  TodoProposal? proposal,
  Widget? notice,
  TodoViewModel? photos,
}) =>
    showGeneralDialog<TodoDraft>(
      context: context,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => _TodoEditorPage(
        item: item,
        proposal: proposal,
        settings: settings,
        notice: notice,
        photos: photos,
      ),
    );

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key, required this.viewModel});

  final TodoViewModel viewModel;

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  AppLifecycleState? _lastLifecycleState;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: todoTabSections.length,
      vsync: this,
      initialIndex: _tabIndexOf(widget.viewModel.section),
    )..addListener(_onTabChanged);
    widget.viewModel.addListener(_syncTabControllerFromViewModel);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.viewModel.load();
    });
  }

  @override
  void didUpdateWidget(covariant TodoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_syncTabControllerFromViewModel);
      widget.viewModel.addListener(_syncTabControllerFromViewModel);
      _syncTabControllerFromViewModel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.viewModel.load();
      });
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_syncTabControllerFromViewModel);
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Upcoming has no tab of its own; it shows inside the all tab.
  int _tabIndexOf(TodoListSection section) {
    final index = todoTabSections.indexOf(section);
    return index < 0 ? 0 : index;
  }

  void _onTabChanged() {
    final target = todoTabSections[_tabController.index];
    if (widget.viewModel.section != target) {
      widget.viewModel.selectSection(target);
    }
  }

  void _syncTabControllerFromViewModel() {
    if (!mounted) return;
    final targetIndex = _tabIndexOf(widget.viewModel.section);
    if (_tabController.index != targetIndex) {
      _tabController.animateTo(targetIndex);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _lastLifecycleState != null &&
        _lastLifecycleState != AppLifecycleState.resumed) {
      unawaited(widget.viewModel.refreshOnResume());
    }
    _lastLifecycleState = state;
  }

  Future<void> _addOrEdit([TodoItem? item]) async {
    await widget.viewModel.refreshShortcutSettings();
    if (!mounted) return;
    final saved = await showTodoEditorDialog(
      context: context,
      item: item,
      settings: widget.viewModel.shortcutSettings,
      photos: widget.viewModel,
    );
    if (saved == null) return;
    if (item == null) {
      await widget.viewModel.add(
        text: saved.text,
        due: saved.due,
        recurrence: saved.recurrence,
        priority: saved.priority,
        subtasks: saved.subtasks,
        alertMinutes: saved.alertMinutes,
        attachments: saved.attachments,
      );
    } else {
      await widget.viewModel.edit(
        item,
        text: saved.text,
        due: saved.due,
        recurrence: saved.recurrence,
        clearRecurrence: saved.recurrence == null,
        priority: saved.priority,
        subtasks: saved.subtasks,
        alertMinutes: saved.alertMinutes,
        attachments: saved.attachments,
      );
    }
  }

  Future<void> _remove(TodoItem item) async {
    if (!await widget.viewModel.remove(item) || !mounted) return;
    final l10n = UserStorage.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.todoDeleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: l10n.todoUndo,
          onPressed: () => widget.viewModel.restore(item),
        ),
      ));
  }

  Future<void> _calendar(TodoItem item) async {
    final opened = await widget.viewModel.addToCalendar(item);
    if (!opened && mounted) {
      ToastHelper.showError(context, UserStorage.l10n.addToCalendarFailed);
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

  Future<void> _openSearch() => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _TodoSearchScreen(
            viewModel: widget.viewModel,
            onEdit: _addOrEdit,
            onDelete: _remove,
            onCalendar: _calendar,
            onOpenSource: _openSource,
          ),
        ),
      );

  Future<void> _taskAction(TodoItem item, _TodoTaskAction action) async {
    switch (action) {
      case _TodoTaskAction.edit:
        await _addOrEdit(item);
      case _TodoTaskAction.delete:
        await _remove(item);
      case _TodoTaskAction.calendar:
        await _calendar(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.todoTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          // Rebuilt with the view model so the overdue count stays current.
          child: ListenableBuilder(
            listenable: widget.viewModel,
            builder: (context, _) => TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final section in todoTabSections)
                  _tab(l10n, section, widget.viewModel),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('todo_open_active_assistant'),
            tooltip: l10n.activeAssistantTitle,
            icon: const Icon(Icons.assistant_outlined),
            onPressed: () => showActiveAssistantSheet(
              context: context,
              viewModel: widget.viewModel,
            ),
          ),
          IconButton(
            key: const ValueKey('todo_open_search'),
            tooltip: l10n.todoSearchHint,
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          _TodoPriorityFilterButton(viewModel: widget.viewModel),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: widget.viewModel,
            builder: (context, _) {
              final viewModel = widget.viewModel;
              if (viewModel.loading && !viewModel.hasAny) {
                return const Center(child: CircularProgressIndicator());
              }
              if (viewModel.errorMessage != null && !viewModel.hasAny) {
                return _loadError(l10n, viewModel);
              }
              return Column(
                children: [
                  if (_alarmPermissionBanner(l10n, viewModel)
                      case final banner?)
                    banner,
                  if (viewModel.damagedLegacyFileName case final fileName?)
                    ListTile(
                      key: const ValueKey('todo_legacy_damaged_banner'),
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(l10n.todoLegacyFileDamaged(fileName)),
                    ),
                  if (viewModel.errorMessage != null)
                    MaterialBanner(
                      key: const ValueKey('todo_error'),
                      content: Text(l10n.todoLoadFailed),
                      actions: [
                        TextButton(
                          onPressed: viewModel.load,
                          child: Text(l10n.todoRetry),
                        ),
                      ],
                    ),
                  if (_shouldShowSyncStatus(viewModel.syncStatus))
                    _syncStatusBar(l10n, viewModel, context),
                  if (viewModel.priorityFilter case final priority?)
                    _activeFilterBar(l10n, viewModel, priority, context),
                  if (viewModel.conflicts.isNotEmpty)
                    _conflictsBanner(l10n, viewModel, context),
                  if (viewModel.activeAssistantItemCount > 0)
                    _activeAssistantSummaryBar(l10n, viewModel, context),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        for (final section in todoTabSections)
                          _sectionBody(viewModel, l10n, section),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: _addButton(l10n),
          ),
        ],
      ),
    );
  }

  /// The round + button, floating over the list's bottom right corner.
  Widget _addButton(AppLocalizations l10n) => Semantics(
        button: true,
        label: l10n.todoAdd,
        child: TodoAddButton(
          key: const ValueKey('todo_add'),
          onTap: () => _addOrEdit(),
        ),
      );

  /// A tab label. The overdue tab shows its open count in amber when above zero.
  Widget _tab(
    AppLocalizations l10n,
    TodoListSection section,
    TodoViewModel viewModel,
  ) {
    final label = _tabLabel(l10n, section);
    if (section != TodoListSection.overdue || viewModel.overdueCount == 0) {
      return Tab(text: label);
    }
    final count = viewModel.overdueCount;
    return Tab(
      child: Semantics(
        container: true,
        label: l10n.todoOverdueTabSemantics(count),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.primary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(AppLocalizations l10n, TodoListSection section) =>
      switch (section) {
        TodoListSection.all => l10n.todoTabAll,
        TodoListSection.today => l10n.todoTabToday,
        TodoListSection.upcoming => l10n.todoTabUpcoming,
        TodoListSection.overdue => l10n.todoTabOverdue,
        TodoListSection.completed => l10n.todoTabCompleted,
      };

  String _sectionTitle(AppLocalizations l10n, TodoSectionKey key) =>
      switch (key) {
        TodoSectionKey.overdue => l10n.todoTabOverdue,
        TodoSectionKey.today => l10n.todoTabToday,
        TodoSectionKey.upcoming => l10n.todoTabUpcoming,
        TodoSectionKey.undated => l10n.todoUndatedSection,
        TodoSectionKey.completed => l10n.todoTabCompleted,
      };

  Widget _activeAssistantSummaryBar(
    AppLocalizations l10n,
    TodoViewModel viewModel,
    BuildContext context,
  ) =>
      Material(
        color: AppColors.surface,
        child: InkWell(
          key: const ValueKey('todo_active_assistant_bar'),
          onTap: () => showActiveAssistantSheet(
            context: context,
            viewModel: widget.viewModel,
          ),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.assistant_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.activeAssistantSummaryBanner(
                      viewModel.activeAssistantItemCount,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _activeFilterBar(
    AppLocalizations l10n,
    TodoViewModel viewModel,
    TodoPriority priority,
    BuildContext context,
  ) =>
      Container(
        key: const ValueKey('todo_active_filter_bar'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color: _priorityColor(priority),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l10n.todoPriorityLabel}: ${_priorityLabel(l10n, priority)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
              ),
            ),
            TextButton(
              key: const ValueKey('todo_clear_priority_filter'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: () => viewModel.setPriorityFilter(null),
              child: Text(l10n.todoFilterClear),
            ),
          ],
        ),
      );

  Widget _syncStatusBar(
    AppLocalizations l10n,
    TodoViewModel viewModel,
    BuildContext context,
  ) {
    final status = viewModel.syncStatus;
    final isSyncing = status.state == TodoSyncBadgeState.syncing;
    final label = switch (status.state) {
      TodoSyncBadgeState.synced => l10n.todoSyncSynced,
      TodoSyncBadgeState.syncing => l10n.todoSyncSyncing,
      TodoSyncBadgeState.revoked => l10n.todoSyncRevoked,
      TodoSyncBadgeState.error => l10n.todoSyncError,
      TodoSyncBadgeState.offline => l10n.todoSyncOffline,
      TodoSyncBadgeState.waitingPc => () {
          final pending = status.pendingOutbox + (status.pendingPc ?? 0);
          return pending > 0
              ? l10n.todoSyncPendingChanges(pending)
              : l10n.todoSyncSavedOnDevice;
        }(),
      TodoSyncBadgeState.savedOnDevice ||
      TodoSyncBadgeState.localOnly =>
        status.pendingOutbox > 0
            ? l10n.todoSyncPendingChanges(status.pendingOutbox)
            : l10n.todoSyncSavedOnDevice,
    };
    final formattedTime = _formatLastSyncTime(context, status.lastSyncedAt);
    final lastSyncLabel =
        formattedTime != null && status.paired && !status.revoked
            ? l10n.todoSyncLastSuccess(formattedTime)
            : null;
    final iconColor = switch (status.state) {
      TodoSyncBadgeState.synced => AppColors.success,
      TodoSyncBadgeState.revoked => AppColors.danger,
      TodoSyncBadgeState.error => AppColors.warning,
      TodoSyncBadgeState.syncing => AppColors.primary,
      TodoSyncBadgeState.waitingPc ||
      TodoSyncBadgeState.savedOnDevice ||
      TodoSyncBadgeState.offline ||
      TodoSyncBadgeState.localOnly =>
        AppColors.textSecondary,
    };
    final iconData = switch (status.state) {
      TodoSyncBadgeState.synced => Icons.cloud_done_outlined,
      TodoSyncBadgeState.revoked => Icons.link_off,
      TodoSyncBadgeState.error => Icons.sync_problem_outlined,
      TodoSyncBadgeState.offline => Icons.cloud_off_outlined,
      TodoSyncBadgeState.syncing => Icons.sync,
      TodoSyncBadgeState.waitingPc ||
      TodoSyncBadgeState.savedOnDevice ||
      TodoSyncBadgeState.localOnly =>
        Icons.smartphone_outlined,
    };

    return Container(
      key: const ValueKey('todo_sync_status_bar'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSyncing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(iconData, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (lastSyncLabel != null)
                      Text(
                        lastSyncLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (status.paired && !status.revoked)
            TextButton(
              key: const ValueKey('todo_sync_now_button'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: isSyncing ? null : () => viewModel.syncNow(),
              child: Text(l10n.todoSyncNowButton),
            ),
        ],
      ),
    );
  }

  Widget _conflictsBanner(
    AppLocalizations l10n,
    TodoViewModel viewModel,
    BuildContext context,
  ) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.45;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final conflict in viewModel.conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _conflictCard(l10n, viewModel, conflict, context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _conflictCard(
    AppLocalizations l10n,
    TodoViewModel viewModel,
    TaskTextConflict conflict,
    BuildContext context,
  ) =>
      Container(
        key: ValueKey('todo_conflict_card_${conflict.id}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.todoConflictBannerTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.todoConflictBannerSubtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _conflictOptionBox(
              label: l10n.todoConflictLocalLabel,
              value: conflict.localText,
              context: context,
            ),
            const SizedBox(height: 6),
            _conflictOptionBox(
              label: l10n.todoConflictRemoteLabel,
              value: conflict.remoteText,
              context: context,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: ValueKey('todo_conflict_keep_local_${conflict.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.divider),
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () => viewModel.resolveConflict(
                    conflict.id,
                    keepLocal: true,
                  ),
                  child: Text(l10n.todoConflictKeepLocal),
                ),
                FilledButton(
                  key: ValueKey('todo_conflict_use_remote_${conflict.id}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () => viewModel.resolveConflict(
                    conflict.id,
                    keepLocal: false,
                  ),
                  child: Text(l10n.todoConflictUseRemote),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _conflictOptionBox({
    required String label,
    required String value,
    required BuildContext context,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
          ],
        ),
      );

  String? _formatLastSyncTime(BuildContext context, String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(iso.trim());
    if (parsed == null) return null;
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.Hm(locale).format(parsed.toLocal());
  }

  Widget? _alarmPermissionBanner(
    AppLocalizations l10n,
    TodoViewModel viewModel,
  ) {
    if (viewModel.alarmStatus == TodoAlarmStatus.ready ||
        viewModel.alarmStatus == TodoAlarmStatus.unsupported) {
      return null;
    }
    final message = switch (viewModel.alarmStatus) {
      TodoAlarmStatus.notificationsDenied => l10n.todoAlarmNotificationsDenied,
      TodoAlarmStatus.exactAlarmsDenied => l10n.todoAlarmExactDenied,
      TodoAlarmStatus.bothPermissionsDenied => l10n.todoAlarmBothDenied,
      TodoAlarmStatus.unavailable => l10n.todoAlarmUnavailable,
      TodoAlarmStatus.ready || TodoAlarmStatus.unsupported => null,
    };
    if (message == null) return null;
    return MaterialBanner(
      key: const ValueKey('todo_alarm_permission_banner'),
      content: Text(message),
      actions: [
        TextButton(
          key: const ValueKey('todo_alarm_configure'),
          onPressed: viewModel.configureAlarmPermissions,
          child: Text(l10n.todoAlarmConfigure),
        ),
      ],
    );
  }

  Widget _loadError(AppLocalizations l10n, TodoViewModel viewModel) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.todoLoadFailed, key: const ValueKey('todo_error')),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('todo_retry'),
                onPressed: viewModel.load,
                child: Text(l10n.todoRetry),
              ),
            ],
          ),
        ),
      );

  Widget _sectionBody(
    TodoViewModel viewModel,
    AppLocalizations l10n,
    TodoListSection section,
  ) {
    if (section == TodoListSection.all) {
      return _allBody(viewModel, l10n);
    }
    final items = viewModel.itemsFor(section);
    if (items.isEmpty) {
      final message = switch (section) {
        TodoListSection.all => l10n.todoEmptyAll,
        TodoListSection.today => l10n.todoEmptyToday,
        TodoListSection.upcoming => l10n.todoEmptyUpcoming,
        TodoListSection.overdue => l10n.todoEmptyOverdue,
        TodoListSection.completed => l10n.todoEmptyCompleted,
      };
      return _emptyBody(
        viewModel,
        l10n,
        message,
        showAdd: section == TodoListSection.today,
      );
    }
    final undated = section == TodoListSection.today
        ? [
            for (final item in items)
              if (viewModel.stateFor(item) == TodoTaskState.noDate) item,
          ]
        : const <TodoItem>[];
    final dated = undated.isEmpty
        ? items
        : [
            for (final item in items)
              if (!undated.contains(item)) item
          ];
    return ListView(
      key: ValueKey('todo_section_${section.name}'),
      // Keeps the last card clear of the floating add pill.
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final item in dated) _taskRow(item, l10n, viewModel),
        if (undated.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
            child: Text(
              l10n.todoUndatedSection,
              key: const ValueKey('todo_undated_header'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          for (final item in undated) _taskRow(item, l10n, viewModel),
        ],
      ],
    );
  }

  Widget _emptyBody(
    TodoViewModel viewModel,
    AppLocalizations l10n,
    String message, {
    required bool showAdd,
  }) {
    final hasFilter = viewModel.priorityFilter != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasFilter ? l10n.todoFilterEmpty : message,
              key: const ValueKey('todo_empty'),
              textAlign: TextAlign.center,
            ),
            if (hasFilter) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                key: const ValueKey('todo_empty_clear_filter'),
                onPressed: () => viewModel.setPriorityFilter(null),
                icon: const Icon(Icons.filter_list_off),
                label: Text(l10n.todoFilterClear),
              ),
            ] else if (showAdd && !viewModel.hasAny) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _addOrEdit,
                icon: const Icon(Icons.add),
                label: Text(l10n.todoAdd),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The all tab: one collapsible section per group, in the order the view
  /// model gives. Each header shows the section name and its count.
  Widget _allBody(TodoViewModel viewModel, AppLocalizations l10n) {
    final groups = viewModel.allSections;
    if (groups.isEmpty) {
      return _emptyBody(
        viewModel,
        l10n,
        l10n.todoEmptyAll,
        showAdd: true,
      );
    }
    return ListView(
      key: const ValueKey('todo_section_all'),
      // Keeps the last card clear of the floating add button.
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final (index, group) in groups.indexed)
          Column(
            key: ValueKey('todo_all_section_${group.key.name}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                // 12 above every section but the first.
                padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                child: _sectionHeader(viewModel, l10n, group),
              ),
              if (!viewModel.isSectionCollapsed(group.key))
                for (final item in group.items)
                  _taskRow(item, l10n, viewModel),
            ],
          ),
      ],
    );
  }

  /// A 40 dp section header inside a 48 dp touch target. The count animates
  /// when it changes: the new number comes in from 4 dp above.
  Widget _sectionHeader(
    TodoViewModel viewModel,
    AppLocalizations l10n,
    TodoSectionGroup group,
  ) {
    final collapsed = viewModel.isSectionCollapsed(group.key);
    final title = _sectionTitle(l10n, group.key);
    final count = group.items.length;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      // Own node, so the cards after it are not read as part of the header.
      container: true,
      button: true,
      expanded: !collapsed,
      label: '$title · $count',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('todo_section_toggle_${group.key.name}'),
        onTap: () => viewModel.toggleSection(group.key),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelLarge?.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: AnimatedBuilder(
                              animation: animation,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(0, -4 * (1 - animation.value)),
                                child: child,
                              ),
                              child: child,
                            ),
                          ),
                          child: ExcludeSemantics(
                            key: ValueKey(count),
                            child: Text(
                              ' · $count',
                              style: textTheme.labelLarge?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const ExcludeSemantics(
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskRow(
    TodoItem item,
    AppLocalizations l10n,
    TodoViewModel viewModel,
  ) =>
      _TodoTaskRow(
        key: ValueKey('todo_row_${item.id}'),
        item: item,
        viewModel: viewModel,
        onEdit: () => _addOrEdit(item),
        onDone: (done) => _setDone(item, done),
        onSubtask: (subtask) => viewModel.toggleSubtask(item, subtask),
        onAction: (action) => _taskAction(item, action),
        onOpenSource: () => _openSource(item),
      );

  /// Completing animates the card and keeps it in place for its exit length;
  /// the write itself is immediate. Reopening only writes.
  Future<void> _setDone(TodoItem item, bool done) {
    if (done && !item.done) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      return widget.viewModel.completeTask(
        item,
        exitDuration: reduced ? todoReducedExit : todoCompleteExit,
      );
    }
    return widget.viewModel.toggleDone(item);
  }
}

enum _TodoTaskAction { edit, delete, calendar }

class _TodoPriorityFilterButton extends StatelessWidget {
  const _TodoPriorityFilterButton({required this.viewModel});

  final TodoViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => PopupMenuButton<String>(
        key: const ValueKey('todo_priority_filter'),
        tooltip: l10n.todoFilter,
        icon: Icon(
          Icons.filter_list,
          color: viewModel.priorityFilter == null ? null : AppColors.primary,
        ),
        onSelected: (value) => viewModel.setPriorityFilter(
          value == 'all'
              ? null
              : TodoPriority.values
                  .firstWhere((priority) => priority.name == value),
        ),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'all', child: Text(l10n.todoFilterAll)),
          for (final priority in TodoPriority.values)
            PopupMenuItem(
              value: priority.name,
              child: Text(
                _priorityLabel(l10n, priority),
                style: TextStyle(color: _priorityColor(priority)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodoSearchScreen extends StatefulWidget {
  const _TodoSearchScreen({
    required this.viewModel,
    required this.onEdit,
    required this.onDelete,
    required this.onCalendar,
    required this.onOpenSource,
  });

  final TodoViewModel viewModel;
  final Future<void> Function(TodoItem item) onEdit;
  final Future<void> Function(TodoItem item) onDelete;
  final Future<void> Function(TodoItem item) onCalendar;
  final void Function(TodoItem item) onOpenSource;

  @override
  State<_TodoSearchScreen> createState() => _TodoSearchScreenState();
}

class _TodoSearchScreenState extends State<_TodoSearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _action(TodoItem item, _TodoTaskAction action) async {
    switch (action) {
      case _TodoTaskAction.edit:
        await widget.onEdit(item);
      case _TodoTaskAction.delete:
        await widget.onDelete(item);
      case _TodoTaskAction.calendar:
        await widget.onCalendar(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.todoSearchResultsHeader),
        actions: [
          _TodoPriorityFilterButton(viewModel: widget.viewModel),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final results = widget.viewModel.searchResults(_query);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  key: const ValueKey('todo_search'),
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.todoSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('todo_search_clear'),
                            tooltip: l10n.todoFilterClear,
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (_query.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.todoSearchResultsCount(results.length)),
                  ),
                ),
              Expanded(
                child: _query.trim().isEmpty
                    ? Center(child: Text(l10n.todoSearchStart))
                    : results.isEmpty
                        ? Center(
                            child: Text(
                              l10n.todoNoResults,
                              key: const ValueKey('todo_search_empty'),
                            ),
                          )
                        : ListView(
                            key: const ValueKey('todo_search_results'),
                            children: [
                              for (final item in results)
                                _TodoTaskRow(
                                  key: ValueKey('todo_row_${item.id}'),
                                  animated: false,
                                  item: item,
                                  viewModel: widget.viewModel,
                                  onEdit: () => widget.onEdit(item),
                                  onDone: (_) =>
                                      widget.viewModel.toggleDone(item),
                                  onSubtask: (subtask) => widget.viewModel
                                      .toggleSubtask(item, subtask),
                                  onAction: (action) => _action(item, action),
                                  onOpenSource: () => widget.onOpenSource(item),
                                ),
                            ],
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

bool _shouldShowSyncStatus(TodoSyncStatus status) =>
    status.paired ||
    status.pendingOutbox > 0 ||
    status.state == TodoSyncBadgeState.syncing ||
    status.state == TodoSyncBadgeState.error ||
    status.state == TodoSyncBadgeState.offline ||
    status.state == TodoSyncBadgeState.revoked ||
    status.conflicts.isNotEmpty;

const _enterCurve = Cubic(0.16, 1, 0.3, 1);
const _completeExitMs = 1080;
const _reducedExitMs = 150;
const _enterMs = 820;
const _cardEnterMs = 380;
const _sweepStartMs = 120;
const _sweepMs = 700;

/// Completion animation length, and the fade that replaces it when the system
/// asks for reduced motion. The screen passes the same length to the view model.
const todoCompleteExit = Duration(milliseconds: _completeExitMs);
const todoReducedExit = Duration(milliseconds: _reducedExitMs);

/// Pulse of the completion circle: 0 to 1 and back, over one unit of time.
double _pulse(double s) => s < 0.5
    ? _enterCurve.transform(s * 2)
    : 1 - _enterCurve.transform((s - 0.5) * 2);

class _TodoTaskRow extends StatefulWidget {
  const _TodoTaskRow({
    super.key,
    required this.item,
    required this.viewModel,
    required this.onEdit,
    required this.onDone,
    required this.onSubtask,
    required this.onAction,
    required this.onOpenSource,
    this.animated = true,
  });

  final TodoItem item;
  final TodoViewModel viewModel;
  final VoidCallback onEdit;
  final ValueChanged<bool> onDone;
  final ValueChanged<TodoSubtask> onSubtask;
  final ValueChanged<_TodoTaskAction> onAction;
  final VoidCallback onOpenSource;

  /// False in search results: completion and entry then only change the state.
  final bool animated;

  @override
  State<_TodoTaskRow> createState() => _TodoTaskRowState();
}

class _TodoTaskRowState extends State<_TodoTaskRow>
    with TickerProviderStateMixin {
  // Entry runs over _enterMs; idle at 1. Exit runs over _completeExitMs, or
  // _reducedExitMs when motion is reduced; idle at 0.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _enterMs),
    value: 1,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _completeExitMs),
  );
  bool _entryChecked = false;
  bool _completing = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entryChecked) return;
    if (!widget.animated || !widget.viewModel.isEntering(widget.item.id)) {
      _entryChecked = true;
      return;
    }
    // A task saved in the editor is listed while that route still covers this
    // screen; tickers are muted then, so the entry waits until the screen shows.
    if (!TickerMode.valuesOf(context).enabled) return;
    _entryChecked = true;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _enter.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _TodoTaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The write failed or the task was reopened: show the stored state again.
    if (_completing && _exit.isCompleted && !widget.item.done) {
      setState(() {
        _completing = false;
        _exit.reset();
      });
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _onCheck(bool value) {
    if (_completing) return;
    if (!widget.animated || !value || widget.item.done) {
      widget.onDone(value);
      return;
    }
    _completing = true;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _exit
      ..duration = Duration(
        milliseconds: _reduced ? _reducedExitMs : _completeExitMs,
      )
      ..forward(from: 0);
    widget.onDone(true);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        // Both controllers drive this card, so it rebuilds on every tick.
        animation: Listenable.merge([_enter, _exit]),
        builder: (context, _) => _buildCard(context),
      );

  Widget _buildCard(BuildContext context) {
    final l10n = UserStorage.l10n;
    final item = widget.item;
    final viewModel = widget.viewModel;
    final style = TodoPriorityStyle.of(item.priority);
    final textTheme = Theme.of(context).textTheme;
    final source = item.source;
    final nextOccurrence = item.done ? viewModel.nextOccurrenceFor(item) : null;
    final showSync = _shouldShowSyncStatus(viewModel.syncStatus);

    // Completion values. While completing they come from the exit controller
    // only, so a reload that marks the task done does not skip the animation.
    final completing = _completing;
    final reduced = completing && _reduced;
    final exitMs = _exit.duration!.inMilliseconds.toDouble();
    double seg(double start, double end) => reduced
        ? 1
        : ((_exit.value * exitMs - start) / (end - start)).clamp(0.0, 1.0);
    final staticDone = item.done ? 1.0 : 0.0;
    final fillT = completing ? _enterCurve.transform(seg(0, 180)) : staticDone;
    final tickT = completing ? _enterCurve.transform(seg(120, 340)) : staticDone;
    final strikeT =
        completing ? _enterCurve.transform(seg(200, 500)) : staticDone;
    final gradFade =
        completing ? _enterCurve.transform(seg(260, 780)) : staticDone;
    final pulse = completing && !reduced ? _pulse(seg(0, 320)) : 0.0;
    final collapse = completing && !reduced && widget.animated
        ? 1 - _enterCurve.transform(seg(760, 1080))
        : 1.0;
    final exitOpacity = reduced
        ? 1 - _exit.value
        : completing && widget.animated
            ? 1 - seg(760, 980)
            : 1.0;

    // Entry values: card growth, slide, scale and fade, then the light sweep.
    final enterMs = _enter.value * _enterMs;
    final enterT =
        _enterCurve.transform((enterMs / _cardEnterMs).clamp(0.0, 1.0));
    final enterFade = Curves.easeOut.transform((enterMs / _cardEnterMs).clamp(0.0, 1.0));
    final sweepT = ((enterMs - _sweepStartMs) / _sweepMs).clamp(0.0, 1.0);
    final sweeping = _enter.isAnimating && sweepT > 0 && sweepT < 1;

    // A task that was just completed shows its live state, not the stored one.
    final showDoneMeta = item.done && !completing;
    final dueState = viewModel.placementStateFor(item);
    final overdue = !showDoneMeta && dueState == TodoTaskState.overdue;
    final metaStyle = textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: AppColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final dueText = showDoneMeta
        ? _statusAndDate(item, viewModel, l10n, context)
        : _dueLabel(l10n, item, dueState, context);

    final meta = <Widget>[
      if (dueText != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (overdue) ...[
              Icon(
                Icons.alarm,
                size: 14,
                color: AppColors.primary,
                semanticLabel: l10n.todoStatusOverdue,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              dueText,
              key: ValueKey('todo_status_date_${item.id}'),
              style: metaStyle?.copyWith(
                color: overdue ? AppColors.primary : null,
              ),
            ),
          ],
        ),
      if (style.pillText case final pillText?)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 8),
          decoration: BoxDecoration(
            color: style.pillBackground,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _priorityLabel(l10n, item.priority),
            key: ValueKey('todo_priority_${item.id}'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: pillText,
            ),
          ),
        ),
      if (item.attachments.isNotEmpty)
        Row(
          key: ValueKey('todo_photos_${item.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.photo_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              l10n.todoPhotoCount(item.attachments.length),
              style: metaStyle,
            ),
          ],
        ),
      if (item.recurrence != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.repeat,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _repeatSummary(l10n, context, item.recurrence),
              key: ValueKey('todo_repeat_summary_${item.id}'),
              style: metaStyle,
            ),
          ],
        ),
    ];

    final card = Stack(
      children: [
        Container(
          key: ValueKey('todo_card_${item.id}'),
          decoration: style.cardDecoration(fade: gradFade),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('todo_${item.id}'),
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              onTap: widget.onEdit,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    checked: item.done,
                    button: true,
                    label: item.done ? l10n.todoReopenTask : l10n.todoMarkDone,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: InkWell(
                        key: ValueKey('todo_done_${item.id}'),
                        customBorder: const CircleBorder(),
                        onTap: () => _onCheck(!item.done),
                        child: Center(
                          child: TodoDoneCircle(
                            ring: style.ring,
                            fill: style.fill,
                            fillProgress: fillT,
                            tickProgress: tickT,
                            scale: 1 + 0.22 * pulse,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 14, 4, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Text(
                                item.text,
                                style: textTheme.bodyLarge?.copyWith(
                                  fontSize: 15,
                                  height: 1.3,
                                  color: Color.lerp(
                                    AppColors.textPrimary,
                                    AppColors.textTertiary,
                                    strikeT,
                                  ),
                                ),
                              ),
                              if (strikeT > 0)
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: strikeT,
                                      child: Container(
                                        height: 1.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: meta,
                            ),
                          ],
                          if (showSync)
                            Text(
                              viewModel.isItemSynced(item)
                                  ? l10n.todoSyncSynced
                                  : l10n.todoSyncSavedOnDevice,
                              key: ValueKey('todo_item_sync_label_${item.id}'),
                              style: textTheme.bodySmall?.copyWith(
                                color: viewModel.isItemSynced(item)
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                              ),
                            ),
                          if (item.sourceStale) ...[
                            const SizedBox(height: 4),
                            Text(
                              l10n.todoSourceChanged,
                              key: ValueKey('todo_source_stale_${item.id}'),
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                          if (nextOccurrence != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${l10n.todoSeriesActive} · '
                              '${l10n.todoSeriesNext(_formatScheduleDate(nextOccurrence, context))}',
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          for (final subtask in item.subtasks)
                            CheckboxListTile(
                              key: ValueKey(
                                  'todo_subtask_${item.id}_${subtask.id}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: subtask.done,
                              onChanged: (_) => widget.onSubtask(subtask),
                              title: Text(
                                subtask.text,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: subtask.done
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                  decoration: subtask.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          if (source != null)
                            InkWell(
                              key: ValueKey('todo_source_${item.id}'),
                              onTap: widget.onOpenSource,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 48),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.description_outlined,
                                        size: 16,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${l10n.todoOpenSource}: ${source.clock ?? ''} '
                                          '"${source.excerpt}"',
                                          style:
                                              textTheme.bodySmall?.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<_TodoTaskAction>(
                    key: ValueKey('todo_actions_${item.id}'),
                    tooltip: l10n.todoTaskActions,
                    onSelected: widget.onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _TodoTaskAction.edit,
                        child: Text(l10n.todoEdit),
                      ),
                      if (!item.done && calendarSlotFor(item.due) != null)
                        PopupMenuItem(
                          value: _TodoTaskAction.calendar,
                          child: Text(l10n.addToCalendar),
                        ),
                      PopupMenuItem(
                        value: _TodoTaskAction.delete,
                        child: Text(l10n.delete),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (sweeping)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                child: Align(
                  // Moves the band from fully left of the card to fully right.
                  alignment: Alignment(-4 + 8 * sweepT, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.6,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            style.fill.withValues(alpha: 0),
                            style.fill.withValues(alpha: 0.35),
                            style.fill.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: (enterT * collapse).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - enterT)),
            child: Transform.scale(
              scale: 0.97 + 0.03 * enterT,
              child: Opacity(
                opacity: (enterFade * exitOpacity).clamp(0.0, 1.0),
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Due date and time of a task that is not done, as shown on its card. Null when
/// the task has no date. Today shows only the time.
String? _dueLabel(
  AppLocalizations l10n,
  TodoItem item,
  TodoTaskState state,
  BuildContext context,
) {
  if (state == TodoTaskState.noDate) return null;
  final time = item.dueTime;
  if (state == TodoTaskState.today) {
    return time ?? l10n.todoStatusToday;
  }
  final date = _formatScheduleDate(item, context);
  return time == null ? date : '$date · $time';
}

/// Short summary of a repeat rule, shared by the list card and the editor.
String _repeatSummary(
  AppLocalizations l10n,
  BuildContext context,
  TodoRecurrence? recurrence,
) =>
    switch (recurrence?.frequency) {
      null => l10n.todoRepeatNone,
      TodoRepeatFrequency.daily => l10n.todoRepeatSummaryDaily,
      TodoRepeatFrequency.weekly when recurrence!.weekdays.length == 1 =>
        l10n.todoRepeatSummaryWeeklyOne(
          _weekdayName(context, recurrence.weekdays.first, short: false),
        ),
      TodoRepeatFrequency.weekly => l10n.todoRepeatSummaryWeekly([
          for (final day in ([...recurrence!.weekdays]..sort()))
            _weekdayName(context, day, short: true),
        ].join(', ')),
      TodoRepeatFrequency.monthly => l10n.todoRepeatSummaryMonthly,
    };

/// Weekday name for 1 (Monday) to 7 (Sunday).
String _weekdayName(BuildContext context, int weekday, {required bool short}) {
  final locale = Localizations.localeOf(context).toString();
  final date = DateTime.utc(2026, 1, 5 + weekday - 1);
  return short
      ? DateFormat.E(locale).format(date)
      : DateFormat.EEEE(locale).format(date);
}

String _shortWeekday(BuildContext context, int weekday) =>
    _weekdayName(context, weekday, short: true);

/// Label for an early alert in minutes; shared by the editor row and its page.
String _alertLabel(AppLocalizations l10n, int minutes) => switch (minutes) {
      0 => l10n.todoAlertNone,
      60 => l10n.todoAlertOneHourBefore,
      1440 => l10n.todoAlertOneDayBefore,
      _ when minutes > 60 && minutes % 60 == 0 =>
        l10n.todoAlertHoursBefore(minutes ~/ 60),
      _ => l10n.todoShortcutsAlertBefore(minutes),
    };

String _statusAndDate(
  TodoItem item,
  TodoViewModel viewModel,
  AppLocalizations l10n,
  BuildContext context,
) {
  final state = viewModel.stateFor(item);
  final label = switch (state) {
    TodoTaskState.noDate => l10n.todoStatusNoDate,
    TodoTaskState.today => l10n.todoStatusToday,
    TodoTaskState.upcoming => l10n.todoStatusUpcoming,
    TodoTaskState.overdue => l10n.todoStatusOverdue,
    TodoTaskState.completed => l10n.todoStatusCompleted,
  };
  DateTime? date;
  if (item.done && item.doneAt != null) {
    final instant = DateTime.tryParse(item.doneAt!);
    if (instant != null) {
      date = TodoScheduleCalculator.dateTimeInTimeZone(instant, item.timeZone);
    }
  }
  date ??= DateTime.tryParse(item.dueDate ?? '');
  if (item.done) date ??= DateTime.tryParse(item.createdAt);
  final dateLabel = date == null
      ? null
      : DateFormat.yMMMd(Localizations.localeOf(context).toString())
          .format(date);
  if (dateLabel == null) return label;
  final time = item.done ? null : item.dueTime;
  return '$label · $dateLabel${time == null ? '' : ' · $time'}';
}

String _formatScheduleDate(TodoItem item, BuildContext context) {
  final date = DateTime.tryParse(item.dueDate ?? '');
  if (date == null) return item.due;
  return DateFormat.yMMMd(Localizations.localeOf(context).toString())
      .format(date);
}

String _priorityLabel(AppLocalizations l10n, TodoPriority priority) =>
    switch (priority) {
      TodoPriority.low => l10n.todoPriorityLow,
      TodoPriority.normal => l10n.todoPriorityNormal,
      TodoPriority.high => l10n.todoPriorityHigh,
      TodoPriority.urgent => l10n.todoPriorityUrgent,
    };

/// Colour never stands alone: every use also shows the priority label.
Color _priorityColor(TodoPriority priority) =>
    TodoPriorityStyle.of(priority).color;

enum _EditorPanel { date, time, repeat }

Widget _divider() => const Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      color: AppColors.divider,
    );

TextStyle? _valueStyle(BuildContext context, {required bool muted}) =>
    Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: muted ? AppColors.textSecondary : AppColors.textPrimary,
        );

InputDecoration _plainInput({
  String? hintText,
  String? labelText,
  String? errorText,
}) =>
    InputDecoration(
      hintText: hintText,
      labelText: labelText,
      errorText: errorText,
      hintStyle: const TextStyle(color: AppColors.textTertiary),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    );

/// One line of the editor block: a outline icon, the value and an optional trailing control.
class _EditorLine extends StatelessWidget {
  const _EditorLine({
    super.key,
    required this.icon,
    required this.child,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final line = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 22, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 20),
            Expanded(child: child),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
    if (onTap == null) return line;
    return InkWell(onTap: onTap, child: line);
  }
}

class _TodoEditorPage extends StatefulWidget {
  const _TodoEditorPage({
    this.item,
    this.proposal,
    required this.settings,
    this.notice,
    this.photos,
  }) : assert(item == null || proposal == null);

  final TodoItem? item;
  final TodoProposal? proposal;
  final TodoShortcutSettings settings;
  final Widget? notice;
  final TodoViewModel? photos;

  @override
  State<_TodoEditorPage> createState() => _TodoEditorPageState();
}

class _TodoEditorPageState extends State<_TodoEditorPage> {
  late final _text = TextEditingController(
    text: widget.proposal?.title ?? widget.item?.text ?? '',
  );
  late final _due = TextEditingController(
    text: _initialDate(widget.item, widget.proposal),
  );
  late final _time = TextEditingController(
    text: _initialTime(widget.item, widget.proposal),
  );
  late int _alertMinutes =
      widget.item?.alertMinutes ?? widget.settings.defaultAlertMinutes;
  late final _newSubtask = TextEditingController();
  late final List<TodoSubtask> _subtasks = [
    ...?widget.item?.subtasks,
  ];
  // Stored `fs://` references, or local paths of photos picked in this session
  // that are copied into the workspace only when the task is saved.
  late final List<String> _photos = [...?widget.item?.attachments];
  final Map<String, Future<String?>> _photoPaths = {};
  bool _saving = false;
  late TodoPriority _priority = widget.item?.priority ?? TodoPriority.normal;
  late TodoRepeatFrequency? _frequency = widget.item?.recurrence?.frequency;
  late final Set<int> _weekdays =
      widget.item?.recurrence?.frequency == TodoRepeatFrequency.weekly
          ? widget.item!.recurrence!.weekdays.toSet()
          : {_anchorDate().weekday};
  late final Set<_EditorPanel> _open = {
    if (widget.item?.recurrence != null) _EditorPanel.repeat,
  };
  // Bumped only when the wheel must be redrawn from outside (chips, clear).
  int _wheelVersion = 0;
  String? _textError;
  String? _scheduleError;
  bool _confirmedNoDate = false;
  bool _confirmedNoTime = false;

  @override
  void dispose() {
    _text.dispose();
    _due.dispose();
    _time.dispose();
    _newSubtask.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final proposal = widget.proposal;
    final hasTime = _time.text.trim().isNotEmpty;
    final hasTitle = _text.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          proposal != null
              ? l10n.todoProposalReviewTitle
              : widget.item == null
                  ? l10n.todoNewTask
                  : l10n.todoEdit,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
        ),
      ),
      body: SingleChildScrollView(
        key: const ValueKey('todo_editor_scroll'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            _editorBlock(context, l10n, hasTime),
            if (proposal?.dateState == TodoProposalDateState.ambiguous &&
                !_hasValidDate) ...[
              const SizedBox(height: 8),
              Text(l10n.todoProposalDateUnclear),
              CheckboxListTile(
                key: const ValueKey('todo_proposal_no_date'),
                contentPadding: EdgeInsets.zero,
                value: _confirmedNoDate,
                title: Text(l10n.todoProposalUseNoDate),
                onChanged: (value) => setState(() {
                  _confirmedNoDate = value ?? false;
                  if (_confirmedNoDate) {
                    _due.clear();
                    _time.clear();
                    _confirmedNoTime = true;
                  }
                  _scheduleError = null;
                }),
              ),
            ],
            if (proposal?.timeState == TodoProposalTimeState.ambiguous &&
                !hasTime) ...[
              const SizedBox(height: 8),
              Text(l10n.todoProposalTimeUnclear),
              CheckboxListTile(
                key: const ValueKey('todo_proposal_no_time'),
                contentPadding: EdgeInsets.zero,
                value: _confirmedNoTime,
                title: Text(l10n.todoProposalUseNoTime),
                onChanged: (value) => setState(() {
                  _confirmedNoTime = value ?? false;
                  _scheduleError = null;
                }),
              ),
            ],
            if (_scheduleError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _scheduleError!,
                  key: const ValueKey('todo_schedule_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!hasTime)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.todoNoTime,
                  key: const ValueKey('todo_no_time'),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
            if (widget.notice != null) ...[
              const SizedBox(height: 12),
              widget.notice!,
            ],
          ],
        ),
      ),
      bottomNavigationBar: _bottomPill(context, l10n, hasTitle),
    );
  }

  Widget _editorBlock(
    BuildContext context,
    AppLocalizations l10n,
    bool hasTime,
  ) {
    final hasDate = _due.text.trim().isNotEmpty;
    final hasTitle = _text.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleBlock(context, l10n, hasTitle),
          _divider(),
          _EditorLine(
            key: const ValueKey('todo_date_row'),
            icon: Icons.calendar_today_outlined,
            onTap: () => _togglePanel(_EditorPanel.date),
            trailing: hasDate
                ? _removeButton(
                    const ValueKey('todo_clear_date'),
                    l10n.todoClearDate,
                    _clearDate,
                  )
                : null,
            child: Text(
              _dateLabel(context, l10n),
              style: _valueStyle(context, muted: !hasDate),
            ),
          ),
          if (_open.contains(_EditorPanel.date)) _datePanel(context, l10n),
          _divider(),
          _EditorLine(
            key: const ValueKey('todo_time_row'),
            icon: Icons.schedule_outlined,
            onTap: () => _togglePanel(_EditorPanel.time),
            trailing: hasTime
                ? _removeButton(
                    const ValueKey('todo_clear_time'),
                    l10n.todoClearTime,
                    _clearTime,
                  )
                : null,
            child: Text(
              _timeLabel(context, l10n),
              style: _valueStyle(context, muted: !hasTime),
            ),
          ),
          if (_open.contains(_EditorPanel.time)) _timePanel(context, l10n),
          if (hasTime) ...[
            _divider(),
            _EditorLine(
              key: const ValueKey('todo_alert_row'),
              icon: Icons.notifications_active_outlined,
              onTap: _openAlertPage,
              child: Text(
                _alertLabel(l10n, _alertMinutes),
                style: _valueStyle(context, muted: _alertMinutes == 0),
              ),
            ),
          ],
          _divider(),
          _EditorLine(
            key: const ValueKey('todo_repeat_row'),
            icon: Icons.repeat,
            onTap: () => _togglePanel(_EditorPanel.repeat),
            child: Text(
              _repeatSummary(l10n, context, _recurrence()),
              style: _valueStyle(context, muted: _frequency == null),
            ),
          ),
          if (_open.contains(_EditorPanel.repeat)) _repeatPanel(context, l10n),
          _divider(),
          _EditorLine(
            icon: Icons.flag_outlined,
            child: DropdownButtonFormField<TodoPriority>(
              key: const ValueKey('todo_priority_editor'),
              initialValue: _priority,
              isExpanded: true,
              decoration: _plainInput(labelText: l10n.todoPriorityLabel),
              items: [
                for (final priority in TodoPriority.values)
                  DropdownMenuItem(
                    value: priority,
                    child: Text(
                      _priorityLabel(l10n, priority),
                      style: TextStyle(color: _priorityColor(priority)),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _priority = value);
              },
            ),
          ),
          _divider(),
          _subtaskSection(context, l10n),
        ],
      ),
    );
  }

  /// The task text: a larger multi-line field, then the photo buttons and thumbnails.
  Widget _titleBlock(
    BuildContext context,
    AppLocalizations l10n,
    bool hasTitle,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.radio_button_unchecked,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: TextField(
                  key: const ValueKey('todo_text'),
                  controller: _text,
                  minLines: 2,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                  ),
                  decoration: _plainInput(
                    hintText: l10n.todoTextHint,
                    errorText: _textError,
                  ),
                  onChanged: (_) => setState(() => _textError = null),
                ),
              ),
              if (hasTitle)
                IconButton(
                  key: const ValueKey('todo_text_clear'),
                  tooltip: l10n.todoClearText,
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: _clearText,
                ),
            ],
          ),
          if (widget.photos != null)
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('todo_photo_gallery'),
                    tooltip: l10n.todoPhotoFromGallery,
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                  ),
                  IconButton(
                    key: const ValueKey('todo_photo_camera'),
                    tooltip: l10n.todoPhotoFromCamera,
                    icon: const Icon(
                      Icons.photo_camera_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => _pickPhoto(ImageSource.camera),
                  ),
                ],
              ),
            ),
          if (_photos.isNotEmpty) _photoStrip(l10n),
        ],
      ),
    );
  }

  Widget _photoStrip(AppLocalizations l10n) => SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // Top room for the remove buttons that overhang each thumbnail.
          padding: const EdgeInsets.fromLTRB(56, 12, 16, 0),
          itemCount: _photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => _photoThumb(l10n, index),
        ),
      );

  Widget _photoThumb(AppLocalizations l10n, int index) {
    final photo = _photos[index];
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Semantics(
              button: true,
              label: l10n.todoPhotoOpen,
              child: InkWell(
                key: ValueKey('todo_photo_$index'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openPhoto(photo),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FutureBuilder<String?>(
                    future: _localPath(photo),
                    builder: (context, snapshot) {
                      final path = snapshot.data;
                      if (path == null) {
                        return const ColoredBox(
                          color: AppColors.iconBgLight,
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.textSecondary,
                          ),
                        );
                      }
                      return LocalImage(
                        url: path,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -12,
            right: -12,
            child: IconButton(
              key: ValueKey('todo_photo_remove_$index'),
              tooltip: l10n.todoPhotoRemove,
              icon: const Icon(
                Icons.cancel,
                size: 20,
                color: AppColors.textPrimary,
              ),
              onPressed: () => setState(() => _photos.removeAt(index)),
            ),
          ),
        ],
      ),
    );
  }

  /// Local file of a photo: stored references are resolved once and cached.
  Future<String?> _localPath(String photo) => _photoPaths.putIfAbsent(
        photo,
        () => _isStoredPhoto(photo)
            ? (widget.photos?.photoPath(photo) ?? Future.value(null))
            : Future.value(photo),
      );

  Future<void> _openPhoto(String photo) async {
    final path = await _localPath(photo);
    if (path == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _TodoPhotoViewer(path: path)),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final l10n = UserStorage.l10n;
    final photos = widget.photos;
    if (photos == null) return;
    String? path;
    try {
      path = await photos.pickPhoto(source);
    } catch (_) {
      if (mounted) ToastHelper.showError(context, l10n.todoPhotoSaveFailed);
      return;
    }
    if (path == null || !mounted) return;
    final picked = path;
    setState(() => _photos.add(picked));
  }

  static bool _isStoredPhoto(String photo) => photo.startsWith('fs://');

  /// Copies the photos picked in this session into the workspace. References
  /// already stored are kept; the result follows the order shown.
  Future<List<String>> _storedPhotos() async {
    final pending = [
      for (final photo in _photos)
        if (!_isStoredPhoto(photo)) photo,
    ];
    if (pending.isEmpty) return List<String>.of(_photos);
    final stored = await widget.photos!.storePhotos(pending);
    var next = 0;
    return [
      for (final photo in _photos)
        if (_isStoredPhoto(photo)) photo else stored[next++],
    ];
  }

  Widget _removeButton(Key key, String tooltip, VoidCallback onPressed) =>
      IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: const Icon(Icons.remove_circle, color: AppColors.danger),
      );

  Widget _datePanel(BuildContext context, AppLocalizations l10n) {
    final anchor = _anchorDate();
    final initial = DateTime(anchor.year, anchor.month, anchor.day);
    final base = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: AppColors.onPrimary,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: CalendarDatePicker(
            // Rebuilt when the date changes so the shown month follows it.
            key: ValueKey('todo_calendar_${_due.text}'),
            initialDate: initial,
            firstDate: DateTime(initial.year - 5, 1, 1),
            lastDate: DateTime(initial.year + 10, 12, 31),
            onDateChanged: (picked) => setState(() {
              _due.text = _formatDate(picked);
              _scheduleError = null;
              _confirmedNoDate = false;
            }),
          ),
        ),
        _horizontalChips([
          for (final shortcut in TodoDateShortcut.values)
            if (widget.settings.enabledDateShortcuts.contains(shortcut))
              ActionChip(
                key: ValueKey('todo_date_shortcut_${shortcut.name}'),
                label: Text(_dateShortcutLabel(shortcut, l10n)),
                onPressed: () => _applyDateShortcut(shortcut),
              ),
        ]),
      ],
    );
  }

  Widget _timePanel(BuildContext context, AppLocalizations l10n) {
    final parsed = _parsedTime() ?? const TimeOfDay(hour: 9, minute: 0);
    final now = DateTime.now();
    final shortcuts = widget.settings.timeShortcutsMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 180,
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.dark,
              primaryColor: AppColors.primary,
              textTheme: CupertinoTextThemeData(
                dateTimePickerTextStyle: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                ),
              ),
            ),
            child: CupertinoDatePicker(
              key: ValueKey('todo_time_wheel_$_wheelVersion'),
              mode: CupertinoDatePickerMode.time,
              use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
              minuteInterval: parsed.minute % 5 == 0 ? 5 : 1,
              initialDateTime: DateTime(
                now.year,
                now.month,
                now.day,
                parsed.hour,
                parsed.minute,
              ),
              onDateTimeChanged: _onWheelChanged,
            ),
          ),
        ),
        _horizontalChips([
          for (var index = 0; index < shortcuts.length; index++)
            ActionChip(
              key: ValueKey('todo_time_shortcut_$index'),
              label: Text(_formatTime(context, shortcuts[index])),
              onPressed: () => _applyTimeShortcut(shortcuts[index]),
            ),
          ActionChip(
            key: const ValueKey('todo_time_in_1h'),
            label: Text(l10n.todoInOneHour),
            onPressed: () => _applyInHours(1),
          ),
          ActionChip(
            key: const ValueKey('todo_time_in_2h'),
            label: Text(l10n.todoInTwoHours),
            onPressed: () => _applyInHours(2),
          ),
        ]),
      ],
    );
  }

  Widget _horizontalChips(List<Widget> chips) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          children: [
            for (final chip in chips)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: chip,
              ),
          ],
        ),
      );

  Widget _repeatPanel(BuildContext context, AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _repeatChip(null, l10n.todoRepeatNone),
                _repeatChip(TodoRepeatFrequency.daily, l10n.todoRepeatDaily),
                _repeatChip(
                  TodoRepeatFrequency.weekly,
                  l10n.todoRepeatWeekly,
                ),
                _repeatChip(
                  TodoRepeatFrequency.monthly,
                  l10n.todoRepeatMonthly,
                ),
              ],
            ),
            if (_frequency == TodoRepeatFrequency.weekly) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    FilterChip(
                      key: ValueKey('todo_repeat_weekday_$weekday'),
                      label: Text(_shortWeekday(context, weekday)),
                      selected: _weekdays.contains(weekday),
                      onSelected: (selected) => _toggleWeekday(
                        weekday,
                        selected,
                      ),
                    ),
                ],
              ),
            ],
            if (_frequency == TodoRepeatFrequency.monthly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.todoMonthlyDayRule,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _subtaskSection(BuildContext context, AppLocalizations l10n) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 12, 16, 0),
            child: Text(
              l10n.todoSubtasksTitle,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          _EditorLine(
            icon: Icons.checklist_outlined,
            trailing: IconButton(
              key: const ValueKey('todo_subtask_add'),
              tooltip: l10n.todoSubtaskAdd,
              onPressed: _addSubtask,
              icon: const Icon(Icons.add, color: AppColors.primary),
            ),
            child: TextField(
              key: const ValueKey('todo_subtask_new'),
              controller: _newSubtask,
              decoration: _plainInput(hintText: l10n.todoSubtaskHint),
              onSubmitted: (_) => _addSubtask(),
            ),
          ),
          for (var index = 0; index < _subtasks.length; index++)
            ListTile(
              key: ValueKey('todo_subtask_editor_${_subtasks[index].id}'),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 56, right: 8),
              leading: Checkbox(
                value: _subtasks[index].done,
                onChanged: (value) => setState(() {
                  _subtasks[index] = _subtasks[index].copyWith(
                    done: value ?? false,
                  );
                }),
              ),
              title: Text(_subtasks[index].text),
              trailing: IconButton(
                tooltip: l10n.todoSubtaskRemove,
                onPressed: () => setState(() => _subtasks.removeAt(index)),
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      );

  Widget _bottomPill(
    BuildContext context,
    AppLocalizations l10n,
    bool hasTitle,
  ) =>
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Material(
              color: AppColors.surface,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: const ValueKey('todo_dialog_cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: AppColors.divider,
                  ),
                  TextButton(
                    key: const ValueKey('todo_dialog_save'),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          hasTitle ? AppColors.primary : AppColors.textTertiary,
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _save,
                    child: Text(widget.proposal == null
                        ? l10n.todoSave
                        : l10n.todoProposalConfirm),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _save() async {
    if (_saving) return;
    final l10n = UserStorage.l10n;
    if (_text.text.trim().isEmpty) {
      setState(() => _textError = l10n.todoTextRequired);
      return;
    }
    if (widget.proposal?.dateState == TodoProposalDateState.ambiguous &&
        !_hasValidDate &&
        !_confirmedNoDate) {
      setState(() => _scheduleError = l10n.todoProposalDateMustResolve);
      return;
    }
    if (widget.proposal?.timeState == TodoProposalTimeState.ambiguous &&
        _time.text.trim().isEmpty &&
        !_confirmedNoTime) {
      setState(() => _scheduleError = l10n.todoProposalTimeMustResolve);
      return;
    }
    final TodoRecurrence? recurrence = _recurrence();
    if (_time.text.trim().isNotEmpty && !_validTime) {
      setState(() => _scheduleError = l10n.todoTimeInvalid);
      return;
    }
    if (_time.text.trim().isNotEmpty && !_hasValidDate) {
      setState(() => _scheduleError = l10n.todoTimeRequiresDate);
      return;
    }
    if (recurrence != null && !_hasValidDate) {
      setState(() => _scheduleError = l10n.todoRepeatRequiresDate);
      return;
    }
    _saving = true;
    List<String> photos;
    try {
      photos = await _storedPhotos();
    } catch (_) {
      _saving = false;
      if (mounted) ToastHelper.showError(context, l10n.todoPhotoSaveFailed);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop<TodoDraft>((
      text: _text.text,
      due: _combinedDue,
      recurrence: recurrence,
      priority: _priority,
      subtasks: List<TodoSubtask>.unmodifiable(_subtasks),
      alertMinutes: _alertMinutes,
      attachments: List<String>.unmodifiable(photos),
    ));
  }

  Future<void> _openAlertPage() async {
    final minutes = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => _TodoAlertPage(minutes: _alertMinutes),
      ),
    );
    if (minutes == null || !mounted) return;
    setState(() => _alertMinutes = minutes);
  }

  void _togglePanel(_EditorPanel panel) => setState(() {
        if (!_open.remove(panel)) _open.add(panel);
      });

  void _clearText() => setState(() => _text.clear());

  void _clearDate() => setState(() {
        _due.clear();
        _time.clear();
        _frequency = null;
        _open.removeAll({
          _EditorPanel.date,
          _EditorPanel.time,
          _EditorPanel.repeat,
        });
        _confirmedNoDate = false;
        _confirmedNoTime = false;
        _scheduleError = null;
      });

  void _clearTime() => setState(() {
        _time.clear();
        _open.remove(_EditorPanel.time);
        _confirmedNoTime = false;
        _scheduleError = null;
      });

  void _onWheelChanged(DateTime value) {
    if (!_hasValidDate && _due.text.trim().isEmpty) {
      _due.text = _formatDate(_anchorDate());
    }
    _time.text = _formatClock(value);
    setState(() {
      _scheduleError = null;
      _confirmedNoTime = false;
    });
  }

  void _addSubtask() {
    final text = _newSubtask.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(TodoSubtask(id: const Uuid().v4(), text: text));
      _newSubtask.clear();
    });
  }

  Widget _repeatChip(TodoRepeatFrequency? frequency, String label) =>
      ChoiceChip(
        key: ValueKey('todo_repeat_${frequency?.name ?? 'none'}'),
        label: Text(label),
        selected: _frequency == frequency,
        onSelected: (_) {
          if (frequency != null && _due.text.trim().isEmpty) {
            _applyDateShortcut(TodoDateShortcut.today);
          }
          setState(() => _frequency = frequency);
        },
      );

  String _dateShortcutLabel(TodoDateShortcut shortcut, AppLocalizations l10n) =>
      switch (shortcut) {
        TodoDateShortcut.today => l10n.todoShortcutToday,
        TodoDateShortcut.tomorrow => l10n.todoShortcutTomorrow,
        TodoDateShortcut.inThreeDays => l10n.todoShortcutInThreeDays,
        TodoDateShortcut.nextMonday => l10n.todoShortcutNextMonday,
      };

  String _formatTime(BuildContext context, int minutes) => TimeOfDay(
        hour: minutes ~/ 60,
        minute: minutes % 60,
      ).format(context);

  String _dateLabel(BuildContext context, AppLocalizations l10n) {
    final text = _due.text.trim();
    if (text.isEmpty) return l10n.todoEditorDate;
    final explicit = parseExplicitDue(text);
    if (explicit == null) return text;
    final now = DateTime.now();
    final date = explicit.date;
    if (_sameDay(
        date,
        TodoScheduleCalculator.dateForShortcut(
          TodoDateShortcut.today,
          now: now,
        ))) {
      return l10n.todoShortcutToday;
    }
    if (_sameDay(
        date,
        TodoScheduleCalculator.dateForShortcut(
          TodoDateShortcut.tomorrow,
          now: now,
        ))) {
      return l10n.todoShortcutTomorrow;
    }
    return DateFormat.yMMMEd(Localizations.localeOf(context).toString())
        .format(date);
  }

  String _timeLabel(BuildContext context, AppLocalizations l10n) {
    final text = _time.text.trim();
    if (text.isEmpty) return l10n.todoEditorTime;
    final time = _parsedTime();
    return time == null ? text : time.format(context);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _anchorDate() {
    final explicit = parseExplicitDue(_due.text);
    if (explicit != null) {
      return DateTime.utc(
        explicit.date.year,
        explicit.date.month,
        explicit.date.day,
      );
    }
    return TodoScheduleCalculator.dateForShortcut(
      TodoDateShortcut.today,
      now: DateTime.now(),
    );
  }

  bool get _hasValidDate {
    return parseExplicitDue(_due.text) != null;
  }

  TimeOfDay? _parsedTime() {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour >= 24 || minute >= 60) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  bool get _validTime => _parsedTime() != null;

  String get _combinedDue => _time.text.trim().isEmpty
      ? _due.text
      : '${_due.text.trim()} ${_time.text.trim()}';

  String _initialDate(TodoItem? item, TodoProposal? proposal) {
    if (proposal?.dateState == TodoProposalDateState.explicit) {
      return proposal!.dueDate!;
    }
    if (item == null || item.due == reportDueUnknown) return '';
    if (item.dueDate != null) return item.dueDate!;
    final explicit = parseExplicitDue(item.due);
    return explicit == null ? item.due : _formatDate(explicit.date);
  }

  String _initialTime(TodoItem? item, TodoProposal? proposal) {
    if (proposal?.timeState == TodoProposalTimeState.explicit) {
      return proposal!.dueTime!;
    }
    if (item == null) return '';
    if (item.dueTime != null) return item.dueTime!;
    final explicit = parseExplicitDue(item.due);
    return explicit?.hasTime == true ? _formatClock(explicit!.date) : '';
  }

  void _applyDateShortcut(TodoDateShortcut shortcut) {
    final date = TodoScheduleCalculator.dateForShortcut(
      shortcut,
      now: DateTime.now(),
    );
    setState(() {
      _due.text = _formatDate(date);
      _scheduleError = null;
      _confirmedNoDate = false;
    });
  }

  void _applyTimeShortcut(int minutes) {
    if (!_hasValidDate && _due.text.trim().isEmpty) {
      _due.text = _formatDate(_anchorDate());
    }
    _time.text = '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
    setState(() {
      _wheelVersion++;
      _scheduleError = null;
      _confirmedNoTime = false;
    });
  }

  /// Sets the due to the current time plus [hours], rounded up to a 5 minute step.
  void _applyInHours(int hours) {
    final target = DateTime.now().add(Duration(hours: hours));
    final rounded = DateTime(
      target.year,
      target.month,
      target.day,
      target.hour,
      target.minute,
    ).add(Duration(minutes: (5 - target.minute % 5) % 5));
    setState(() {
      _due.text = _formatDate(rounded);
      _time.text = _formatClock(rounded);
      _wheelVersion++;
      _scheduleError = null;
      _confirmedNoDate = false;
      _confirmedNoTime = false;
    });
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _formatClock(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  void _toggleWeekday(int weekday, bool selected) {
    setState(() {
      if (selected) {
        _weekdays.add(weekday);
      } else if (_weekdays.length > 1) {
        _weekdays.remove(weekday);
      }
    });
  }

  TodoRecurrence? _recurrence() => switch (_frequency) {
        null => null,
        TodoRepeatFrequency.daily => TodoRecurrence.daily(),
        TodoRepeatFrequency.weekly => TodoRecurrence.weekly(_weekdays),
        TodoRepeatFrequency.monthly =>
          TodoRecurrence.monthly(_anchorDate().day),
      };
}

/// Full-screen view of one task photo, with pinch zoom.
class _TodoPhotoViewer extends StatelessWidget {
  const _TodoPhotoViewer({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: PhotoView(
          imageProvider: LocalImage.provider(path),
          minScale: PhotoViewComputedScale.contained,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
        ),
      );
}

/// Full-page early alert picker; pops the chosen minutes, or null on back.
class _TodoAlertPage extends StatefulWidget {
  const _TodoAlertPage({required this.minutes});

  final int minutes;

  @override
  State<_TodoAlertPage> createState() => _TodoAlertPageState();
}

class _TodoAlertPageState extends State<_TodoAlertPage> {
  static const _presets = [0, 10, 15, 60, 1440];

  late bool _custom = !_presets.contains(widget.minutes);
  late bool _hours = widget.minutes >= 60;
  late int _amount = _hours
      ? _clampInt((widget.minutes / 60).round(), 1, 23)
      : _clampInt(widget.minutes, 1, 59);
  late final _amountWheel =
      FixedExtentScrollController(initialItem: _amount - 1);
  late final _unitWheel =
      FixedExtentScrollController(initialItem: _hours ? 1 : 0);

  @override
  void dispose() {
    _amountWheel.dispose();
    _unitWheel.dispose();
    super.dispose();
  }

  int get _value => _hours ? _amount * 60 : _amount;

  void _selectCustom() {
    if (_custom) return;
    setState(() {
      _custom = true;
      _hours = false;
      _amount = 30;
    });
    _alignWheel(_amountWheel, _amount - 1);
    _alignWheel(_unitWheel, 0);
  }

  void _setUnit(bool hours) {
    if (_hours == hours) return;
    setState(() {
      _hours = hours;
      _amount = hours ? 1 : 30;
    });
    _alignWheel(_amountWheel, _amount - 1);
  }

  /// Wheels are only attached while they are on screen, so jump after the frame.
  void _alignWheel(FixedExtentScrollController wheel, int index) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _custom && wheel.hasClients) {
          wheel.jumpToItem(index);
        }
      });

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final amountMax = _hours ? 23 : 59;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l10n.todoAlertPageTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
        ),
        actions: [
          if (_custom)
            TextButton(
              key: const ValueKey('todo_alert_done'),
              onPressed: () => Navigator.of(context).pop<int>(_value),
              child: Text(l10n.todoAlertDone),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                for (final minutes in _presets) ...[
                  _AlertOption(
                    key: ValueKey('todo_alert_option_$minutes'),
                    label: _alertLabel(l10n, minutes),
                    selected: !_custom && widget.minutes == minutes,
                    onTap: () => Navigator.of(context).pop<int>(minutes),
                  ),
                  _divider(),
                ],
                _AlertOption(
                  key: const ValueKey('todo_alert_option_custom'),
                  label: l10n.todoAlertCustom,
                  subtitle: _custom ? _alertLabel(l10n, _value) : null,
                  selected: _custom,
                  onTap: _selectCustom,
                ),
                if (_custom)
                  SizedBox(
                    height: 200,
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoPicker(
                            key: const ValueKey('todo_alert_amount'),
                            scrollController: _amountWheel,
                            itemExtent: 44,
                            selectionOverlay:
                                const CupertinoPickerDefaultSelectionOverlay(
                              background: CupertinoColors.transparent,
                            ),
                            onSelectedItemChanged: (index) =>
                                setState(() => _amount = index + 1),
                            children: [
                              for (var amount = 1;
                                  amount <= amountMax;
                                  amount++)
                                Center(
                                  child: Text(
                                    '$amount',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: CupertinoPicker(
                            key: const ValueKey('todo_alert_unit'),
                            scrollController: _unitWheel,
                            itemExtent: 44,
                            selectionOverlay:
                                const CupertinoPickerDefaultSelectionOverlay(
                              background: CupertinoColors.transparent,
                            ),
                            onSelectedItemChanged: (index) =>
                                _setUnit(index == 1),
                            children: [
                              Center(
                                child: Text(
                                  l10n.todoAlertUnitMinutes,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                              Center(
                                child: Text(
                                  l10n.todoAlertUnitHours,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _clampInt(int value, int low, int high) =>
    value < low ? low : (value > high ? high : value);

class _AlertOption extends StatelessWidget {
  const _AlertOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: textTheme.bodyLarge?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
