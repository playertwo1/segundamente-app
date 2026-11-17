import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/persona_task_suggestion.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/daily_briefing_builder.dart';
import 'package:memex/domain/use_cases/persona_suggestion_governor.dart';
import 'package:memex/domain/use_cases/stalled_task_detector.dart';
import 'package:memex/utils/user_storage.dart';

class ActiveAssistantState {
  const ActiveAssistantState({
    required this.settings,
    this.briefing,
    this.stalledNudges = const [],
    this.personaSuggestions = const [],
  });

  final ActiveAssistantSettings settings;
  final DailyBriefing? briefing;
  final List<StalledTaskNudge> stalledNudges;
  final List<PersonaTaskSuggestion> personaSuggestions;
}

class ActiveAssistantService {
  ActiveAssistantService._({
    DateTime Function()? clock,
    Future<ActiveAssistantSettings> Function()? loadSettings,
    Future<void> Function(ActiveAssistantSettings)? saveSettings,
    Future<String?> Function()? loadDismissedBriefingKey,
    Future<void> Function(String?)? saveDismissedBriefingKey,
    Future<Map<String, String>> Function()? loadStalledSnoozeMap,
    Future<void> Function(Map<String, String>)? saveStalledSnoozeMap,
    Future<String?> Function()? loadPersonaSuggestionsRaw,
    Future<void> Function(String)? savePersonaSuggestionsRaw,
  })  : _clock = clock ?? DateTime.now,
        _loadSettings = loadSettings ?? UserStorage.getActiveAssistantSettings,
        _saveSettings = saveSettings ?? UserStorage.setActiveAssistantSettings,
        _loadDismissedBriefingKey = loadDismissedBriefingKey ??
            UserStorage.getActiveAssistantDismissedBriefingKey,
        _saveDismissedBriefingKey = saveDismissedBriefingKey ??
            UserStorage.setActiveAssistantDismissedBriefingKey,
        _loadStalledSnoozeMap = loadStalledSnoozeMap ??
            UserStorage.getActiveAssistantStalledSnoozeMap,
        _saveStalledSnoozeMap = saveStalledSnoozeMap ??
            UserStorage.setActiveAssistantStalledSnoozeMap,
        _loadPersonaSuggestionsRaw = loadPersonaSuggestionsRaw ??
            UserStorage.getActiveAssistantPersonaSuggestionsRaw,
        _savePersonaSuggestionsRaw = savePersonaSuggestionsRaw ??
            UserStorage.setActiveAssistantPersonaSuggestionsRaw;

  @visibleForTesting
  ActiveAssistantService.forTesting({
    DateTime Function()? clock,
    Future<ActiveAssistantSettings> Function()? loadSettings,
    Future<void> Function(ActiveAssistantSettings)? saveSettings,
    Future<String?> Function()? loadDismissedBriefingKey,
    Future<void> Function(String?)? saveDismissedBriefingKey,
    Future<Map<String, String>> Function()? loadStalledSnoozeMap,
    Future<void> Function(Map<String, String>)? saveStalledSnoozeMap,
    Future<String?> Function()? loadPersonaSuggestionsRaw,
    Future<void> Function(String)? savePersonaSuggestionsRaw,
  }) : this._(
          clock: clock,
          loadSettings: loadSettings,
          saveSettings: saveSettings,
          loadDismissedBriefingKey: loadDismissedBriefingKey,
          saveDismissedBriefingKey: saveDismissedBriefingKey,
          loadStalledSnoozeMap: loadStalledSnoozeMap,
          saveStalledSnoozeMap: saveStalledSnoozeMap,
          loadPersonaSuggestionsRaw: loadPersonaSuggestionsRaw,
          savePersonaSuggestionsRaw: savePersonaSuggestionsRaw,
        );

  static final ActiveAssistantService instance = ActiveAssistantService._();

  final DateTime Function() _clock;

  /// Current time on this service's clock, so callers judge silence against
  /// the same time the service used to set it.
  DateTime now() => _clock();
  final Future<ActiveAssistantSettings> Function() _loadSettings;
  final Future<void> Function(ActiveAssistantSettings) _saveSettings;
  final Future<String?> Function() _loadDismissedBriefingKey;
  final Future<void> Function(String?) _saveDismissedBriefingKey;
  final Future<Map<String, String>> Function() _loadStalledSnoozeMap;
  final Future<void> Function(Map<String, String>) _saveStalledSnoozeMap;
  final Future<String?> Function() _loadPersonaSuggestionsRaw;
  final Future<void> Function(String) _savePersonaSuggestionsRaw;

  Future<ActiveAssistantSettings> loadSettings() => _loadSettings();

  Future<void> saveSettings(ActiveAssistantSettings settings) =>
      _saveSettings(settings);

