/// Mifflin-St Jeor BMR plus activity factors — the numbers behind the
/// maintenance-calorie estimate.
library;

/// Biological sex used by the Mifflin-St Jeor constants. Asked once on the
/// first launch and editable later in Settings → Targets.
enum Sex {
  male('Male'),
  female('Female');

  const Sex(this.label);

  /// Human-readable label.
  final String label;

  /// Parses a stored setting value back into an enum, or null when absent.
  static Sex? fromName(String? name) => Sex.values.asNameMap()[name?.trim() ?? ''];
}

/// Average physical activity for the week. The factor scales BMR up to total
/// daily energy expenditure (TDEE).
enum ActivityLevel {
  sedentary(1.2, 'Mostly sitting', 'Desk or indoor work, little walking'),
  light(1.375, 'Lightly active', 'Walking or light exercise 1–3× a week'),
  moderate(1.55, 'Moderately active', 'Exercise or sports 3–5× a week'),
  active(1.725, 'Active', 'Hard exercise or sports 6–7× a week'),
  veryActive(1.9, 'Very active', 'Hard daily training or a physical job');

  const ActivityLevel(this.factor, this.label, this.description);

  /// TDEE multiplier for this activity level.
  final double factor;

  final String label;
  final String description;

  /// Parses a stored setting value back into an enum, or null when absent.
  static ActivityLevel? fromName(String? name) =>
      ActivityLevel.values.asNameMap()[name?.trim() ?? ''];
}

/// Pure calorie math. No I/O — trivially unit-testable.
abstract final class CalorieMath {
  /// Basal metabolic rate via Mifflin-St Jeor:
  ///
  ///   men:   10·kg + 6.25·cm − 5·age + 5
  ///   women: 10·kg + 6.25·cm − 5·age − 161
  static double bmr({
    required double weightKg,
    required double heightCm,
    required int age,
    required Sex sex,
  }) {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return base + (sex == Sex.male ? 5 : -161);
  }

  /// Estimated daily maintenance calories: BMR × activity factor.
  static double maintenance({
    required double weightKg,
    required double heightCm,
    required int age,
    required Sex sex,
    required ActivityLevel activity,
  }) {
    return bmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      sex: sex,
    ) *
        activity.factor;
  }
}
