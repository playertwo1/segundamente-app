import 'package:memex/domain/models/active_assistant_settings.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/use_cases/todo_schedule_calculator.dart';

/// Enforces frequency limits and quiet hours for persona-initiated task suggestions.
class PersonaSuggestionGovernor {
  const PersonaSuggestionGovernor._();

  static bool canSuggestNow({
    required DateTime now,
    required ActiveAssistantSettings settings,
    required List<DateTime> recentSuggestionTimestamps,
    Duration minSpacing = const Duration(hours: 2),
    String timeZone = todoTimeZone,
  }) {
    if (!settings.personaSuggestionsEnabled ||
        settings.isSilencedAt(now, timeZone: timeZone)) {
      return false;
    }

    final localNow = TodoScheduleCalculator.dateTimeInTimeZone(now, timeZone);
    var todayCount = 0;

    for (final t in recentSuggestionTimestamps) {
      final localT = TodoScheduleCalculator.dateTimeInTimeZone(t, timeZone);
      final isSameLocalDate = localT.year == localNow.year &&
          localT.month == localNow.month &&
          localT.day == localNow.day;

      if (isSameLocalDate) {
        todayCount++;
        if (!now.isBefore(t) && now.difference(t) < minSpacing) {
          return false;
        }
      }
    }

    if (todayCount >= settings.maxPersonaSuggestionsPerDay) {
      return false;
    }

    return true;
  }
}
