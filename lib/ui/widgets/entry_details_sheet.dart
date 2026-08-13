import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'macro_pill.dart';

/// Opens the details sheet for a logged meal or exercise.
Future<void> showEntryDetails(BuildContext context, LogEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EntryDetailsSheet(entry: entry),
  );
}

/// The full breakdown of one timeline entry — time, calories, macros and the
/// per-item / per-set detail for meals and exercises, plus the raw text the
/// entry was parsed from.
class EntryDetailsSheet extends StatelessWidget {
  const EntryDetailsSheet({super.key, required this.entry});

  final LogEntry entry;

  static String _mealLabel(MealType type) => switch (type) {
        MealType.breakfast => 'Breakfast',
        MealType.lunch => 'Lunch',
        MealType.dinner => 'Dinner',
        MealType.snack => 'Snack',
        MealType.meal => 'Meal',
      };

  @override
  Widget build(BuildContext context) {
    final isMeal = entry.type == EntryType.meal;
    final accent = isMeal ? AppColors.jollof : AppColors.ugu;
    final icon =
        isMeal ? Icons.restaurant_rounded : Icons.directions_run_rounded;
    final transcript = entry.rawTranscript.trim();
    // The raw quote matters most for meals, where the parsed items can lose
    // the dish context — a workout's exercise cards already capture what was
    // said, so the "YOU SAID" block is only shown for meals.
    final showTranscript =
        isMeal && transcript.isNotEmpty && transcript != entry.summary.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMeal
                          ? _mealLabel(entry.mealType).toUpperCase()
                          : 'EXERCISE',
                      style: AppText.label(color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.timeOfDay(entry.timestamp),
                      style: AppText.label(color: AppColors.smoke),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(entry.displayTitle, style: AppText.headline()),
          const SizedBox(height: 4),
          Text(
            isMeal
                ? '${Formatters.kcal(entry.calories)} kcal'
                : '${Formatters.kcal(entry.calories)} kcal burned',
            style: AppText.dataL(color: accent),
          ),
          const SizedBox(height: 16),
          if (isMeal) ...[
            _section('MACROS'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                MacroPill(
                  label: 'PROTEIN',
                  value: '${Formatters.grams(entry.proteinG)}g',
                  color: MacroPill.proteinColor,
                ),
                MacroPill(
                  label: 'CARBS',
                  value: '${Formatters.grams(entry.carbsG)}g',
                  color: MacroPill.carbsColor,
                ),
                MacroPill(
                  label: 'FAT',
                  value: '${Formatters.grams(entry.fatG)}g',
                  color: MacroPill.fatColor,
                ),
              ],
            ),
            if (entry.items.isNotEmpty) ...[
              const SizedBox(height: 20),
              _section('IN THIS MEAL'),
              const SizedBox(height: 8),
              for (final item in entry.items) _ItemCard(item: item),
            ],
          ] else if (entry.exerciseItems.length == 1) ...[
            // A single exercise is already summed up by the headline and the
            // kcal line — just surface its structure (duration, sets × reps)
            // as compact chips instead of a one-card section.
            ..._singleExerciseWidgets(entry.exerciseItems.first),
          ] else if (entry.exerciseItems.isNotEmpty) ...[
            _section('IN THIS WORKOUT'),
            const SizedBox(height: 8),
            for (final item in entry.exerciseItems)
              _ExerciseItemCard(item: item),
          ] else if (entry.durationMinutes != null ||
              (entry.sets != null && entry.reps != null)) ...[
            _section('WORKOUT'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (entry.durationMinutes != null)
                  _DetailChip(
                    icon: Icons.schedule_rounded,
                    label: '${Formatters.grams(entry.durationMinutes!)} min',
                  ),
                if (entry.sets != null && entry.reps != null)
                  _DetailChip(
                    icon: Icons.repeat_rounded,
                    label: '${entry.sets} × ${entry.reps} reps',
                  ),
              ],
            ),
          ],
          if (showTranscript) ...[
            const SizedBox(height: 20),
            _section('YOU SAID'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ember),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote_rounded,
                      color: AppColors.smoke, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('“$transcript”', style: AppText.bodyMuted()),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title) =>
      Text(title, style: AppText.label(color: AppColors.smoke));
}

/// The structure chips (duration, sets × reps) for one exercise item, empty
/// when the item carries no structure. Shared by the compact single-exercise
/// form and the per-exercise cards in a multi-exercise workout.
///
/// Natural speech often gives reps without sets ("10 pressups"), so the count
/// shows on its own rather than demanding a full sets × reps pair.
List<Widget> _structureChips(ExerciseItem item) => [
      if (item.reps != null)
        _DetailChip(
          icon: Icons.repeat_rounded,
          label: item.sets != null
              ? '${item.sets} × ${item.reps} reps'
              : '${item.reps} reps',
        ),
      if (item.durationMinutes != null)
        _DetailChip(
          icon: Icons.schedule_rounded,
          label: '${Formatters.grams(item.durationMinutes!)} min',
        ),
    ];

/// The widgets for a workout made of a single exercise: just its structure
/// chips under the header — no "IN THIS WORKOUT" section, since the headline
/// and kcal line already name the exercise and its burn.
List<Widget> _singleExerciseWidgets(ExerciseItem item) {
  final chips = _structureChips(item);
  return [
    if (chips.isNotEmpty) ...[
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: chips),
    ],
  ];
}

/// One parsed food item inside a meal, read-only (quantity + macros).
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final MealItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.barkRaised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: AppText.title(fontSize: 15)),
                  if (item.quantity.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.quantity,
                        style: AppText.bodyMuted(fontSize: 13)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      MacroPill(
                        label: 'PROTEIN',
                        value: '${Formatters.grams(item.proteinG)}g',
                        color: MacroPill.proteinColor,
                      ),
                      MacroPill(
                        label: 'CARBS',
                        value: '${Formatters.grams(item.carbsG)}g',
                        color: MacroPill.carbsColor,
                      ),
                      MacroPill(
                        label: 'FAT',
                        value: '${Formatters.grams(item.fatG)}g',
                        color: MacroPill.fatColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${Formatters.kcal(item.calories)} kcal',
              style: AppText.dataS(color: AppColors.smoke),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact labelled stat chip (duration, sets × reps) for workout entries.
class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.ugu, size: 16),
          const SizedBox(width: 6),
          Text(label, style: AppText.dataS(color: AppColors.bone)),
        ],
      ),
    );
  }
}


/// One exercise inside a logged workout, read-only (sets × reps / duration +
/// its own burn).
class _ExerciseItemCard extends StatelessWidget {
  const _ExerciseItemCard({required this.item});

  final ExerciseItem item;

  @override
  Widget build(BuildContext context) {
    final structure = _structureChips(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.barkRaised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: AppText.title(fontSize: 15)),
                  if (structure.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: structure),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${Formatters.kcal(item.caloriesBurned)} kcal',
              style: AppText.dataS(color: AppColors.smoke),
            ),
          ],
        ),
      ),
    );
  }
}

