/// Period arithmetic for the weekly / monthly calorie views.
///
/// Weeks start on Monday, matching the calendar grid's weekday header.
library;

/// The Monday that starts the week containing [day].
DateTime startOfWeek(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// The first day of the month containing [day].
DateTime startOfMonth(DateTime day) => DateTime(day.year, day.month, 1);
