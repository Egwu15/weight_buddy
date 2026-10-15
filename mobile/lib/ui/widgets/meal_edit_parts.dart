import 'package:flutter/material.dart';

import '../../data/openai_service.dart';
import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'macro_pill.dart';

/// Pieces shared by every screen that shows or edits a parsed meal/workout:
/// the record sheet's confirm step, the entry editor and the details sheet.

String mealTypeLabel(MealType type) => switch (type) {
      MealType.breakfast => 'Breakfast',
      MealType.lunch => 'Lunch',
      MealType.dinner => 'Dinner',
      MealType.snack => 'Snack',
      MealType.meal => 'Meal',
    };

/// "3 × 10 reps · 20 min · 140 kcal burned" for one parsed exercise.
String exerciseSubtitle(ParsedExercise exercise) {
  final duration = exercise.durationMinutes;
  // Natural speech often gives reps without sets ("10 pressups") — show
  // whatever structure the speaker actually gave.
  final parts = <String>[
    if (exercise.sets != null && exercise.reps != null)
      '${exercise.sets} × ${exercise.reps} reps'
    else if (exercise.reps != null)
      '${exercise.reps} reps',
    if (duration != null) '${Formatters.grams(duration)} min',
    '${Formatters.kcal(exercise.caloriesBurned)} kcal burned',
  ];
  return parts.join(' · ');
}

/// The quantity field for one meal item. Calories and macros scale with the
/// number typed, so "3 eggs" → "2 eggs" takes a third off.
///
/// Scaling is always relative to [base], the item as it arrived, never to the
/// previous keystroke: clearing the field midway ("3" → "" → "2") would
/// otherwise lose the reference number and scale against 1.
class MealQuantityController extends TextEditingController {
  MealQuantityController(this.base) : super(text: base.quantity);

  final MealItem base;

  static final _number = RegExp(r'\d+(?:\.\d+)?');

  static double? _leadingNumber(String text) {
    final m = _number.firstMatch(text);
    return m == null ? null : double.tryParse(m.group(0)!);
  }

  /// [base] rescaled to the quantity in [raw], or null when [raw] says zero
  /// (a half-typed "0.5" must not wipe the item's numbers on the way).
  MealItem? scaledTo(String raw) {
    final newV = _leadingNumber(raw);
    final baseV = _leadingNumber(base.quantity) ?? 1;
    if (newV != null && newV <= 0) return null;
    final factor = newV == null || baseV <= 0 ? 1.0 : newV / baseV;
    return MealItem(
      name: base.name,
      quantity: raw,
      calories: base.calories * factor,
      proteinG: base.proteinG * factor,
      carbsG: base.carbsG * factor,
      fatG: base.fatG * factor,
    );
  }
}

/// The running total for a meal being confirmed or edited.
class MealTotalsRow extends StatelessWidget {
  const MealTotalsRow({
    super.key,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ember),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TOTAL', style: AppText.label()),
              const Spacer(),
              Text(
                '${Formatters.kcal(calories)} kcal',
                style: AppText.dataL(color: AppColors.jollof),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              MacroPill(
                label: 'PROTEIN',
                value: '${Formatters.grams(protein)}g',
                color: MacroPill.proteinColor,
              ),
              MacroPill(
                label: 'CARBS',
                value: '${Formatters.grams(carbs)}g',
                color: MacroPill.carbsColor,
              ),
              MacroPill(
                label: 'FAT',
                value: '${Formatters.grams(fat)}g',
                color: MacroPill.fatColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
