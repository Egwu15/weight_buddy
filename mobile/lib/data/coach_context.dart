import '../models/exercise_recommendation.dart';
import '../models/log_entry.dart';
import '../models/memory.dart';
import '../models/weigh_in.dart';
import '../utils/streaks.dart';

/// Builds the coach's system prompt from the user's live data and the
/// distilled layers (memories + saved exercises).
abstract final class CoachContext {
  static const persona = '''
You are the Weight Buddy coach — a warm, direct personal nutrition and
training coach for one person. You know their day-to-day logs, weight,
streaks and what you have previously remembered about them. Give specific,
actionable advice in plain language. When you recommend exercises, be
concrete about sets, reps, rest and difficulty so they can act on it
immediately. Keep answers focused; a few clear paragraphs beat an essay.
Do not claim to know things not in the context. Remember: the user speaks
regional and everyday foods — estimate honestly when amounts are unclear.''';

  /// One section of the digest; omitted when empty.
  static String build({
    required LogTotals today,
    required List<(DateTime, LogTotals)> last7Days,
    required double maintenanceKcal,
    required List<WeighIn> weighIns,
    required Streaks streaks,
    required List<Memory> memories,
    required List<ExerciseRecommendation> exercises,
  }) {
    final sections = <String>[];

    sections.add(
      'MAINTENANCE TARGET: $maintenanceKcal kcal/day (days at or under '
      'this count as on-plan).',
    );

    sections.add(
      'TODAY: eaten ${today.eatenKcal.round()} kcal, burned '
      '${today.burnedKcal.round()} kcal, net ${today.netKcal.round()} kcal, '
      'protein ${today.proteinG.round()}g / carbs ${today.carbsG.round()}g / '
      'fat ${today.fatG.round()}g.',
    );

    if (last7Days.isNotEmpty) {
      final lines = last7Days.map((record) {
        final (day, totals) = record;
        final label = '${day.day}/${day.month}';
        final status = totals.eatenKcal == 0 && totals.burnedKcal == 0
            ? 'nothing logged'
            : 'net ${totals.netKcal.round()} kcal';
        return '$label: $status';
      }).join(' · ');
      sections.add('LAST 7 DAYS: $lines.');
    }

    if (weighIns.isNotEmpty) {
      final latest = weighIns.first;
      final first = weighIns.last;
      final delta = latest.weightKg - first.weightKg;
      final deltaText = delta == 0
          ? 'unchanged'
          : (delta > 0
              ? '+${delta.toStringAsFixed(1)} kg'
              : '${delta.toStringAsFixed(1)} kg');
      sections.add(
        'WEIGHT: latest ${latest.weightKg.toStringAsFixed(1)} kg on '
        '${latest.date.day}/${latest.date.month}. Trend across '
        '${weighIns.length} reading(s): $deltaText.',
      );
    }

    if (streaks.logging > 0 || streaks.onPlan > 0) {
      sections.add(
        'STREAKS: logging ${streaks.logging} day(s), on-plan '
        '${streaks.onPlan} day(s).',
      );
    }

    if (memories.isNotEmpty) {
      final bullets = memories
          .take(12)
          .map((m) => '- ${m.content} [${m.category.apiName}]')
          .join('\n');
      sections.add('WHAT I REMEMBER:\n$bullets');
    }

    if (exercises.isNotEmpty) {
      final bullets = exercises
          .take(10)
          .map((e) =>
              '- ${e.name}${e.prescription.isNotEmpty ? ' (${e.prescription})' : ''}')
          .join('\n');
      sections.add('SAVED EXERCISES FOR THIS PERSON:\n$bullets');
    }

    return sections.join('\n\n');
  }
}
