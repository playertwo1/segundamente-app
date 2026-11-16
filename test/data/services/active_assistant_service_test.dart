import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/active_assistant_service.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/persona_task_suggestion.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/use_cases/daily_briefing_builder.dart';

void main() {
  group('ActiveAssistantService', () {
    // 2026-11-16 12:30 UTC = 2026-11-16 09:30 local (morning period active: 09:00 - 14:00)
    final fixedMorning = DateTime.utc(2026, 11, 16, 12, 30);

    ActiveAssistantSettings currentSettings = ActiveAssistantSettings.defaults;
    String? dismissedKey;
    Map<String, String> stalledSnooze = {};
    String? personaSuggestionsRaw;

    setUp(() {
      currentSettings = ActiveAssistantSettings.defaults;
      dismissedKey = null;
      stalledSnooze = {};
      personaSuggestionsRaw = null;
    });

    ActiveAssistantService createService({DateTime Function()? clock}) {
      return ActiveAssistantService.forTesting(
        clock: clock ?? () => fixedMorning,
        loadSettings: () async => currentSettings,
        saveSettings: (s) async => currentSettings = s,
        loadDismissedBriefingKey: () async => dismissedKey,
        saveDismissedBriefingKey: (k) async => dismissedKey = k,
        loadStalledSnoozeMap: () async => stalledSnooze,
        saveStalledSnoozeMap: (m) async => stalledSnooze = m,
        loadPersonaSuggestionsRaw: () async => personaSuggestionsRaw,
        savePersonaSuggestionsRaw: (j) async => personaSuggestionsRaw = j,
      );
    }

    test('buildState returns briefing when active period has items', () async {
      final service = createService();
      final items = [
        const TodoItem(
          id: '1',
          text: 'Overdue task',
          due: '2026-11-15',
          dueDate: '2026-11-15',
          done: false,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];

      final state = await service.buildState(items);
      expect(state.briefing, isNotNull);
      expect(state.briefing!.period, DailyBriefingPeriod.morning);
      expect(state.briefing!.overdueItems.length, 1);
    });

    test('buildState returns null briefing when items are empty', () async {
      final service = createService();
      final state = await service.buildState(const []);
      expect(state.briefing, isNull);
    });

    test('buildState returns null briefing when dismissed for this period',
        () async {
      final service = createService();
      final items = [
        const TodoItem(
          id: '1',
          text: 'Task today',
          due: '2026-11-16',
          dueDate: '2026-11-16',
          done: false,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];

      // Dismiss morning briefing for 2026-11-16
      dismissedKey = '2026-11-16:morning';

      final state = await service.buildState(items);
      expect(state.briefing, isNull);
    });

    test('buildState computes stalledNudges even when briefing is dismissed',
        () async {
      final service = createService();
      final items = [
        const TodoItem(
          id: 'stalled_1',
          text: 'Task stalled 4 days',
          due: '2026-11-12',
          dueDate: '2026-11-12',
          done: false,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];

      dismissedKey = '2026-11-16:morning';

      final state = await service.buildState(items);
      expect(state.briefing, isNull);
      expect(state.stalledNudges.length, 1);
      expect(state.stalledNudges.first.item.id, 'stalled_1');
      expect(state.stalledNudges.first.stalledDays, 4);
    });

    test('buildState computes stalledNudges when period is null', () async {
      // 2026-11-16 11:30 UTC = 2026-11-16 08:30 local (outside quiet hours 22:00-08:00, but before 09:00 morning briefing)
      final preBriefingTime = DateTime.utc(2026, 11, 16, 11, 30);
      final service = createService(clock: () => preBriefingTime);
      final items = [
        const TodoItem(
          id: 'stalled_1',
          text: 'Task stalled 4 days',
          due: '2026-11-12',
          dueDate: '2026-11-12',
          done: false,
          createdAt: '2026-11-01T10:00:00.000Z',
        ),
      ];

      final state = await service.buildState(items);
      expect(state.briefing, isNull);
      expect(state.stalledNudges.length, 1);
      expect(state.stalledNudges.first.item.id, 'stalled_1');
    });

    test('dismissBriefing stores dismissed key', () async {
      final service = createService();
      const briefing = DailyBriefing(
        period: DailyBriefingPeriod.morning,
        dateKey: '2026-11-16',
      );

      await service.dismissBriefing(briefing);
      expect(dismissedKey, '2026-11-16:morning');
    });

    test('silenceFor updates settings with future timestamp', () async {
      final service = createService();
      await service.silenceFor(const Duration(hours: 2));

      expect(currentSettings.silencedUntilIso, isNotNull);
      final silencedUntil =
          DateTime.parse(currentSettings.silencedUntilIso!).toUtc();
      expect(
        silencedUntil,
        fixedMorning.add(const Duration(hours: 2)).toUtc(),
      );
    });

    test('load and save stalled snooze map works', () async {
      final service = createService();
      await service.saveStalledSnoozeMap({'item1': '2026-11-20T10:00:00Z'});
      final loaded = await service.loadStalledSnoozeMap();
      expect(loaded, {'item1': '2026-11-20T10:00:00Z'});
    });

    test('snoozeStalledTask adds snooze and prunes expired snoozes', () async {
      stalledSnooze = {
        'expired_task': '2026-11-15T10:00:00.000Z', // Expired relative to fixedMorning (2026-11-16 12:30 UTC)
        'valid_task': '2026-11-18T10:00:00.000Z', // Still valid
      };

      final service = createService();
      await service.snoozeStalledTask('new_task', duration: const Duration(days: 3));

      expect(stalledSnooze.containsKey('expired_task'), isFalse);
      expect(stalledSnooze['valid_task'], '2026-11-18T10:00:00.000Z');
      expect(
        stalledSnooze['new_task'],
        fixedMorning.add(const Duration(days: 3)).toUtc().toIso8601String(),
      );
    });

    test('clearStalledSnooze removes task from snooze map', () async {
      stalledSnooze = {
        'task_to_clear': '2026-11-20T10:00:00.000Z',
        'task_to_keep': '2026-11-20T10:00:00.000Z',
      };

      final service = createService();
      await service.clearStalledSnooze('task_to_clear');

      expect(stalledSnooze.containsKey('task_to_clear'), isFalse);
      expect(stalledSnooze['task_to_keep'], '2026-11-20T10:00:00.000Z');
    });

    PersonaTaskSuggestion createSuggestion({
      String id = 'sug-1',
      String characterId = 'yaoyao',
      String characterName = 'Yaoyao',
      String message = 'Take a break!',
      String? createdAt,
      bool dismissed = false,
    }) {
      return PersonaTaskSuggestion(
        id: id,
        characterId: characterId,
        characterName: characterName,
        message: message,
        proposal: TodoProposal(
          id: 'prop-$id',
          title: 'Rest a bit',
          dateState: TodoProposalDateState.unspecified,
          timeState: TodoProposalTimeState.unspecified,
        ),
        createdAt: createdAt ?? fixedMorning.toUtc().toIso8601String(),
        dismissed: dismissed,
      );
    }

    test('tryAddPersonaSuggestion adds suggestion when governor allows',
        () async {
      final service = createService();
      final suggestion = createSuggestion();

      final added = await service.tryAddPersonaSuggestion(suggestion);
      expect(added, isTrue);

      final loaded = await service.loadPersonaSuggestions();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'sug-1');
      expect(loaded.first.characterName, 'Yaoyao');
      expect(loaded.first.proposal.title, 'Rest a bit');
    });

    test(
        'tryAddPersonaSuggestion rejects suggestion when frequency spacing violated',
        () async {
      final service = createService();
      final suggestion1 = createSuggestion(
        id: 'sug-1',
        createdAt: fixedMorning.toUtc().toIso8601String(),
      );
      final added1 = await service.tryAddPersonaSuggestion(
        suggestion1,
        now: fixedMorning,
      );
      expect(added1, isTrue);

      // 30 minutes later - should be rejected by 2h minSpacing
      final suggestion2 = createSuggestion(
        id: 'sug-2',
        createdAt: fixedMorning
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
      );
      final added2 = await service.tryAddPersonaSuggestion(
        suggestion2,
        now: fixedMorning.add(const Duration(minutes: 30)),
      );
      expect(added2, isFalse);

      final loaded = await service.loadPersonaSuggestions();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'sug-1');
    });

    test('dismissPersonaSuggestion marks matching suggestion as dismissed',
        () async {
      final service = createService();
      final suggestion = createSuggestion(id: 'sug-1');
      await service.tryAddPersonaSuggestion(suggestion);

      await service.dismissPersonaSuggestion('sug-1');
      final loaded = await service.loadPersonaSuggestions();
      expect(loaded.first.dismissed, isTrue);
    });

    test(
        'buildState includes active persona suggestions and filters dismissed/silenced',
        () async {
      final service = createService();
      final suggestion1 = createSuggestion(id: 'sug-1');
      final suggestion2 = createSuggestion(
        id: 'sug-2',
        createdAt: fixedMorning
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        dismissed: true,
      );
      personaSuggestionsRaw =
          jsonEncode([suggestion1.toJson(), suggestion2.toJson()]);

      // Load with active suggestions enabled
      final state1 = await service.buildState(const []);
      expect(state1.personaSuggestions.length, 1);
      expect(state1.personaSuggestions.first.id, 'sug-1');

      // When disabled in settings
      currentSettings = currentSettings.copyWith(
        personaSuggestionsEnabled: false,
      );
      final state2 = await service.buildState(const []);
      expect(state2.personaSuggestions, isEmpty);

      // When silenced
      currentSettings = currentSettings.copyWith(
        personaSuggestionsEnabled: true,
        silencedUntilIso:
            fixedMorning.add(const Duration(hours: 1)).toUtc().toIso8601String(),
      );
      final state3 = await service.buildState(const []);
      expect(state3.personaSuggestions, isEmpty);
    });
  });
}
