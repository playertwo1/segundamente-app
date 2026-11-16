import 'package:memex/domain/models/todo_item.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ActiveAssistantSettings {
  ActiveAssistantSettings({
    this.morningBriefingEnabled = true,
    this.morningBriefingMinutes = 540,
    this.afternoonBriefingEnabled = true,
    this.afternoonBriefingMinutes = 840,
    this.stalledReminderEnabled = true,
    this.stalledThresholdDays = 3,
    this.personaSuggestionsEnabled = true,
    this.maxPersonaSuggestionsPerDay = 2,
    this.quietHoursEnabled = true,
    this.quietHoursStartMinutes = 1320,
    this.quietHoursEndMinutes = 480,
    String? silencedUntilIso,
  }) : silencedUntilIso = _normalizeSilencedUntil(silencedUntilIso) {
    if (morningBriefingMinutes < 0 || morningBriefingMinutes >= 1440) {
      throw ArgumentError.value(
        morningBriefingMinutes,
        'morningBriefingMinutes',
        'morningBriefingMinutes must be between 0 and 1439',
      );
    }
    if (afternoonBriefingMinutes < 0 || afternoonBriefingMinutes >= 1440) {
      throw ArgumentError.value(
        afternoonBriefingMinutes,
        'afternoonBriefingMinutes',
        'afternoonBriefingMinutes must be between 0 and 1439',
      );
    }
    if (stalledThresholdDays < 1 || stalledThresholdDays > 30) {
      throw ArgumentError.value(
        stalledThresholdDays,
        'stalledThresholdDays',
        'stalledThresholdDays must be between 1 and 30',
      );
    }
    if (maxPersonaSuggestionsPerDay < 1 || maxPersonaSuggestionsPerDay > 10) {
      throw ArgumentError.value(
        maxPersonaSuggestionsPerDay,
        'maxPersonaSuggestionsPerDay',
        'maxPersonaSuggestionsPerDay must be between 1 and 10',
      );
    }
    if (quietHoursStartMinutes < 0 || quietHoursStartMinutes >= 1440) {
      throw ArgumentError.value(
        quietHoursStartMinutes,
        'quietHoursStartMinutes',
        'quietHoursStartMinutes must be between 0 and 1439',
      );
    }
    if (quietHoursEndMinutes < 0 || quietHoursEndMinutes >= 1440) {
      throw ArgumentError.value(
        quietHoursEndMinutes,
        'quietHoursEndMinutes',
        'quietHoursEndMinutes must be between 0 and 1439',
      );
    }
  }

  static ActiveAssistantSettings get defaults => ActiveAssistantSettings();

  final bool morningBriefingEnabled;
  final int morningBriefingMinutes;
  final bool afternoonBriefingEnabled;
  final int afternoonBriefingMinutes;
  final bool stalledReminderEnabled;
  final int stalledThresholdDays;
  final bool personaSuggestionsEnabled;
  final int maxPersonaSuggestionsPerDay;
  final bool quietHoursEnabled;
  final int quietHoursStartMinutes;
  final int quietHoursEndMinutes;
  final String? silencedUntilIso;

  static bool _timeZonesInitialized = false;

  static tz.Location _location(String name) {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      return tz.getLocation(todoTimeZone);
    }
  }

  static String? _normalizeSilencedUntil(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      throw ArgumentError.value(
        value,
        'silencedUntilIso',
        'silencedUntilIso must be a valid ISO-8601 string or null',
      );
    }
    return trimmed;
  }

  ActiveAssistantSettings copyWith({
    bool? morningBriefingEnabled,
    int? morningBriefingMinutes,
    bool? afternoonBriefingEnabled,
    int? afternoonBriefingMinutes,
    bool? stalledReminderEnabled,
    int? stalledThresholdDays,
    bool? personaSuggestionsEnabled,
    int? maxPersonaSuggestionsPerDay,
    bool? quietHoursEnabled,
    int? quietHoursStartMinutes,
    int? quietHoursEndMinutes,
    String? silencedUntilIso,
    bool clearSilencedUntil = false,
  }) =>
      ActiveAssistantSettings(
        morningBriefingEnabled:
            morningBriefingEnabled ?? this.morningBriefingEnabled,
        morningBriefingMinutes:
            morningBriefingMinutes ?? this.morningBriefingMinutes,
        afternoonBriefingEnabled:
            afternoonBriefingEnabled ?? this.afternoonBriefingEnabled,
        afternoonBriefingMinutes:
            afternoonBriefingMinutes ?? this.afternoonBriefingMinutes,
        stalledReminderEnabled:
            stalledReminderEnabled ?? this.stalledReminderEnabled,
        stalledThresholdDays:
            stalledThresholdDays ?? this.stalledThresholdDays,
        personaSuggestionsEnabled:
            personaSuggestionsEnabled ?? this.personaSuggestionsEnabled,
        maxPersonaSuggestionsPerDay:
            maxPersonaSuggestionsPerDay ?? this.maxPersonaSuggestionsPerDay,
        quietHoursEnabled:
            quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStartMinutes:
            quietHoursStartMinutes ?? this.quietHoursStartMinutes,
        quietHoursEndMinutes:
            quietHoursEndMinutes ?? this.quietHoursEndMinutes,
        silencedUntilIso: clearSilencedUntil
            ? null
            : (silencedUntilIso ?? this.silencedUntilIso),
      );

  Map<String, dynamic> toJson() => {
        'morning_briefing_enabled': morningBriefingEnabled,
        'morning_briefing_minutes': morningBriefingMinutes,
        'afternoon_briefing_enabled': afternoonBriefingEnabled,
        'afternoon_briefing_minutes': afternoonBriefingMinutes,
        'stalled_reminder_enabled': stalledReminderEnabled,
        'stalled_threshold_days': stalledThresholdDays,
        'persona_suggestions_enabled': personaSuggestionsEnabled,
        'max_persona_suggestions_per_day': maxPersonaSuggestionsPerDay,
        'quiet_hours_enabled': quietHoursEnabled,
        'quiet_hours_start_minutes': quietHoursStartMinutes,
        'quiet_hours_end_minutes': quietHoursEndMinutes,
        if (silencedUntilIso != null) 'silenced_until_iso': silencedUntilIso,
      };

  static ActiveAssistantSettings fromJson(Map<String, dynamic> json) {
    final rawMorningEnabled = json['morning_briefing_enabled'];
    final rawMorningMinutes = json['morning_briefing_minutes'];
    final rawAfternoonEnabled = json['afternoon_briefing_enabled'];
    final rawAfternoonMinutes = json['afternoon_briefing_minutes'];
    final rawStalledEnabled = json['stalled_reminder_enabled'];
    final rawStalledDays = json['stalled_threshold_days'];
    final rawPersonaEnabled = json['persona_suggestions_enabled'];
    final rawMaxSuggestions = json['max_persona_suggestions_per_day'];
    final rawQuietEnabled = json['quiet_hours_enabled'];
    final rawQuietStart = json['quiet_hours_start_minutes'];
    final rawQuietEnd = json['quiet_hours_end_minutes'];
    final rawSilenced = json['silenced_until_iso'];

    if (rawMorningEnabled != null && rawMorningEnabled is! bool) {
      throw const FormatException('morning_briefing_enabled is malformed');
    }
    if (rawMorningMinutes != null && rawMorningMinutes is! num) {
      throw const FormatException('morning_briefing_minutes is malformed');
    }
    if (rawAfternoonEnabled != null && rawAfternoonEnabled is! bool) {
      throw const FormatException('afternoon_briefing_enabled is malformed');
    }
    if (rawAfternoonMinutes != null && rawAfternoonMinutes is! num) {
      throw const FormatException('afternoon_briefing_minutes is malformed');
    }
    if (rawStalledEnabled != null && rawStalledEnabled is! bool) {
      throw const FormatException('stalled_reminder_enabled is malformed');
    }
    if (rawStalledDays != null && rawStalledDays is! num) {
      throw const FormatException('stalled_threshold_days is malformed');
    }
    if (rawPersonaEnabled != null && rawPersonaEnabled is! bool) {
      throw const FormatException('persona_suggestions_enabled is malformed');
    }
    if (rawMaxSuggestions != null && rawMaxSuggestions is! num) {
      throw const FormatException(
          'max_persona_suggestions_per_day is malformed');
    }
    if (rawQuietEnabled != null && rawQuietEnabled is! bool) {
      throw const FormatException('quiet_hours_enabled is malformed');
    }
    if (rawQuietStart != null && rawQuietStart is! num) {
      throw const FormatException('quiet_hours_start_minutes is malformed');
    }
    if (rawQuietEnd != null && rawQuietEnd is! num) {
      throw const FormatException('quiet_hours_end_minutes is malformed');
    }
    if (rawSilenced != null && rawSilenced is! String) {
      throw const FormatException('silenced_until_iso is malformed');
    }

    try {
      return ActiveAssistantSettings(
        morningBriefingEnabled: rawMorningEnabled as bool? ?? true,
        morningBriefingMinutes: (rawMorningMinutes as num?)?.toInt() ?? 540,
        afternoonBriefingEnabled: rawAfternoonEnabled as bool? ?? true,
        afternoonBriefingMinutes: (rawAfternoonMinutes as num?)?.toInt() ?? 840,
        stalledReminderEnabled: rawStalledEnabled as bool? ?? true,
        stalledThresholdDays: (rawStalledDays as num?)?.toInt() ?? 3,
        personaSuggestionsEnabled: rawPersonaEnabled as bool? ?? true,
        maxPersonaSuggestionsPerDay: (rawMaxSuggestions as num?)?.toInt() ?? 2,
        quietHoursEnabled: rawQuietEnabled as bool? ?? true,
        quietHoursStartMinutes: (rawQuietStart as num?)?.toInt() ?? 1320,
        quietHoursEndMinutes: (rawQuietEnd as num?)?.toInt() ?? 480,
        silencedUntilIso: rawSilenced as String?,
      );
    } on ArgumentError catch (e) {
      throw FormatException(
          'Active assistant settings are out of range: ${e.message}');
    }
  }

  bool isInQuietHours(DateTime now, {String timeZone = todoTimeZone}) {
    if (quietHoursStartMinutes == quietHoursEndMinutes) return false;
    final local = tz.TZDateTime.from(now, _location(timeZone));
    final localMinutes = local.hour * 60 + local.minute;
    if (quietHoursStartMinutes < quietHoursEndMinutes) {
      return localMinutes >= quietHoursStartMinutes &&
          localMinutes < quietHoursEndMinutes;
    } else {
      return localMinutes >= quietHoursStartMinutes ||
          localMinutes < quietHoursEndMinutes;
    }
  }

  bool isSilencedAt(DateTime now, {String timeZone = todoTimeZone}) {
    if (silencedUntilIso != null) {
      final silenced = DateTime.tryParse(silencedUntilIso!);
      if (silenced != null && silenced.isAfter(now)) {
        return true;
      }
    }
    return quietHoursEnabled && isInQuietHours(now, timeZone: timeZone);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveAssistantSettings &&
          runtimeType == other.runtimeType &&
          morningBriefingEnabled == other.morningBriefingEnabled &&
          morningBriefingMinutes == other.morningBriefingMinutes &&
          afternoonBriefingEnabled == other.afternoonBriefingEnabled &&
          afternoonBriefingMinutes == other.afternoonBriefingMinutes &&
          stalledReminderEnabled == other.stalledReminderEnabled &&
          stalledThresholdDays == other.stalledThresholdDays &&
          personaSuggestionsEnabled == other.personaSuggestionsEnabled &&
          maxPersonaSuggestionsPerDay == other.maxPersonaSuggestionsPerDay &&
          quietHoursEnabled == other.quietHoursEnabled &&
          quietHoursStartMinutes == other.quietHoursStartMinutes &&
          quietHoursEndMinutes == other.quietHoursEndMinutes &&
          silencedUntilIso == other.silencedUntilIso;

  @override
  int get hashCode => Object.hash(
        morningBriefingEnabled,
        morningBriefingMinutes,
        afternoonBriefingEnabled,
        afternoonBriefingMinutes,
        stalledReminderEnabled,
        stalledThresholdDays,
        personaSuggestionsEnabled,
        maxPersonaSuggestionsPerDay,
        quietHoursEnabled,
        quietHoursStartMinutes,
        quietHoursEndMinutes,
        silencedUntilIso,
      );
}
