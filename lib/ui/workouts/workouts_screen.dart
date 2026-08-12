import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/exercise_recommendation.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'log_exercise_sheet.dart';

/// The auto-saved exercise library: every recommendation the coach made,
/// referenceable without hunting through chat.
class WorkoutsScreen extends ConsumerWidget {
  const WorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(exercisesProvider);
    final exercises = exercisesAsync.value ?? const <ExerciseRecommendation>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.pot,
        title: Text('Workouts', style: AppText.title()),
      ),
      body: exercises.isEmpty
          ? const _EmptyWorkouts()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: exercises.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) =>
                  _ExerciseCard(exercise: exercises[i]),
            ),
    );
  }
}

class _EmptyWorkouts extends StatelessWidget {
  const _EmptyWorkouts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center_outlined,
                color: AppColors.smoke, size: 28),
            const SizedBox(height: 10),
            Text('No saved workouts yet', style: AppText.title()),
            const SizedBox(height: 4),
            Text(
              'Ask the coach for an exercise plan and every concrete '
              'recommendation lands here automatically.',
              textAlign: TextAlign.center,
              style: AppText.bodyMuted(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.exercise});

  final ExerciseRecommendation exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (exercise.planName.isNotEmpty)
                        Text(
                          exercise.planName.toUpperCase(),
                          style: AppText.label(color: AppColors.ugu),
                        ),
                      Text(exercise.name, style: AppText.title()),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => ref
                      .read(exercisesProvider.notifier)
                      .remove(exercise),
                  tooltip: 'Remove from workouts',
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.chili, size: 20),
                ),
              ],
            ),
            if (exercise.prescription.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                exercise.prescription,
                style: AppText.dataM(color: AppColors.plantain),
              ),
            ],
            if (exercise.difficulty.isNotEmpty ||
                exercise.muscleGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (exercise.difficulty.isNotEmpty)
                    _Tag(text: exercise.difficulty, color: AppColors.jollof),
                  for (final g in exercise.muscleGroups)
                    _Tag(text: g, color: AppColors.smoke),
                ],
              ),
            ],
            if (exercise.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(exercise.description, style: AppText.bodyMuted()),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onPressed: () => _copy(context),
                ),
                _ActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Ask',
                  onPressed: () => _ask(ref, context),
                ),
                _ActionButton(
                  icon: Icons.check_rounded,
                  label: 'Log it',
                  onPressed: () => _log(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final text = [
      exercise.name,
      if (exercise.prescription.isNotEmpty) exercise.prescription,
      if (exercise.difficulty.isNotEmpty) 'Difficulty: ${exercise.difficulty}',
      if (exercise.muscleGroups.isNotEmpty)
        'Muscles: ${exercise.muscleGroups.join(', ')}',
      if (exercise.description.isNotEmpty) exercise.description,
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppToast.show(context, 'Copied to clipboard');
  }

  void _ask(WidgetRef ref, BuildContext context) {
    ref.read(coachDraftProvider.notifier).draft(
          'Tell me more about the saved exercise '
          '“${exercise.name}” — form, common mistakes, and how to progress it.',
        );
    Navigator.of(context).pop();
  }

  void _log(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LogExerciseSheet(exercise: exercise),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppText.label(color: color),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: AppColors.smoke),
      label: Text(label, style: AppText.label(color: AppColors.smoke)),
    );
  }
}

