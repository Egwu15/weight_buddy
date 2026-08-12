import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/openai_service.dart';
import '../../models/exercise_recommendation.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/app_toast.dart';

enum _Stage { processing, parsed, error }

/// “Log it” for a saved exercise: turns the recommendation into a real
/// exercise entry by running it through the same GPT parsing pipeline the
/// voice flow uses, then saves it to today.
class LogExerciseSheet extends ConsumerStatefulWidget {
  const LogExerciseSheet({super.key, required this.exercise});

  final ExerciseRecommendation exercise;

  @override
  ConsumerState<LogExerciseSheet> createState() => _LogExerciseSheetState();
}

class _LogExerciseSheetState extends ConsumerState<LogExerciseSheet> {
  _Stage _stage = _Stage.processing;
  ParsedLog? _parsed;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _process();
  }

  String get _promptText {
    final e = widget.exercise;
    final parts = <String>['I did'];
    if (e.sets != null && e.sets! > 0) parts.add('${e.sets} sets of');
    if (e.reps != null && e.reps! > 0) {
      parts.add('${e.reps} reps of ${e.name}');
    } else if (e.durationMinutes != null && e.durationMinutes! > 0) {
      parts.add('${e.name} for ${e.durationMinutes} minutes');
    } else {
      parts.add(e.name);
    }
    if (e.durationMinutes != null && e.durationMinutes! > 0 &&
        e.reps != null) {
      parts.add('(${e.durationMinutes} minutes total)');
    }
    return '${parts.join(' ')}.';
  }

  Future<void> _process() async {
    setState(() => _stage = _Stage.processing);
    final service = ref.read(openaiServiceProvider);
    if (service == null) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Save your OpenAI key in Settings to log this exercise.';
      });
      return;
    }
    try {
      final parsed = await service.parseTranscript(_promptText);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _stage = _Stage.parsed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = '$e';
      });
    }
  }

  Future<void> _save() async {
    final parsed = _parsed;
    if (parsed == null) return;
    ref.read(selectedDayProvider.notifier).setDay(DateTime.now());
    await ref.read(dayLogsProvider.notifier).add(
          parsed.toEntry(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            rawTranscript: _promptText,
          ),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, 'Logged as exercise');
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text('Log exercise', style: AppText.title())),
          const SizedBox(height: 16),
          Text(e.name, style: AppText.headline()),
          if (e.prescription.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(e.prescription,
                style: AppText.dataM(color: AppColors.plantain)),
          ],
          const SizedBox(height: 20),
          switch (_stage) {
            _Stage.processing => const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Working out the burn…'),
                ],
              ),
            _Stage.error => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error,
                      style: AppText.bodyMuted(color: AppColors.chili)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _process,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            _Stage.parsed => _parsedCard(),
          },
        ],
      ),
    );
  }

  Widget _parsedCard() {
    final parsed = _parsed!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(parsed.summary, style: AppText.title()),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stat(label: 'BURNED', value: Formatters.kcal(parsed.calories)),
                if (parsed.durationMinutes != null) ...[
                  Container(width: 1, height: 30, color: AppColors.ember),
                  _Stat(
                    label: 'DURATION',
                    value: '${parsed.durationMinutes!.round()} min',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Log it as done'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label(color: AppColors.smoke)),
          const SizedBox(height: 4),
          Text(value, style: AppText.dataM(color: AppColors.ugu)),
        ],
      ),
    );
  }
}

