import '../models/log_entry.dart';

/// Consecutive-day records for the calendar header.
class Streaks {
  const Streaks({this.logging = 0, this.onPlan = 0});

  /// Consecutive days ending today with at least one log entry.
  final int logging;

  /// Consecutive days ending today that were both logged and at or under
  /// maintenance calories.
  final int onPlan;
}

/// Walks backwards from [today] through [perDay] counting streaks.
///
/// A logging day has any entry; an on-plan day must also have
/// `netKcal <= maintenanceKcal`. A missing day breaks both streaks.
Streaks computeStreaks(
  Map<DateTime, LogTotals> perDay,
  DateTime today,
  double maintenanceKcal,
) {
  var logging = 0, onPlan = 0;
  var d = DateTime(today.year, today.month, today.day);
  for (var i = 0; i < 366; i++) {
    final totals = perDay[d];
    if (totals == null) break;
    logging++;
    if (totals.netKcal <= maintenanceKcal) onPlan++;
    d = d.subtract(const Duration(days: 1));
  }
  return Streaks(logging: logging, onPlan: onPlan);
}
