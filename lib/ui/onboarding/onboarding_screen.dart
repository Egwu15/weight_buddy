import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/weigh_in.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_math.dart';
import '../widgets/profile_selectors.dart';

/// First-run onboarding: a few quick questions (height, weight, age, sex,
/// activity) so maintenance calories are estimated instead of guessed.
///
/// Completing it stores the profile, computes the maintenance target and
/// plants today's first weigh-in; the shell then swaps to the tabs. Skipping
/// keeps the app usable — the profile can be filled in later under Settings →
/// Targets.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _ageController = TextEditingController();
  String _unit = 'kg';
  Sex? _sex;
  ActivityLevel? _activity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _unit = ref.read(appSettingsProvider).value?.weightUnit ?? 'kg';
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  double? _heightCm() =>
      double.tryParse(_heightController.text.trim().replaceAll(',', '.'));

  double? _weightValue() =>
      double.tryParse(_weightController.text.trim().replaceAll(',', '.'));

  int? _age() => int.tryParse(_ageController.text.trim());

  /// The maintenance estimate, or null while any required field is missing.
  double? get _estimate {
    final height = _heightCm();
    final weight = _weightValue();
    final age = _age();
    final sex = _sex;
    final activity = _activity;
    if (height == null || height <= 0 || height > 300) return null;
    if (weight == null || weight <= 0 || weight > 500) return null;
    if (age == null || age <= 0 || age > 120) return null;
    if (sex == null || activity == null) return null;
    final kg = _unit == 'lb' ? weight / 2.2046226218 : weight;
    return CalorieMath.maintenance(
      weightKg: kg,
      heightCm: height,
      age: age,
      sex: sex,
      activity: activity,
    );
  }

  void _banner(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _complete() async {
    final height = _heightCm();
    final weight = _weightValue();
    final age = _age();
    final sex = _sex;
    final activity = _activity;
    if (height == null || height <= 0 || height > 300) {
      _banner('Enter your height in centimetres.');
      return;
    }
    if (weight == null || weight <= 0 || weight > 500) {
      _banner('Enter your current weight.');
      return;
    }
    if (age == null || age <= 0 || age > 120) {
      _banner('Enter your age in years.');
      return;
    }
    if (sex == null) {
      _banner('Choose male or female.');
      return;
    }
    if (activity == null) {
      _banner('Pick the activity level closest to your week.');
      return;
    }
    final kg = _unit == 'lb' ? weight / 2.2046226218 : weight;
    final estimate = CalorieMath.maintenance(
      weightKg: kg,
      heightCm: height,
      age: age,
      sex: sex,
      activity: activity,
    ).round();
    final current = ref.read(appSettingsProvider).value;
    if (current == null) return;
    final next = current.copyWith(
      heightCm: height,
      age: age,
      sex: sex,
      activityLevel: activity,
      maintenanceKcal: estimate.toDouble(),
      weightUnit: _unit,
      profileCompleted: true,
    );
    setState(() => _saving = true);
    // Plant today's first weigh-in, then flip the shell into the tabs.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await ref
        .read(weighInsProvider.notifier)
        .add(WeighIn(date: today, weightKg: kg));
    await ref.read(appSettingsProvider.notifier).save(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Maintenance ≈ $estimate kcal/day — welcome in.')),
    );
  }

  Future<void> _skip() async {
    final current = ref.read(appSettingsProvider).value;
    if (current == null) return;
    await ref
        .read(appSettingsProvider.notifier)
        .save(current.copyWith(profileCompleted: true));
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _estimate;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Row(
              children: [
                Text('weightbuddy',
                    style: AppText.label(color: AppColors.jollof)),
                const Spacer(),
                TextButton(onPressed: _skip, child: const Text('Skip for now')),
              ],
            ),
            const SizedBox(height: 12),
            Text('A few questions, then we’re off', style: AppText.headline()),
            const SizedBox(height: 8),
            Text(
              'We’ll estimate your maintenance calories from these instead '
              'of guessing. Change any of it later in Settings.',
              style: AppText.bodyMuted(),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Height', style: AppText.title()),
                    const SizedBox(height: 4),
                    Text('In centimetres, e.g. 175',
                        style: AppText.bodyMuted(fontSize: 13)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _heightController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: AppText.dataM(),
                      decoration: const InputDecoration(
                        labelText: 'Height',
                        suffixText: 'cm',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Text('Current weight', style: AppText.title()),
                    const SizedBox(height: 4),
                    Text(
                      'Used for the estimate and saved as today’s weigh-in.',
                      style: AppText.bodyMuted(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: AppText.dataM(),
                            decoration: InputDecoration(
                              labelText: 'Weight',
                              suffixText: _unit,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        WeightUnitToggle(
                          unit: _unit,
                          onChanged: (u) => setState(() => _unit = u),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Age', style: AppText.title()),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      style: AppText.dataM(),
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        suffixText: 'years',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sex', style: AppText.title()),
                    const SizedBox(height: 4),
                    Text(
                      'Used by the standard calorie equation.',
                      style: AppText.bodyMuted(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    SexSelector(
                      value: _sex,
                      onChanged: (s) => setState(() => _sex = s),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activity level', style: AppText.title()),
                    const SizedBox(height: 4),
                    Text(
                      'How active is an average week for you?',
                      style: AppText.bodyMuted(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ActivitySelector(
                      value: _activity,
                      onChanged: (a) => setState(() => _activity = a),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (estimate != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.plantain),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calculate_outlined,
                        color: AppColors.plantain, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ESTIMATED MAINTENANCE',
                              style: AppText.label()),
                          const SizedBox(height: 2),
                          Text(
                            '${estimate.round()} kcal/day',
                            style: AppText.dataL(color: AppColors.plantain),
                          ),
                          Text(
                            'Mifflin-St Jeor with your activity level',
                            style: AppText.bodyMuted(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _complete,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: Text(_saving ? 'Saving…' : 'Start tracking'),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