  Future<Map<String, String>> loadStalledSnoozeMap() => _loadStalledSnoozeMap();

  Future<void> saveStalledSnoozeMap(Map<String, String> map) =>
      _saveStalledSnoozeMap(map);

  Future<List<PersonaTaskSuggestion>> loadPersonaSuggestions() async {
    try {
      final raw = await _loadPersonaSuggestionsRaw();
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final list = <PersonaTaskSuggestion>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            list.add(
              PersonaTaskSuggestion.fromJson(item.cast<String, dynamic>()),
            );
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _savePersonaSuggestions(
    List<PersonaTaskSuggestion> suggestions,
  ) async {
    final json = jsonEncode(suggestions.map((s) => s.toJson()).toList());
    await _savePersonaSuggestionsRaw(json);
  }

  Future<bool> tryAddPersonaSuggestion(
    PersonaTaskSuggestion suggestion, {
    DateTime? now,
  }) async {
    final currentTime = now ?? _clock();
    final settings = await loadSettings();
    final all = await loadPersonaSuggestions();
    final timestamps = all
        .map((s) => DateTime.tryParse(s.createdAt))
        .whereType<DateTime>()
        .toList();

    final allowed = PersonaSuggestionGovernor.canSuggestNow(
      now: currentTime,
      settings: settings,
      recentSuggestionTimestamps: timestamps,
    );
    if (!allowed) {
      return false;
    }

    var updated = [...all, suggestion];
    if (updated.length > 50) {
      updated = updated.sublist(updated.length - 50);
    }
    await _savePersonaSuggestions(updated);
    return true;
  }

  Future<void> dismissPersonaSuggestion(String suggestionId) async {
    final all = await loadPersonaSuggestions();
    var changed = false;
    final updated = all.map((s) {
      if (s.id == suggestionId && !s.dismissed) {
        changed = true;
        return s.copyWith(dismissed: true);
      }
      return s;
    }).toList();
    if (changed) {
      await _savePersonaSuggestions(updated);
    }
  }

  Future<ActiveAssistantState> buildState(
    List<TodoItem> items, {
    DateTime? now,
  }) async {
    final currentTime = now ?? _clock();
    final settings = await loadSettings();
    final snoozeMap = await loadStalledSnoozeMap();

    final stalledNudges = StalledTaskDetector.detect(
      items: items,
      now: currentTime,
      settings: settings,
      snoozedUntilByTaskId: snoozeMap,
    );

    DailyBriefing? briefing;
    final period = DailyBriefingBuilder.activePeriodFor(
      now: currentTime,
      settings: settings,
    );
    if (period != null) {
      final candidate = DailyBriefingBuilder.build(
        items: items,
        now: currentTime,
        period: period,
      );
      if (!candidate.isEmpty) {
        final dismissedKey = await _loadDismissedBriefingKey();
        final briefingKey = '${candidate.dateKey}:${candidate.period.name}';
        if (dismissedKey != briefingKey) {
          briefing = candidate;
        }
      }
    }

    List<PersonaTaskSuggestion> personaSuggestions = const [];
    if (settings.personaSuggestionsEnabled &&
        !settings.isSilencedAt(currentTime)) {
      final all = await loadPersonaSuggestions();
      personaSuggestions = [for (final s in all) if (!s.dismissed) s];
    }

    return ActiveAssistantState(
      settings: settings,
      briefing: briefing,
      stalledNudges: stalledNudges,
      personaSuggestions: personaSuggestions,
    );
  }

  Future<void> dismissBriefing(DailyBriefing briefing) async {
    final briefingKey = '${briefing.dateKey}:${briefing.period.name}';
    await _saveDismissedBriefingKey(briefingKey);
  }

  Future<void> silenceFor(Duration duration, {DateTime? now}) async {
    final currentTime = now ?? _clock();
    final settings = await loadSettings();
    final until = currentTime.add(duration).toUtc().toIso8601String();
    await saveSettings(settings.copyWith(silencedUntilIso: until));
  }

  Future<void> snoozeStalledTask(
    String taskId, {
    Duration duration = const Duration(days: 3),
    DateTime? now,
  }) async {
    final currentTime = now ?? _clock();
    final map = Map<String, String>.from(await loadStalledSnoozeMap());
    map[taskId] = currentTime.add(duration).toUtc().toIso8601String();

    map.removeWhere((_, untilIso) {
      final parsed = DateTime.tryParse(untilIso);
      return parsed == null || !parsed.isAfter(currentTime);
    });

    await saveStalledSnoozeMap(map);
  }

  Future<void> clearStalledSnooze(String taskId) async {
    final map = Map<String, String>.from(await loadStalledSnoozeMap());
    if (map.containsKey(taskId)) {
      map.remove(taskId);
      await saveStalledSnoozeMap(map);
    }
  }
}
