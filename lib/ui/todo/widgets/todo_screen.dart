import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/domain/models/calendar_slot.dart';
import 'package:memex/domain/models/explicit_due.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';
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
    await widget.viewModel.refreshShortcutSettings();
    if (!mounted) return;
    final saved = await showDialog<
        ({
          String text,
          String due,
          TodoRecurrence? recurrence,
        })>(
      context: context,
      builder: (_) => _TodoDialog(
        item: item,
        settings: widget.viewModel.shortcutSettings,
      ),
    );
    if (saved == null) return;
    if (item == null) {
      await widget.viewModel.add(
        text: saved.text,
        due: saved.due,
        recurrence: saved.recurrence,
      );
    } else {
      await widget.viewModel.edit(
        item,
        text: saved.text,
        due: saved.due,
        recurrence: saved.recurrence,
        clearRecurrence: saved.recurrence == null,
      );
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
        ToastHelper.showError(context, l10n.permissionRequired(l10n.reminders));
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
      leading: Semantics(
        label: item.text,
        child: Checkbox(
          key: ValueKey('todo_done_${item.id}'),
          value: item.done,
          onChanged: (_) => widget.viewModel.toggleDone(item),
        ),
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
          if (item.sourceStale)
            Text(
              l10n.todoSourceChanged,
              key: ValueKey('todo_source_stale_${item.id}'),
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
  const _TodoDialog({this.item, required this.settings});

  final TodoItem? item;
  final TodoShortcutSettings settings;

  @override
  State<_TodoDialog> createState() => _TodoDialogState();
}

class _TodoDialogState extends State<_TodoDialog> {
  late final _text = TextEditingController(text: widget.item?.text ?? '');
  late final _due = TextEditingController(
    text: _initialDate(widget.item),
  );
  late final _time = TextEditingController(text: _initialTime(widget.item));
  late TodoRepeatFrequency? _frequency = widget.item?.recurrence?.frequency;
  late final Set<int> _weekdays =
      widget.item?.recurrence?.frequency == TodoRepeatFrequency.weekly
          ? widget.item!.recurrence!.weekdays.toSet()
          : {_anchorDate().weekday};
  String? _scheduleError;

  @override
  void dispose() {
    _text.dispose();
    _due.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final hasTime = _time.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(widget.item == null ? l10n.todoAdd : l10n.todoEdit),
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
                decoration: InputDecoration(hintText: l10n.todoTextHint),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('todo_due'),
                controller: _due,
                decoration: InputDecoration(
                  labelText: l10n.todoDueHint,
                  hintText: 'YYYY-MM-DD',
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
                ),
                onChanged: (_) => setState(() => _scheduleError = null),
              ),
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
            ],
          ),
        ),
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
            final recurrence = _recurrence();
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
            Navigator.of(context).pop((
              text: _text.text,
              due: _combinedDue,
              recurrence: recurrence,
            ));
          },
          child: Text(l10n.todoSave),
        ),
      ],
    );
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

  String _initialDate(TodoItem? item) {
    if (item == null || item.due == reportDueUnknown) return '';
    if (item.dueDate != null) return item.dueDate!;
    final explicit = parseExplicitDue(item.due);
    return explicit == null ? item.due : _formatDate(explicit.date);
  }

  String _initialTime(TodoItem? item) {
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
    setState(() => _scheduleError = null);
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
