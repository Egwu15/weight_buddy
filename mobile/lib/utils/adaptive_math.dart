library;

import '../models/weigh_in.dart';

/// Adaptive ("smart") maintenance estimate read from the user's own data —
/// the flip side of the formula. Instead of predicting from height, age, sex
/// and activity, it asks what the body actually did:
///
///   observed = average daily intake + (weight change kg × 7,700) / days
///
/// Logged workouts are already inside the weight trend (training shows up as
/// less weight gain / more loss), so exercise burn is never double-counted.

/// Daily food intake keyed by local-midnight day.
typedef DailyIntake = Map<DateTime, double>;

abstract final class AdaptiveMath {
  /// 7,700 kcal ≈ 1 kg of body tissue — the standard energy-equivalence
  /// constant that turns a weight trend into a calorie correction.
  static const kcalPerKg = 7700;

  /// The observed daily maintenance, or null when there isn't enough logging
  /// yet to trust it. Requires at least [minSpanDays] between the first and
  /// last weigh-in in the window and at least [minLoggedDays] of food logs
  /// in between, so a couple of lucky days can never rewrite the target.
  ///
  /// [weighIns] is the full list (newest-first, as stored); only the most
  /// recent [lookbackDays] ending at [now] are considered.
  static double? observedMaintenance({
    required List<WeighIn> weighIns,
    required DailyIntake dailyIntakeKcal,
    required DateTime now,
    int lookbackDays = 60,
    int minSpanDays = 14,
    int minLoggedDays = 10,
  }) {
    final start = now.subtract(Duration(days: lookbackDays));
    final inWindow = weighIns
        .where((w) => !w.date.isBefore(start) && !w.date.isAfter(now))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (inWindow.length < 2) return null;

    final first = inWindow.first;
    final last = inWindow.last;
    final spanDays = last.date.difference(first.date).inDays;
    if (spanDays < minSpanDays) return null;

    var totalKcal = 0.0;
    var loggedDays = 0;
    for (var d = 0; d <= spanDays; d++) {
      final kcal = dailyIntakeKcal[first.date.add(Duration(days: d))];
      if (kcal != null) {
        totalKcal += kcal;
        loggedDays++;
      }
    }
    if (loggedDays < minLoggedDays) return null;

    final windowDays = spanDays + 1; // inclusive of both weigh-ins
    final avgIntake = totalKcal / windowDays;
    final weightChangeKg = last.weightKg - first.weightKg;
    return avgIntake + weightChangeKg * kcalPerKg / windowDays;
  }

  /// Clamps an observed estimate to ±[margin] of the formula estimate, so
  /// the smart number refines the profile target instead of drifting wildly
  /// from it (a skipped week of logging can never halve or double it).
  static double clampToFormula(
    double observed,
    double formula, {
    double margin = 0.15,
  }) {
    final low = formula * (1 - margin);
    final high = formula * (1 + margin);
    return observed.clamp(low, high).toDouble();
  }
}
