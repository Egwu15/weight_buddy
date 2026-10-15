import 'package:flutter_test/flutter_test.dart';

import 'package:weight_buddy/models/log_entry.dart';

/// A workout entry with the exercises nested underneath, like the GPT parser
/// builds one.
LogEntry _workout({
  required String summary,
  List<ExerciseItem> items = const [],
}) =>
    LogEntry(
      timestamp: 0,
      type: EntryType.exercise,
      summary: summary,
      calories: items.fold(0.0, (s, e) => s + e.caloriesBurned),
      proteinG: 0,
      carbsG: 0,
      fatG: 0,
      rawTranscript: summary,
      exerciseItems: items,
    );

void main() {
  group('LogEntry.displayTitle', () {
    test('meals always use the spoken summary', () {
      const meal = LogEntry(
        timestamp: 0,
        type: EntryType.meal,
        summary: 'Jollof rice with 2 pieces fried chicken and fried plantain',
        calories: 1350,
        proteinG: 53.5,
        carbsG: 158,
        fatG: 50,
        rawTranscript: 'I had two plates of jollof rice',
      );
      expect(
        meal.displayTitle,
        'Jollof rice with 2 pieces fried chicken and fried plantain',
      );
    });

    test('a single-exercise workout uses the exercise name', () {
      final workout = _workout(
        summary: '5 knee press-ups and 5 dips',
        items: const [
          ExerciseItem(name: 'Knee Press-ups', sets: 1, reps: 5, caloriesBurned: 1),
        ],
      );
      expect(workout.displayTitle, 'Knee Press-ups');
    });

    test('a two-exercise workout reads "First + 1 more"', () {
      final workout = _workout(
        summary: '5 knee press-ups and 5 dips',
        items: const [
          ExerciseItem(name: 'Knee Press-ups', sets: 1, reps: 5, caloriesBurned: 1),
          ExerciseItem(name: 'Dips', sets: 1, reps: 5, caloriesBurned: 2),
        ],
      );
      expect(workout.displayTitle, 'Knee Press-ups + 1 more');
    });

    test('a three-exercise circuit reads "First + 2 more"', () {
      final workout = _workout(
        summary: 'Leg day: squats, lunges and deadlifts',
        items: const [
          ExerciseItem(name: 'Bodyweight squats', sets: 3, reps: 12, caloriesBurned: 70),
          ExerciseItem(name: 'Walking lunges', sets: 3, reps: 10, caloriesBurned: 80),
          ExerciseItem(name: 'Romanian deadlifts', reps: 10, caloriesBurned: 90),
        ],
      );
      expect(workout.displayTitle, 'Bodyweight squats + 2 more');
    });

    test('falls back to the summary when the first exercise name is blank', () {
      final workout = _workout(
        summary: 'ran for 30 minutes',
        items: const [
          ExerciseItem(name: '  ', durationMinutes: 30, caloriesBurned: 240),
        ],
      );
      expect(workout.displayTitle, 'ran for 30 minutes');
    });

    test('legacy exercises without nested items use the summary', () {
      final legacy = _workout(summary: 'Treadmill run');
      expect(legacy.displayTitle, 'Treadmill run');
    });
  });
}
