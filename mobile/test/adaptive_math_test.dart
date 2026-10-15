import 'package:flutter_test/flutter_test.dart';

import 'package:weight_buddy/models/weigh_in.dart';
import 'package:weight_buddy/utils/adaptive_math.dart';

void main() {
  final now = DateTime(2026, 8, 13);

  WeighIn w(DateTime date, double kg) => WeighIn(date: date, weightKg: kg);

  group('AdaptiveMath.observedMaintenance', () {
    test('weight loss over 21 days with steady intake', () {
      final start = now.subtract(const Duration(days: 21));
      final weighIns = [w(now, 83.0), w(start, 85.0)];
      final intake = <DateTime, double>{};
      // 2200 kcal/day on every day between the two weigh-ins.
      for (var d = 0; d <= 21; d++) {
        intake[start.add(Duration(days: d))] = 2200;
      }
      // window = 22 inclusive days, Δkg = −2:
      // observed = 2200 + (−2 × 7700) / 22 = 2200 − 700 = 1500.
      final observed = AdaptiveMath.observedMaintenance(
        weighIns: weighIns,
        dailyIntakeKcal: intake,
        now: now,
      );
      expect(observed, closeTo(1500, 0.001));
    });

    test('returns null when the weigh-ins are too close together', () {
      final weighIns = [
        w(now, 83.0),
        w(now.subtract(const Duration(days: 5)), 85.0),
      ];
      expect(
        AdaptiveMath.observedMaintenance(
          weighIns: weighIns,
          dailyIntakeKcal: const {},
          now: now,
        ),
        isNull,
      );
    });

    test('returns null without enough logged food days', () {
      final start = now.subtract(const Duration(days: 20));
      final weighIns = [w(now, 83.0), w(start, 85.0)];
      expect(
        AdaptiveMath.observedMaintenance(
          weighIns: weighIns,
          dailyIntakeKcal: {start: 2200},
          now: now,
        ),
        isNull,
      );
    });

    test('ignores weigh-ins outside the lookback window', () {
      final old = now.subtract(const Duration(days: 90));
      final weighIns = [w(old, 80.0), w(now, 83.0)];
      expect(
        AdaptiveMath.observedMaintenance(
          weighIns: weighIns,
          dailyIntakeKcal: const {},
          now: now,
        ),
        isNull,
      );
    });
  });

  group('AdaptiveMath.clampToFormula', () {
    test('bounds the observed value to ±15% of the formula', () {
      // Inside the band → unchanged.
      expect(AdaptiveMath.clampToFormula(2100, 2124), closeTo(2100, 0.001));
      // Too low → clamped up to 85% of the formula.
      expect(
        AdaptiveMath.clampToFormula(1500, 2124),
        closeTo(2124 * 0.85, 0.001),
      );
      // Too high → clamped down to 115% of the formula.
      expect(
        AdaptiveMath.clampToFormula(3000, 2124),
        closeTo(2124 * 1.15, 0.001),
      );
    });
  });
}
