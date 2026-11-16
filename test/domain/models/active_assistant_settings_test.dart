import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/active_assistant_settings.dart';

void main() {
  group('ActiveAssistantSettings', () {
    test('defaults match approved values', () {
      final settings = ActiveAssistantSettings.defaults;
      expect(settings.morningBriefingEnabled, isTrue);
      expect(settings.morningBriefingMinutes, 540); // 09:00
      expect(settings.afternoonBriefingEnabled, isTrue);
      expect(settings.afternoonBriefingMinutes, 840); // 14:00
      expect(settings.stalledReminderEnabled, isTrue);
      expect(settings.stalledThresholdDays, 3);
      expect(settings.personaSuggestionsEnabled, isTrue);
      expect(settings.maxPersonaSuggestionsPerDay, 2);
      expect(settings.quietHoursEnabled, isTrue);
      expect(settings.quietHoursStartMinutes, 1320); // 22:00
      expect(settings.quietHoursEndMinutes, 480); // 08:00
      expect(settings.silencedUntilIso, isNull);
    });

    test('round trips through JSON serialization', () {
      final settings = ActiveAssistantSettings(
        morningBriefingEnabled: false,
        morningBriefingMinutes: 600,
        afternoonBriefingEnabled: true,
        afternoonBriefingMinutes: 900,
        stalledReminderEnabled: false,
        stalledThresholdDays: 5,
        personaSuggestionsEnabled: false,
        maxPersonaSuggestionsPerDay: 4,
        quietHoursEnabled: false,
        quietHoursStartMinutes: 1380,
        quietHoursEndMinutes: 420,
        silencedUntilIso: '2026-11-20T10:00:00.000Z',
      );

      final json = settings.toJson();
      final restored = ActiveAssistantSettings.fromJson(json);

      expect(restored, equals(settings));
      expect(restored.morningBriefingEnabled, isFalse);
      expect(restored.morningBriefingMinutes, 600);
      expect(restored.afternoonBriefingEnabled, isTrue);
      expect(restored.afternoonBriefingMinutes, 900);
      expect(restored.stalledReminderEnabled, isFalse);
      expect(restored.stalledThresholdDays, 5);
      expect(restored.personaSuggestionsEnabled, isFalse);
      expect(restored.maxPersonaSuggestionsPerDay, 4);
      expect(restored.quietHoursEnabled, isFalse);
      expect(restored.quietHoursStartMinutes, 1380);
      expect(restored.quietHoursEndMinutes, 420);
      expect(restored.silencedUntilIso, '2026-11-20T10:00:00.000Z');
    });

    test('fromJson falls back to defaults for missing keys', () {
      final restored = ActiveAssistantSettings.fromJson(const {});
      expect(restored, equals(ActiveAssistantSettings.defaults));
    });

    test('copyWith updates specified fields and clearSilencedUntil works', () {
      final settings = ActiveAssistantSettings.defaults.copyWith(
        morningBriefingMinutes: 480,
        silencedUntilIso: '2026-11-16T12:00:00.000Z',
      );
      expect(settings.morningBriefingMinutes, 480);
      expect(settings.silencedUntilIso, '2026-11-16T12:00:00.000Z');

      final cleared = settings.copyWith(clearSilencedUntil: true);
      expect(cleared.silencedUntilIso, isNull);
      expect(cleared.morningBriefingMinutes, 480);
    });

    test('rejects out of range values with ArgumentError', () {
      expect(
        () => ActiveAssistantSettings(morningBriefingMinutes: -1),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(morningBriefingMinutes: 1440),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(afternoonBriefingMinutes: -1),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(afternoonBriefingMinutes: 1440),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(stalledThresholdDays: 0),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(stalledThresholdDays: 31),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(maxPersonaSuggestionsPerDay: 0),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(maxPersonaSuggestionsPerDay: 11),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(quietHoursStartMinutes: -1),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(quietHoursStartMinutes: 1440),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(quietHoursEndMinutes: -1),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(quietHoursEndMinutes: 1440),
        throwsArgumentError,
      );
      expect(
        () => ActiveAssistantSettings(silencedUntilIso: 'invalid-iso-date'),
        throwsArgumentError,
      );
    });

    test('normalizes empty or whitespace silencedUntilIso to null', () {
      final settings = ActiveAssistantSettings(silencedUntilIso: '   ');
      expect(settings.silencedUntilIso, isNull);
    });

    test(
        'fromJson throws FormatException on invalid bounds or malformed types',
        () {
      expect(
        () =>
            ActiveAssistantSettings.fromJson({'morning_briefing_minutes': 9999}),
        throwsFormatException,
      );
      expect(
        () =>
            ActiveAssistantSettings.fromJson({'morning_briefing_minutes': 'nine'}),
        throwsFormatException,
      );
      expect(
        () => ActiveAssistantSettings.fromJson({'quiet_hours_enabled': 123}),
        throwsFormatException,
      );
      expect(
        () => ActiveAssistantSettings.fromJson({'silenced_until_iso': 456}),
        throwsFormatException,
      );
      expect(
        () =>
            ActiveAssistantSettings.fromJson({'silenced_until_iso': 'bad-date'}),
        throwsFormatException,
      );
    });

    group('isInQuietHours', () {
      test('correctly handles interval crossing midnight (22:00 to 08:00)', () {
        final settings = ActiveAssistantSettings(
          quietHoursStartMinutes: 1320, // 22:00
          quietHoursEndMinutes: 480, // 08:00
        );

        // In Sao Paulo (UTC-3):
        // 2026-11-16 21:59 local is UTC 2026-11-17 00:59
        final beforeStart = DateTime.utc(2026, 11, 17, 0, 59);
        expect(settings.isInQuietHours(beforeStart), isFalse);

        // 2026-11-16 22:00 local is UTC 2026-11-17 01:00
        final atStart = DateTime.utc(2026, 11, 17, 1, 0);
        expect(settings.isInQuietHours(atStart), isTrue);

        // 2026-11-17 02:00 local is UTC 2026-11-17 05:00
        final middle = DateTime.utc(2026, 11, 17, 5, 0);
        expect(settings.isInQuietHours(middle), isTrue);

        // 2026-11-17 07:59 local is UTC 2026-11-17 10:59
        final beforeEnd = DateTime.utc(2026, 11, 17, 10, 59);
        expect(settings.isInQuietHours(beforeEnd), isTrue);

        // 2026-11-17 08:00 local is UTC 2026-11-17 11:00
        final atEnd = DateTime.utc(2026, 11, 17, 11, 0);
        expect(settings.isInQuietHours(atEnd), isFalse);
      });

      test('correctly handles daytime interval (02:00 to 06:00)', () {
        final settings = ActiveAssistantSettings(
          quietHoursStartMinutes: 120, // 02:00
          quietHoursEndMinutes: 360, // 06:00
        );

        // In Sao Paulo (UTC-3):
        // 01:59 local is UTC 04:59
        expect(settings.isInQuietHours(DateTime.utc(2026, 11, 16, 4, 59)),
            isFalse);
        // 02:00 local is UTC 05:00
        expect(
            settings.isInQuietHours(DateTime.utc(2026, 11, 16, 5, 0)), isTrue);
        // 05:59 local is UTC 08:59
        expect(
            settings.isInQuietHours(DateTime.utc(2026, 11, 16, 8, 59)), isTrue);
        // 06:00 local is UTC 09:00
        expect(
            settings.isInQuietHours(DateTime.utc(2026, 11, 16, 9, 0)), isFalse);
      });

      test('returns false when start and end minutes are equal', () {
        final settings = ActiveAssistantSettings(
          quietHoursStartMinutes: 300,
          quietHoursEndMinutes: 300,
        );
        expect(
            settings.isInQuietHours(DateTime.utc(2026, 11, 16, 6, 0)), isFalse);
      });
    });

    group('isSilencedAt', () {
      test('silencedUntilIso in future silences even outside quiet hours', () {
        final now = DateTime.utc(
            2026, 11, 16, 15, 0); // 12:00 local (outside quiet hours)
        final settings = ActiveAssistantSettings(
          quietHoursEnabled: true,
          quietHoursStartMinutes: 1320,
          quietHoursEndMinutes: 480,
          silencedUntilIso:
              DateTime.utc(2026, 11, 16, 16, 0).toIso8601String(),
        );

        expect(settings.isSilencedAt(now), isTrue);
      });

      test('silencedUntilIso in past does not silence outside quiet hours', () {
        final now = DateTime.utc(2026, 11, 16, 15, 0); // 12:00 local
        final settings = ActiveAssistantSettings(
          quietHoursEnabled: true,
          quietHoursStartMinutes: 1320,
          quietHoursEndMinutes: 480,
          silencedUntilIso:
              DateTime.utc(2026, 11, 16, 14, 0).toIso8601String(),
        );

        expect(settings.isSilencedAt(now), isFalse);
      });

      test('quiet hours disabled ignores quiet hours window', () {
        final now = DateTime.utc(
            2026, 11, 17, 3, 0); // 00:00 local (in quiet hours window)
        final settings = ActiveAssistantSettings(
          quietHoursEnabled: false,
          quietHoursStartMinutes: 1320,
          quietHoursEndMinutes: 480,
        );

        expect(settings.isSilencedAt(now), isFalse);
      });
    });
  });
}
