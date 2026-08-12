import '../models/log_entry.dart';

/// Picks the daily-nudge text from what's been logged today, or returns null
/// when the day looks complete and no nudge is needed.
///
/// Rules:
///  - nothing logged -> the standard "what did you eat" nudge;
///  - any of breakfast/lunch/dinner missing (snacks never fill a slot) ->
///    "Anything else today? (...)";
///  - meals complete but no exercise -> "Did you get your workout in?";
///  - otherwise (meals + workout logged) -> null (stay quiet).
String? nudgeMessage(List<LogEntry> logs) {
  if (logs.isEmpty) {
    return 'Time to log — what did you eat today?';
  }
  var hasBreakfast = false, hasLunch = false, hasDinner = false;
  var hasWorkout = false;
  for (final e in logs) {
    switch (e.mealType) {
      case MealType.breakfast:
        hasBreakfast = true;
      case MealType.lunch:
        hasLunch = true;
      case MealType.dinner:
        hasDinner = true;
      case MealType.snack:
        break; // snacks never fill a meal slot
      case MealType.meal:
        break; // unknown/legacy: not a specific slot
    }
    if (e.type == EntryType.exercise) hasWorkout = true;
  }
  final missing = <String>[
    if (!hasBreakfast) 'breakfast',
    if (!hasLunch) 'lunch',
    if (!hasDinner) 'dinner',
  ];
  if (missing.isNotEmpty) {
    final names = missing.length > 2
        ? '${missing.sublist(0, missing.length - 1).join(', ')} and '
            '${missing.last}'
        : missing.join(' and ');
    return 'Anything else today? ($names still open)';
  }
  if (!hasWorkout) {
    return 'Did you get your workout in?';
  }
  return null;
}
