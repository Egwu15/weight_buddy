import 'package:flutter_test/flutter_test.dart';

import 'package:weight_buddy/utils/calorie_math.dart';

void main() {
  group('CalorieMath.bmr (Mifflin-St Jeor)', () {
    test('male 70kg, 175cm, 25y', () {
      expect(
        CalorieMath.bmr(
          weightKg: 70,
          heightCm: 175,
          age: 25,
          sex: Sex.male,
        ),
        closeTo(1673.75, 0.001),
      );
    });

    test('female 60kg, 165cm, 30y', () {
      expect(
        CalorieMath.bmr(
          weightKg: 60,
          heightCm: 165,
          age: 30,
          sex: Sex.female,
        ),
        closeTo(1320.25, 0.001),
      );
    });

    test('sex flips the constant between +5 and -161', () {
      final male = CalorieMath.bmr(
          weightKg: 70, heightCm: 175, age: 25, sex: Sex.male);
      final female = CalorieMath.bmr(
          weightKg: 70, heightCm: 175, age: 25, sex: Sex.female);
      expect(male - female, closeTo(166, 0.001));
    });
  });

  group('CalorieMath.maintenance (BMR × activity)', () {
    test('male light: 1673.75 × 1.375', () {
      expect(
        CalorieMath.maintenance(
          weightKg: 70,
          heightCm: 175,
          age: 25,
          sex: Sex.male,
          activity: ActivityLevel.light,
        ),
        closeTo(1673.75 * 1.375, 0.001),
      );
    });

    test('female sedentary: 1320.25 × 1.2', () {
      expect(
        CalorieMath.maintenance(
          weightKg: 60,
          heightCm: 165,
          age: 30,
          sex: Sex.female,
          activity: ActivityLevel.sedentary,
        ),
        closeTo(1320.25 * 1.2, 0.001),
      );
    });

    test('rounds to a whole number the UI would show', () {
      final estimate = CalorieMath.maintenance(
        weightKg: 70,
        heightCm: 175,
        age: 25,
        sex: Sex.male,
        activity: ActivityLevel.light,
      );
      expect(estimate.round(), 2301);
    });

    test('spec regression: male 31y, 87 kg, 168 cm, sedentary → 2,124', () {
      // BMR = 870 + 1050 − 155 + 5 = 1,770; × 1.2 = 2,124. Sedentary must
      // never slip to 1.375 and inflate this toward ~2,450.
      final bmr = CalorieMath.bmr(
        weightKg: 87,
        heightCm: 168,
        age: 31,
        sex: Sex.male,
      );
      expect(bmr, 1770);
      final tdee = CalorieMath.maintenance(
        weightKg: 87,
        heightCm: 168,
        age: 31,
        sex: Sex.male,
        activity: ActivityLevel.sedentary,
      );
      expect(tdee, 2124);
      expect(tdee, lessThan(2200));
    });
  });

  group('enums', () {
    test('activity factors span 1.2 to 1.9', () {
      expect(ActivityLevel.sedentary.factor, 1.2);
      expect(ActivityLevel.veryActive.factor, 1.9);
      expect(ActivityLevel.moderate.factor, 1.55);
    });

    test('fromName round-trips persisted values', () {
      expect(Sex.fromName('male'), Sex.male);
      expect(Sex.fromName('female'), Sex.female);
      expect(Sex.fromName(null), isNull);
      expect(Sex.fromName(''), isNull);
      expect(ActivityLevel.fromName('moderate'), ActivityLevel.moderate);
      expect(ActivityLevel.fromName('nope'), isNull);
    });
  });
}
