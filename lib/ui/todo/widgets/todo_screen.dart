import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:uuid/uuid.dart';

typedef TodoDraft = ({
  String text,
  String due,
  TodoRecurrence? recurrence,
  TodoPriority priority,
  List<TodoSubtask> subtasks,
  int alertMinutes,
});

Future<TodoDraft?> showTodoEditorDialog({
  required BuildContext context,
  required TodoShortcutSettings settings,
  TodoItem? item,
  TodoProposal? proposal,
}) =>
    showDialog<TodoDraft>(
      context: context,
      builder: (_) => _TodoDialog(
        item: item,
        proposal: proposal,
        settings: settings,
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
      length: TodoListSection.values.length,
      vsync: this,
      initialIndex: widget.viewModel.section.index,
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

  void _onTabChanged() {
    final target = TodoListSection.values[_tabController.index];
    if (widget.viewModel.section != target) {
      widget.viewModel.selectSection(target);
    }
  }

  void _syncTabControllerFromViewModel() {
    if (!mounted) return;
    final targetIndex = widget.viewModel.section.index;
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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: l10n.todoTabToday),
            Tab(text: l10n.todoTabUpcoming),
            Tab(text: l10n.todoTabOverdue),
            Tab(text: l10n.todoTabCompleted),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('todo_open_search'),
            tooltip: l10n.todoSearchHint,
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          _TodoPriorityFilterButton(viewModel: widget.viewModel),
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
          if (viewModel.errorMessage != null && !viewModel.hasAny) {
            return _loadError(l10n, viewModel);
          }
          return Column(
            children: [
              if (_alarmPermissionBanner(l10n, viewModel) case final banner?)
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
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    for (final section in TodoListSection.values)
                      _sectionBody(viewModel, l10n, section),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

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
      TodoSyncBadgeState.savedOnDevice || TodoSyncBadgeState.localOnly =>
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
    final items = viewModel.itemsFor(section);
    if (items.isEmpty) {
      final hasFilter = viewModel.priorityFilter != null;
      final message = hasFilter
          ? l10n.todoFilterEmpty
          : switch (section) {
              TodoListSection.today => l10n.todoEmptyToday,
              TodoListSection.upcoming => l10n.todoEmptyUpcoming,
              TodoListSection.overdue => l10n.todoEmptyOverdue,
              TodoListSection.completed => l10n.todoEmptyCompleted,
            };
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
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
              ] else if (!viewModel.hasAny &&
                  section == TodoListSection.today) ...[
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
      children: [
        for (final item in dated) _taskRow(item, l10n, viewModel),
        if (undated.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Text(
              l10n.todoUndatedSection,
              key: const ValueKey('todo_undated_header'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          for (final item in undated) _taskRow(item, l10n, viewModel),
        ],
      ],
    );
  }

  Widget _taskRow(
    TodoItem item,
    AppLocalizations l10n,
    TodoViewModel viewModel,
  ) =>
      _TodoTaskRow(
        item: item,
        viewModel: viewModel,
        onEdit: () => _addOrEdit(item),
        onDone: (_) => viewModel.toggleDone(item),
        onSubtask: (subtask) => viewModel.toggleSubtask(item, subtask),
        onAction: (action) => _taskAction(item, action),
        onOpenSource: () => _openSource(item),
      );
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
              child: Text(_priorityLabel(l10n, priority)),
            ),
        ],
      ),
    );
  }
}

