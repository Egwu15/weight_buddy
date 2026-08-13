import 'package:flutter_test/flutter_test.dart';

import 'package:weight_buddy/utils/calorie_math.dart';
import 'package:weight_buddy/utils/exercise_math.dart';

void main() {
  group('ExerciseMath.mechanicalKcal (Method 1: mechanical work)', () {
    test('20 dips @ 87 kg lands in the spec’s 6–10 kcal band', () {
      final kcal = ExerciseMath.mechanicalKcal(
        weightKg: 87,
        displacementM: 0.4,
        reps: 20,
      );
      // 87 × 9.81 × 0.4 × 20 = 6,828 J ÷ (4,184 × 0.22) ≈ 7.4 kcal.
      expect(kcal, closeTo(7.42, 0.01));
      expect(kcal, greaterThanOrEqualTo(6));
      expect(kcal, lessThanOrEqualTo(10));
    });

    test('a single 20-rep set never reaches 20 kcal', () {
      final kcal = ExerciseMath.mechanicalKcal(
        weightKg: 87,
        displacementM: 0.4,
        reps: 20,
      );
      expect(kcal, lessThan(20));
    });

    test('push-ups price only the ~65% of bodyweight actually lifted', () {
      final full = ExerciseMath.mechanicalKcal(
        weightKg: 87,
        displacementM: 0.25,
        reps: 20,
      );
      final push = ExerciseMath.mechanicalKcal(
        weightKg: 87,
        displacementM: 0.25,
        effectiveMassFraction: 0.65,
        reps: 20,
      );
      expect(push, closeTo(full * 0.65, 0.001));
      expect(push, closeTo(3.01, 0.01));
    });

    test('pull-ups use the full hang-to-chin displacement', () {
      final kcal = ExerciseMath.mechanicalKcal(
        weightKg: 87,
        displacementM: 0.5,
        reps: 10,
      );
      expect(kcal, closeTo(4.64, 0.01));
    });
  });

  group('ExerciseMath.metKcal (Method 2: MET on precise seconds)', () {
    test('45 s vigorous calisthenics @ 87 kg lands in the 6–10 kcal band', () {
      final kcal = ExerciseMath.metKcal(
        met: ExerciseMath.calisthenicsMet,
        weightKg: 87,
        seconds: 45,
      );
      // 8.0 × 3.5 × 87/200 × 45/60 ≈ 9.1 kcal.
      expect(kcal, closeTo(9.14, 0.01));
      expect(kcal, greaterThanOrEqualTo(6));
      expect(kcal, lessThanOrEqualTo(10));
    });

    test('is priced on the exact seconds, not a rounded-up minute block', () {
      final oneMinute = ExerciseMath.metKcal(
        met: ExerciseMath.calisthenicsMet,
        weightKg: 87,
        seconds: 60,
      );
      final fiveMinutes = ExerciseMath.metKcal(
        met: ExerciseMath.calisthenicsMet,
        weightKg: 87,
        seconds: 300,
      );
      // A 45-second set must cost 45/60 of a minute, not a full 5-minute
      // block — the classic tracker inflation bug.
      expect(fiveMinutes, closeTo(oneMinute * 5, 0.001));
      expect(
        ExerciseMath.metKcal(
          met: ExerciseMath.calisthenicsMet,
          weightKg: 87,
          seconds: 45,
        ),
        closeTo(oneMinute * 0.75, 0.001),
      );
    });
  });

  group('ExerciseMath.burnForExercise (routing)', () {
    test('reps win over duration — mechanical work is the ground truth', () {
      final kcal = ExerciseMath.burnForExercise(
        name: 'Dips',
        weightKg: 87,
        reps: 20,
        durationMinutes: 1,
      );
      expect(kcal, closeTo(7.42, 0.01));
    });

    test('sets multiply the mechanical cost', () {
      // 3 × 10 pull-ups = 30 reps at 0.5 m full bodyweight.
      final kcal = ExerciseMath.burnForExercise(
        name: 'Pull-ups',
        weightKg: 87,
        sets: 3,
        reps: 10,
      );
      expect(kcal, closeTo(13.91, 0.01));
      expect(kcal, lessThan(20));
    });

    test('duration-only entries use MET on precise minutes', () {
      final kcal = ExerciseMath.burnForExercise(
        name: 'Brisk walk',
        weightKg: 87,
        durationMinutes: 45,
      );
      // Walking ≈ 4.3 MET → 4.3 × 3.5 × 87 / 200 × 45.
      expect(kcal, closeTo(4.3 * 3.5 * 87 / 200 * 45, 0.001));
    });

    test('unknown rep movements use the conservative generic displacement', () {
      final kcal = ExerciseMath.burnForExercise(
        name: 'Some random movement',
        weightKg: 87,
        reps: 20,
      );
      expect(kcal, closeTo(7.42, 0.01));
    });

    test('nothing known is an honest 0, never an invented number', () {
      expect(ExerciseMath.burnForExercise(name: 'Dips', weightKg: 87), 0);
      expect(
        ExerciseMath.burnForExercise(
          name: 'Dips',
          weightKg: 87,
          reps: 0,
          durationMinutes: null,
        ),
        0,
      );
    });

    test('mis-parsed absurd reps are capped per set', () {
      final kcal = ExerciseMath.burnForExercise(
        name: 'Dips',
        weightKg: 87,
        reps: 500,
      );
      expect(kcal, lessThanOrEqualTo(ExerciseMath.maxKcalPerSet));
    });
  });

  group('BodyweightMovement.fromName', () {
    test('recognises the spec’s three movements and their variants', () {
      expect(BodyweightMovement.fromName('Dips'), BodyweightMovement.dips);
      expect(BodyweightMovement.fromName('20 dips'), BodyweightMovement.dips);
      expect(
        BodyweightMovement.fromName('Pull-ups'),
        BodyweightMovement.pullUps,
      );
      expect(
        BodyweightMovement.fromName('Chin-ups'),
        BodyweightMovement.pullUps,
      );
      expect(
        BodyweightMovement.fromName('Knee Press-ups'),
        BodyweightMovement.pushUps,
      );
      expect(
        BodyweightMovement.fromName('Push-ups'),
        BodyweightMovement.pushUps,
      );
      expect(
        BodyweightMovement.fromName('Bodyweight Squat'),
        BodyweightMovement.squats,
      );
    });

    test('cardio names are not mis-classified as strength movements', () {
      expect(BodyweightMovement.fromName('Treadmill run'), isNull);
      expect(BodyweightMovement.fromName(null), isNull);
    });
  });

  group('ExerciseMath.metForName', () {
    test(
      'common cardio is priced by its own MET, not the calisthenics default',
      () {
        expect(ExerciseMath.metForName('Treadmill run'), 9.8);
        expect(ExerciseMath.metForName('Brisk walk'), 4.3);
        expect(ExerciseMath.metForName('Cycle at the gym'), 7.5);
        expect(ExerciseMath.metForName('Bodyweight strength circuit'), 8.0);
        expect(ExerciseMath.metForName('Unknown session'), 8.0);
      },
    );
  });

  group('TDEE spec regression (calorie_math)', () {
    test('Male, 31y, 87 kg, 168 cm, sedentary → BMR 1,770 / TDEE 2,124', () {
      final bmr = CalorieMath.bmr(
        weightKg: 87,
        heightCm: 168,
        age: 31,
        sex: Sex.male,
      );
      expect(bmr, closeTo(1770, 0.001));
      final tdee = CalorieMath.maintenance(
        weightKg: 87,
        heightCm: 168,
        age: 31,
        sex: Sex.male,
        activity: ActivityLevel.sedentary,
      );
      expect(tdee, closeTo(2124, 0.001));
    });
  });
}
