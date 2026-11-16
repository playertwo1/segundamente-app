import 'package:flutter/material.dart';
import 'package:memex/data/services/active_assistant_service.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

class ActiveAssistantSettingsPage extends StatefulWidget {
  const ActiveAssistantSettingsPage({
    super.key,
    this.service,
  });

  final ActiveAssistantService? service;

  @override
  State<ActiveAssistantSettingsPage> createState() =>
      _ActiveAssistantSettingsPageState();
}

class _ActiveAssistantSettingsPageState
    extends State<ActiveAssistantSettingsPage> {
  late final ActiveAssistantService _service;
  ActiveAssistantSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ActiveAssistantService.instance;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final loaded = await _service.loadSettings();
      if (mounted) {
        setState(() {
          _settings = loaded;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _update(ActiveAssistantSettings newSettings) async {
    setState(() {
      _settings = newSettings;
      _saving = true;
      _errorMessage = null;
    });
    try {
      await _service.saveSettings(newSettings);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _formatMinutes(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTime({
    required int currentMinutes,
    required void Function(int newMinutes) onSelected,
  }) async {
    final initial = TimeOfDay(
      hour: currentMinutes ~/ 60,
      minute: currentMinutes % 60,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      onSelected(picked.hour * 60 + picked.minute);
    }
  }

  bool _isExplicitlySilenced(ActiveAssistantSettings settings) {
    if (settings.silencedUntilIso == null) return false;
    final parsed = DateTime.tryParse(settings.silencedUntilIso!);
    return parsed != null && parsed.isAfter(DateTime.now());
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.activeAssistantSettingsTitle),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _settings == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage ?? l10n.todoLoadFailed,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        child: Text(l10n.todoRetry),
                      ),
                    ],
                  ),
                )
              : _buildContent(context, _settings!),
    );
  }

  Widget _buildContent(BuildContext context, ActiveAssistantSettings settings) {
    final l10n = UserStorage.l10n;
    final isSilenced = _isExplicitlySilenced(settings);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(l10n.activeAssistantTitle),
        SwitchListTile(
          key: const ValueKey('active_assistant_morning_enabled'),
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary,
          title: Text(l10n.activeAssistantMorningLabel),
          value: settings.morningBriefingEnabled,
          onChanged: _saving
              ? null
              : (enabled) => _update(
                    settings.copyWith(morningBriefingEnabled: enabled),
                  ),
        ),
        ListTile(
          key: const ValueKey('active_assistant_morning_time'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.activeAssistantMorningLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatMinutes(settings.morningBriefingMinutes)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          onTap: _saving || !settings.morningBriefingEnabled
              ? null
              : () => _pickTime(
                    currentMinutes: settings.morningBriefingMinutes,
                    onSelected: (minutes) => _update(
                      settings.copyWith(morningBriefingMinutes: minutes),
                    ),
                  ),
        ),
        SwitchListTile(
          key: const ValueKey('active_assistant_afternoon_enabled'),
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary,
          title: Text(l10n.activeAssistantAfternoonLabel),
          value: settings.afternoonBriefingEnabled,
          onChanged: _saving
              ? null
              : (enabled) => _update(
                    settings.copyWith(afternoonBriefingEnabled: enabled),
                  ),
        ),
        ListTile(
          key: const ValueKey('active_assistant_afternoon_time'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.activeAssistantAfternoonLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatMinutes(settings.afternoonBriefingMinutes)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          onTap: _saving || !settings.afternoonBriefingEnabled
              ? null
              : () => _pickTime(
                    currentMinutes: settings.afternoonBriefingMinutes,
                    onSelected: (minutes) => _update(
                      settings.copyWith(afternoonBriefingMinutes: minutes),
                    ),
                  ),
        ),
        const Divider(color: AppColors.divider),
        _sectionTitle(l10n.activeAssistantStalledSection),
        SwitchListTile(
          key: const ValueKey('active_assistant_stalled_enabled'),
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary,
          title: Text(l10n.activeAssistantStalledSection),
          value: settings.stalledReminderEnabled,
          onChanged: _saving
              ? null
              : (enabled) => _update(
                    settings.copyWith(stalledReminderEnabled: enabled),
                  ),
        ),
        ListTile(
          key: const ValueKey('active_assistant_stalled_threshold'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.activeAssistantStalledThresholdLabel),
          trailing: DropdownButton<int>(
            value: settings.stalledThresholdDays,
            dropdownColor: AppColors.surface,
            onChanged: _saving || !settings.stalledReminderEnabled
                ? null
                : (days) {
                    if (days != null) {
                      _update(settings.copyWith(stalledThresholdDays: days));
                    }
                  },
            items: [1, 2, 3, 5, 7, 14]
                .map((days) => DropdownMenuItem(
                      value: days,
                      child: Text(l10n.activeAssistantStalledDays(days)),
                    ))
                .toList(),
          ),
        ),
        const Divider(color: AppColors.divider),
        _sectionTitle(l10n.activeAssistantPersonaSection),
        SwitchListTile(
          key: const ValueKey('active_assistant_persona_enabled'),
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary,
          title: Text(l10n.activeAssistantPersonaSuggestionsLabel),
          value: settings.personaSuggestionsEnabled,
          onChanged: _saving
              ? null
              : (enabled) => _update(
                    settings.copyWith(personaSuggestionsEnabled: enabled),
                  ),
        ),
        ListTile(
          key: const ValueKey('active_assistant_persona_daily_limit'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.activeAssistantPersonaDailyLimitLabel),
          trailing: DropdownButton<int>(
            value: settings.maxPersonaSuggestionsPerDay,
            dropdownColor: AppColors.surface,
            onChanged: _saving || !settings.personaSuggestionsEnabled
                ? null
                : (limit) {
                    if (limit != null) {
                      _update(
                        settings.copyWith(maxPersonaSuggestionsPerDay: limit),
                      );
                    }
                  },
            items: [1, 2, 3, 5]
                .map((count) => DropdownMenuItem(
                      value: count,
                      child: Text('$count'),
                    ))
                .toList(),
          ),
        ),
        const Divider(color: AppColors.divider),
        _sectionTitle(l10n.activeAssistantQuietHoursLabel),
        SwitchListTile(
          key: const ValueKey('active_assistant_quiet_hours_enabled'),
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary,
          title: Text(l10n.activeAssistantQuietHoursLabel),
          value: settings.quietHoursEnabled,
          onChanged: _saving
              ? null
              : (enabled) => _update(
                    settings.copyWith(quietHoursEnabled: enabled),
                  ),
        ),
        ListTile(
          key: const ValueKey('active_assistant_quiet_hours_start'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.activeAssistantQuietHoursStart),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatMinutes(settings.quietHoursStartMinutes)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          onTap: _saving || !settings.quietHoursEnabled
              ? null
              : () => _pickTime(
                    currentMinutes: settings.quietHoursStartMinutes,
                    onSelected: (minutes) => _update(
                      settings.copyWith(quietHoursStartMinutes: minutes),
                    ),
                  ),
        ),
        ListTile(
          key: const ValueKey('active_assistant_quiet_hours_end'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.activeAssistantQuietHoursEnd),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatMinutes(settings.quietHoursEndMinutes)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          onTap: _saving || !settings.quietHoursEnabled
              ? null
              : () => _pickTime(
                    currentMinutes: settings.quietHoursEndMinutes,
                    onSelected: (minutes) => _update(
                      settings.copyWith(quietHoursEndMinutes: minutes),
                    ),
                  ),
        ),
        const Divider(color: AppColors.divider),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            key: const ValueKey('active_assistant_silence_toggle'),
            icon: Icon(
              isSilenced ? Icons.notifications_active : Icons.notifications_off,
            ),
            label: Text(
              isSilenced
                  ? l10n.activeAssistantClearSilence
                  : l10n.activeAssistantSilenceToday,
            ),
            onPressed: _saving
                ? null
                : () async {
                    if (isSilenced) {
                      await _update(
                        settings.copyWith(clearSilencedUntil: true),
                      );
                    } else {
                      await _service.silenceFor(const Duration(hours: 12));
                      await _load();
                    }
                  },
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
