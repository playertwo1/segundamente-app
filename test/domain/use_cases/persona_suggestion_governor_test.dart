import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/persona_suggestion_governor.dart';

void main() {
  group('PersonaSuggestionGovernor', () {
    // 2026-11-16 15:00 UTC = 2026-11-16 12:00 America/Sao_Paulo (UTC-3)
    final now = DateTime.utc(2026, 11, 16, 15, 0);

    test('allows suggestion when within cap and spacing', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        maxPersonaSuggestionsPerDay: 2,
        quietHoursEnabled: false,
      );
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: [
          // 3 hours ago today
          now.subtract(const Duration(hours: 3)),
        ],
      );
      expect(allowed, isTrue);
    });

    test('rejects suggestion when minSpacing (2h default) is not met', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        maxPersonaSuggestionsPerDay: 5,
        quietHoursEnabled: false,
      );
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: [
          // 1 hour ago today
          now.subtract(const Duration(hours: 1)),
        ],
      );
      expect(allowed, isFalse);
    });

    test('rejects suggestion when daily cap is reached', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        maxPersonaSuggestionsPerDay: 2,
        quietHoursEnabled: false,
      );
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: [
          // Both occurred today, well spaced
          now.subtract(const Duration(hours: 6)),
          now.subtract(const Duration(hours: 3)),
        ],
      );
      expect(allowed, isFalse);
    });

    test('counts all suggestions toward daily cap regardless of dismissed state',
        () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        maxPersonaSuggestionsPerDay: 2,
        quietHoursEnabled: false,
      );
      // Even if these timestamps came from dismissed suggestions, governor counts them
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: [
          now.subtract(const Duration(hours: 5)),
          now.subtract(const Duration(hours: 2, minutes: 30)),
        ],
      );
      expect(allowed, isFalse);
    });

    test('ignores suggestions from previous days for daily cap', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        maxPersonaSuggestionsPerDay: 2,
        quietHoursEnabled: false,
      );
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: [
          // Yesterday in Sao Paulo
          now.subtract(const Duration(days: 1)),
          now.subtract(const Duration(days: 1, hours: 2)),
          now.subtract(const Duration(days: 2)),
        ],
      );
      expect(allowed, isTrue);
    });

    test('returns false when personaSuggestionsEnabled is false', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: false,
        quietHoursEnabled: false,
      );
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: const [],
      );
      expect(allowed, isFalse);
    });

    test('returns false during quiet hours crossing midnight', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        quietHoursEnabled: true,
        quietHoursStartMinutes: 1320, // 22:00
        quietHoursEndMinutes: 480, // 08:00
      );
      // 23:00 local time = 02:00 UTC next day
      final nightTime = DateTime.utc(2026, 11, 17, 2, 0);
      expect(
        PersonaSuggestionGovernor.canSuggestNow(
          now: nightTime,
          settings: settings,
          recentSuggestionTimestamps: const [],
        ),
        isFalse,
      );

      // 06:00 local time = 09:00 UTC
      final earlyMorning = DateTime.utc(2026, 11, 17, 9, 0);
      expect(
        PersonaSuggestionGovernor.canSuggestNow(
          now: earlyMorning,
          settings: settings,
          recentSuggestionTimestamps: const [],
        ),
        isFalse,
      );

      // 14:00 local time = 17:00 UTC
      final daytime = DateTime.utc(2026, 11, 17, 17, 0);
      expect(
        PersonaSuggestionGovernor.canSuggestNow(
          now: daytime,
          settings: settings,
          recentSuggestionTimestamps: const [],
        ),
        isTrue,
      );
    });

    test('returns false when silencedUntilIso is in the future', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        quietHoursEnabled: false,
        silencedUntilIso: now.add(const Duration(hours: 2)).toIso8601String(),
      );
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: const [],
      );
      expect(allowed, isFalse);
    });

    test('returns true when silencedUntilIso is in the past', () {
      final settings = ActiveAssistantSettings(
        personaSuggestionsEnabled: true,
        quietHoursEnabled: false,
        silencedUntilIso:
            now.subtract(const Duration(hours: 2)).toIso8601String(),
      );
      final allowed = PersonaSuggestionGovernor.canSuggestNow(
        now: now,
        settings: settings,
        recentSuggestionTimestamps: const [],
      );
      expect(allowed, isTrue);
    });
  });
}
