import 'package:flutter/material.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/todo/view_models/todo_shortcut_settings_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';

class TodoShortcutSettingsPage extends StatefulWidget {
  const TodoShortcutSettingsPage({
    super.key,
    required this.viewModel,
  });

  final TodoShortcutSettingsViewModel viewModel;

  @override
  State<TodoShortcutSettingsPage> createState() =>
      _TodoShortcutSettingsPageState();
}

class _TodoShortcutSettingsPageState extends State<TodoShortcutSettingsPage> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.todoShortcutsTitle),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final viewModel = widget.viewModel;
          if (viewModel.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (viewModel.loadFailed) {
            return _loadError(l10n.todoShortcutsLoadFailed, l10n.todoRetry);
          }
          final settings = viewModel.settings;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle(l10n.todoShortcutsDaysTitle),
              for (final shortcut in TodoDateShortcut.values)
                SwitchListTile(
                  key: ValueKey('todo_shortcut_day_${shortcut.name}'),
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: AppColors.primary,
                  title: Text(_dayLabel(shortcut, l10n)),
                  value: settings.enabledDateShortcuts.contains(shortcut),
                  onChanged: viewModel.saving
                      ? null
                      : (enabled) => _toggleDay(shortcut, enabled),
                ),
              const Divider(color: AppColors.divider),
              _sectionTitle(l10n.todoShortcutsTimesTitle),
              for (var index = 0;
                  index < settings.timeShortcutsMinutes.length;
                  index++)
                ListTile(
                  key: ValueKey('todo_shortcut_time_$index'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _formatTime(context, settings.timeShortcutsMinutes[index]),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: viewModel.saving ? null : () => _editTime(index),
                ),
              const Divider(color: AppColors.divider),
              ListTile(
                key: const ValueKey('todo_shortcut_alert'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.todoShortcutsAlertTitle),
                trailing: DropdownButton<int>(
                  key: const ValueKey('todo_shortcut_alert_minutes'),
                  value: settings.defaultAlertMinutes,
                  onChanged: viewModel.saving
                      ? null
                      : (minutes) {
                          if (minutes == null) return;
                          _update(settings.copyWith(
                            defaultAlertMinutes: minutes,
                          ));
                        },
                  items: _alertOptions(settings.defaultAlertMinutes)
                      .map((minutes) => DropdownMenuItem(
                            value: minutes,
                            child: Text(_alertLabel(minutes, l10n)),
                          ))
                      .toList(),
                ),
              ),
              ListTile(
                key: const ValueKey('todo_shortcut_timezone'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.todoShortcutsTimezone),
                subtitle: Text(l10n.todoShortcutsTimezoneValue),
              ),
              if (viewModel.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.todoShortcutsSaveFailed,
                    key: const ValueKey('todo_shortcut_error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _loadError(String message, String retryLabel) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                key: const ValueKey('todo_shortcut_retry'),
                onPressed: widget.viewModel.load,
                child: Text(retryLabel),
              ),
            ],
          ),
        ),
      );

  String _dayLabel(TodoDateShortcut shortcut, AppLocalizations l10n) =>
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

  String _alertLabel(int minutes, AppLocalizations l10n) => minutes == 0
      ? l10n.todoShortcutsAlertAtTime
      : l10n.todoShortcutsAlertBefore(minutes);

  List<int> _alertOptions(int current) =>
      ({0, 5, 10, 15, 20, 30, 45, 60, current}.toList()..sort());

  Future<void> _toggleDay(TodoDateShortcut shortcut, bool enabled) async {
    final days = {...widget.viewModel.settings.enabledDateShortcuts};
    if (enabled) {
      days.add(shortcut);
    } else {
      days.remove(shortcut);
    }
    await _update(widget.viewModel.settings.copyWith(
      enabledDateShortcuts: days,
    ));
  }

  Future<void> _editTime(int index) async {
    final current = widget.viewModel.settings.timeShortcutsMinutes[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    final times = [...widget.viewModel.settings.timeShortcutsMinutes];
    times[index] = picked.hour * 60 + picked.minute;
    await _update(widget.viewModel.settings.copyWith(
      timeShortcutsMinutes: times,
    ));
  }

  Future<void> _update(TodoShortcutSettings settings) =>
      widget.viewModel.update(settings);
}