class _TodoSearchScreen extends StatefulWidget {
  const _TodoSearchScreen({
    super.key,
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

class _TodoTaskRow extends StatelessWidget {
  const _TodoTaskRow({
    required this.item,
    required this.viewModel,
    required this.onEdit,
    required this.onDone,
    required this.onSubtask,
    required this.onAction,
    required this.onOpenSource,
  });

  final TodoItem item;
  final TodoViewModel viewModel;
  final VoidCallback onEdit;
  final ValueChanged<bool> onDone;
  final ValueChanged<TodoSubtask> onSubtask;
  final ValueChanged<_TodoTaskAction> onAction;
  final VoidCallback onOpenSource;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final source = item.source;
    final textTheme = Theme.of(context).textTheme;
    final showSync = _shouldShowSyncStatus(viewModel.syncStatus);
    final nextOccurrence =
        item.done ? viewModel.nextOccurrenceFor(item) : null;
    return Column(
      key: ValueKey('todo_${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: MergeSemantics(
            child: Semantics(
              label: item.done ? l10n.todoReopenTask : l10n.todoMarkDone,
              child: Checkbox(
                key: ValueKey('todo_done_${item.id}'),
                value: item.done,
                onChanged: (value) => onDone(value ?? !item.done),
              ),
            ),
          ),
          title: Text(
            item.text,
            style: textTheme.bodyLarge?.copyWith(
              color:
                  item.done ? AppColors.textSecondary : AppColors.textPrimary,
              decoration: item.done ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _statusAndDate(item, viewModel, l10n, context),
                      key: ValueKey('todo_status_date_${item.id}'),
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (item.priority != TodoPriority.normal)
                      Text(
                        _priorityLabel(l10n, item.priority),
                        key: ValueKey('todo_priority_${item.id}'),
                        style: textTheme.bodySmall?.copyWith(
                          color: _priorityColor(item.priority),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                  ],
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
              ],
            ),
          ),
          onTap: onEdit,
          trailing: PopupMenuButton<_TodoTaskAction>(
            key: ValueKey('todo_actions_${item.id}'),
            tooltip: l10n.todoTaskActions,
            onSelected: onAction,
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
        ),
        if (source != null)
          InkWell(
            key: ValueKey('todo_source_${item.id}'),
            onTap: onOpenSource,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(56, 8, 16, 8),
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
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (final subtask in item.subtasks)
          CheckboxListTile(
            key: ValueKey('todo_subtask_${item.id}_${subtask.id}'),
            contentPadding: const EdgeInsets.only(left: 56, right: 16),
            controlAffinity: ListTileControlAffinity.leading,
            value: subtask.done,
            onChanged: (_) => onSubtask(subtask),
            title: Text(
              subtask.text,
              style: textTheme.bodyMedium?.copyWith(
                color: subtask.done
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                decoration: subtask.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

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

Color _priorityColor(TodoPriority priority) => switch (priority) {
      TodoPriority.low || TodoPriority.normal => AppColors.textSecondary,
      TodoPriority.high => AppColors.primary,
      TodoPriority.urgent => AppColors.danger,
    };

class _TodoDialog extends StatefulWidget {
  const _TodoDialog({this.item, this.proposal, required this.settings})
      : assert(item == null || proposal == null);

  final TodoItem? item;
  final TodoProposal? proposal;
  final TodoShortcutSettings settings;

  @override
  State<_TodoDialog> createState() => _TodoDialogState();
}

class _TodoDialogState extends State<_TodoDialog> {
  late final _text = TextEditingController(
    text: widget.proposal?.title ?? widget.item?.text ?? '',
  );
  late final _due = TextEditingController(
    text: _initialDate(widget.item, widget.proposal),
  );
  late final _time = TextEditingController(
    text: _initialTime(widget.item, widget.proposal),
  );
  late final _alertMinutes = TextEditingController(
    text: (widget.item?.alertMinutes ?? widget.settings.defaultAlertMinutes)
        .toString(),
  );
  late final _newSubtask = TextEditingController();
  late final List<TodoSubtask> _subtasks = [
    ...?widget.item?.subtasks,
  ];
  late TodoPriority _priority = widget.item?.priority ?? TodoPriority.normal;
  late TodoRepeatFrequency? _frequency = widget.item?.recurrence?.frequency;
  late final Set<int> _weekdays =
      widget.item?.recurrence?.frequency == TodoRepeatFrequency.weekly
          ? widget.item!.recurrence!.weekdays.toSet()
          : {_anchorDate().weekday};
  String? _textError;
  String? _scheduleError;
  String? _alertError;
  bool _confirmedNoDate = false;
  bool _confirmedNoTime = false;

  @override
  void dispose() {
    _text.dispose();
    _due.dispose();
    _time.dispose();
    _alertMinutes.dispose();
    _newSubtask.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final hasTime = _time.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      title: Text(widget.proposal != null
          ? l10n.todoProposalReviewTitle
          : widget.item == null
              ? l10n.todoAdd
              : l10n.todoEdit),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('todo_text'),
                controller: _text,
                decoration: InputDecoration(
                  hintText: l10n.todoTextHint,
                  errorText: _textError,
                ),
                onChanged: (_) {
                  if (_textError != null) {
                    setState(() => _textError = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TodoPriority>(
                key: const ValueKey('todo_priority_editor'),
                value: _priority,
                decoration: InputDecoration(labelText: l10n.todoPriorityLabel),
                items: [
                  for (final priority in TodoPriority.values)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(_priorityLabel(l10n, priority)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('todo_due'),
                controller: _due,
                decoration: InputDecoration(
                  labelText: l10n.todoDueHint,
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: IconButton(
                    key: const ValueKey('todo_pick_date'),
                    tooltip: l10n.todoPickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: _pickDate,
                  ),
                ),
                onChanged: _dueChanged,
              ),
              TextField(
                key: const ValueKey('todo_time'),
                controller: _time,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: l10n.todoTimeLabel,
                  hintText: l10n.todoTimeHint,
                  suffixIcon: IconButton(
                    key: const ValueKey('todo_pick_time'),
                    tooltip: l10n.todoPickTime,
                    icon: const Icon(Icons.schedule_outlined),
                    onPressed: _pickTime,
                  ),
                ),
                onChanged: (_) => setState(() {
                  _scheduleError = null;
                  _confirmedNoTime = false;
                }),
              ),
              TextField(
                key: const ValueKey('todo_alert_minutes'),
                controller: _alertMinutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.todoAlertMinutesLabel,
                  errorText: _alertError,
                ),
                onChanged: (_) => setState(() => _alertError = null),
              ),
              if (widget.proposal?.dateState ==
                      TodoProposalDateState.ambiguous &&
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
              if (widget.proposal?.timeState ==
                      TodoProposalTimeState.ambiguous &&
                  _time.text.trim().isEmpty) ...[
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
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
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
              if (widget.settings.enabledDateShortcuts.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(l10n.todoShortcutsDaysTitle),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final shortcut in TodoDateShortcut.values)
                      if (widget.settings.enabledDateShortcuts
                          .contains(shortcut))
                        ActionChip(
                          key: ValueKey('todo_date_shortcut_${shortcut.name}'),
                          label: Text(_dateShortcutLabel(shortcut, l10n)),
                          onPressed: () => _applyDateShortcut(shortcut),
                        ),
                  ],
                ),
              ],
              if (widget.settings.timeShortcutsMinutes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(l10n.todoShortcutsTimesTitle),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var index = 0;
                        index < widget.settings.timeShortcutsMinutes.length;
                        index++)
                      ActionChip(
                        key: ValueKey('todo_time_shortcut_$index'),
                        label: Text(_formatTime(
                          context,
                          widget.settings.timeShortcutsMinutes[index],
                        )),
                        onPressed: () => _applyTimeShortcut(
                          widget.settings.timeShortcutsMinutes[index],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(l10n.todoRepeatTitle),
              Wrap(
                spacing: 6,
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
                        label: Text(_weekdayLabel(context, weekday)),
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
              const SizedBox(height: 16),
              Text(l10n.todoSubtasksTitle),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('todo_subtask_new'),
                      controller: _newSubtask,
                      decoration:
                          InputDecoration(hintText: l10n.todoSubtaskHint),
                      onSubmitted: (_) => _addSubtask(),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('todo_subtask_add'),
                    tooltip: l10n.todoSubtaskAdd,
                    onPressed: _addSubtask,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              for (var index = 0; index < _subtasks.length; index++)
                ListTile(
                  key: ValueKey('todo_subtask_editor_${_subtasks[index].id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
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
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('todo_dialog_cancel'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('todo_dialog_save'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          onPressed: () {
            if (_text.text.trim().isEmpty) {
              setState(() => _textError = l10n.todoTextRequired);
              return;
            }
            final alertMinutes = int.tryParse(_alertMinutes.text.trim());
            if (alertMinutes == null || alertMinutes < 0) {
              setState(() => _alertError = l10n.todoAlertMinutesInvalid);
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
            Navigator.of(context).pop<TodoDraft>((
              text: _text.text,
              due: _combinedDue,
              recurrence: recurrence,
              priority: _priority,
              subtasks: List<TodoSubtask>.unmodifiable(_subtasks),
              alertMinutes: alertMinutes,
            ));
          },
          child: Text(widget.proposal == null
              ? l10n.todoSave
              : l10n.todoProposalConfirm),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final anchor = _anchorDate();
    final firstDate = DateTime(anchor.year - 5, 1, 1);
    final lastDate = DateTime(anchor.year + 10, 12, 31);
    final initial = DateTime(anchor.year, anchor.month, anchor.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;
    _due.text = _formatDate(picked);
    setState(() {
      _scheduleError = null;
      _confirmedNoDate = false;
    });
  }

  Future<void> _pickTime() async {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    var initial = const TimeOfDay(hour: 9, minute: 0);
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      if (hour < 24 && minute < 60) {
        initial = TimeOfDay(hour: hour, minute: minute);
      }
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null || !mounted) return;
    if (!_hasValidDate && _due.text.trim().isEmpty) {
      _due.text = _formatDate(_anchorDate());
    }
    _time.text = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
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

  String _weekdayLabel(BuildContext context, int weekday) =>
      DateFormat.E(Localizations.localeOf(context).toString()).format(
        DateTime.utc(2026, 1, 5 + weekday - 1),
      );

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

  bool get _validTime {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    if (match == null) return false;
    return int.parse(match.group(1)!) < 24 && int.parse(match.group(2)!) < 60;
  }

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

  void _dueChanged(String value) {
    final explicit = parseExplicitDue(value);
    if (explicit?.hasTime == true) {
      final date = _formatDate(explicit!.date);
      _due.value = TextEditingValue(
        text: date,
        selection: TextSelection.collapsed(offset: date.length),
      );
      _time.text = _formatClock(explicit.date);
    }
    setState(() {
      _scheduleError = null;
      _confirmedNoDate = false;
    });
  }

  void _applyDateShortcut(TodoDateShortcut shortcut) {
    final date = TodoScheduleCalculator.dateForShortcut(
      shortcut,
      now: DateTime.now(),
    );
    final dateText = _formatDate(date);
    _due.text = dateText;
    setState(() => _scheduleError = null);
  }

  void _applyTimeShortcut(int minutes) {
    if (!_hasValidDate && _due.text.trim().isEmpty) {
      _due.text = _formatDate(_anchorDate());
    }
    final time = '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
    _time.text = time;
    setState(() => _scheduleError = null);
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
