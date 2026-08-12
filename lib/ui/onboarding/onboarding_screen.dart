import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/weigh_in.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_math.dart';
import '../../utils/units.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_selectors.dart';

/// First-run onboarding — a four-step flow (height → weight → age & sex →
/// activity) instead of one long form, so each question gets its own screen.
///
/// The questionnaire gates the whole app — there is no skip — so the daily
/// target is personal from day one. Completing it stores the profile,
/// computes the maintenance target and plants today's first weigh-in; the
/// shell then swaps to the tabs. The profile can be edited later under
/// Settings → Targets.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 4;

  final _heightCmController = TextEditingController();
  final _heightFeetController = TextEditingController();
  final _heightInchesController = TextEditingController();
  final _weightController = TextEditingController();
  final _ageController = TextEditingController();

  int _step = 0;
  String _heightUnit = 'cm';
  String _weightUnit = 'kg';
  Sex? _sex;
  ActivityLevel? _activity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider).value;
    _weightUnit = settings?.weightUnit ?? 'kg';
    _heightUnit = settings?.heightUnit ?? 'cm';
  }

  @override
  void dispose() {
    _heightCmController.dispose();
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  /// The height in centimetres from whatever unit the toggle is showing, or
  /// null when the input is missing or implausible.
  double? _heightCm() {
    if (_heightUnit == 'cm') {
      final cm = double.tryParse(
          _heightCmController.text.trim().replaceAll(',', '.'));
      if (cm == null || cm <= 0 || cm > 300) return null;
      return cm;
    }
    final feet = int.tryParse(_heightFeetController.text.trim());
    final inches = int.tryParse(_heightInchesController.text.trim());
    if (feet == null || inches == null) return null;
    if (feet <= 0 || feet > 9 || inches < 0 || inches > 11) return null;
    final cm = Units.feetInchesToCm(feet, inches);
    if (cm > 300) return null;
    return cm;
  }

  /// The weight in kilograms regardless of the chosen unit, or null when the
  /// input is missing or implausible.
  double? _weightKg() {
    final value = double.tryParse(
        _weightController.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0 || value > 500) return null;
    return _weightUnit == 'lb' ? Units.lbToKg(value) : value;
  }

  int? _age() => int.tryParse(_ageController.text.trim());

  /// The maintenance estimate, or null while any required field is missing.
  double? get _estimate {
    final height = _heightCm();
    final weight = _weightKg();
    final age = _age();
    final sex = _sex;
    final activity = _activity;
    if (height == null || weight == null || age == null ||
        sex == null || activity == null) {
      return null;
    }
    return CalorieMath.maintenance(
      weightKg: weight,
      heightCm: height,
      age: age,
      sex: sex,
      activity: activity,
    );
  }

  void _banner(String message) {
    AppToast.show(context, message);
  }

  /// The first validation error on [step], or null when it's ready to move on.
  String? _stepError(int step) {
    switch (step) {
      case 0:
        return _heightCm() == null
            ? (_heightUnit == 'cm'
                ? 'Enter your height in centimetres.'
                : 'Enter your height in feet and inches.')
            : null;
      case 1:
        return _weightKg() == null ? 'Enter your current weight.' : null;
      case 2:
        final age = _age();
        if (age == null || age <= 0 || age > 120) {
          return 'Enter your age in years.';
        }
        if (_sex == null) return 'Choose male or female.';
        return null;
      case 3:
        return _activity == null
            ? 'Pick the activity level closest to your week.'
            : null;
      default:
        return null;
    }
  }

  void _next() {
    final error = _stepError(_step);
    if (error != null) {
      _banner(error);
      return;
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
  }

  /// Carries a typed height across a unit switch so input is never lost.
  void _onHeightUnitChanged(String unit) {
    if (unit == _heightUnit) return;
    final currentCm = _heightCm();
    setState(() {
      _heightUnit = unit;
      if (currentCm == null) return;
      if (unit == 'ft') {
        final (feet, inches) = Units.cmToFeetInches(currentCm);
        _heightFeetController.text = feet.toString();
        _heightInchesController.text = inches.toString();
        _heightCmController.clear();
      } else {
        _heightCmController.text = currentCm.toStringAsFixed(0);
        _heightFeetController.clear();
        _heightInchesController.clear();
      }
    });
  }

  Future<void> _complete() async {
    final height = _heightCm();
    final weight = _weightKg();
    final age = _age();
    final sex = _sex;
    final activity = _activity;
    if (height == null || weight == null || age == null ||
        sex == null || activity == null) {
      return;
    }
    final estimate = CalorieMath.maintenance(
      weightKg: weight,
      heightCm: height,
      age: age,
      sex: sex,
      activity: activity,
    ).round();
    final current = ref.read(appSettingsProvider).value;
    if (current == null) return;
    final next = current.copyWith(
      heightCm: height,
      heightUnit: _heightUnit,
      age: age,
      sex: sex,
      activityLevel: activity,
      maintenanceKcal: estimate.toDouble(),
      weightUnit: _weightUnit,
      profileCompleted: true,
    );
    setState(() => _saving = true);
    // Plant today's first weigh-in, then flip the shell into the tabs.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await ref
        .read(weighInsProvider.notifier)
        .add(WeighIn(date: today, weightKg: weight));
    await ref.read(appSettingsProvider.notifier).save(next);
    if (!mounted) return;
    AppToast.show(context, 'Maintenance ≈ $estimate kcal/day — welcome in.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text('weightbuddy',
                      style: AppText.label(color: AppColors.jollof)),
                  const Spacer(),
                  Text('Step ${_step + 1} of $_stepCount',
                      style: AppText.bodyMuted(fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _stepCount,
                  minHeight: 4,
                  backgroundColor: AppColors.ember,
                  valueColor: const AlwaysStoppedAnimation(AppColors.plantain),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: ListView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  children: switch (_step) {
                    0 => _heightStep(),
                    1 => _weightStep(),
                    2 => _detailsStep(),
                    _ => _activityStep(),
                  },
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  List<Widget> _heightStep() => [
        Text('How tall are you?', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          'Centimetres or feet and inches — whatever you know.',
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
                Text('5′9″ or 175 cm, e.g.',
                    style: AppText.bodyMuted(fontSize: 13)),
                const SizedBox(height: 12),
                HeightUnitToggle(
                  unit: _heightUnit,
                  onChanged: _onHeightUnitChanged,
                ),
                const SizedBox(height: 16),
                if (_heightUnit == 'cm')
                  TextField(
                    controller: _heightCmController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.dataM(),
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      suffixText: 'cm',
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _heightFeetController,
                          keyboardType: TextInputType.number,
                          style: AppText.dataM(),
                          decoration: const InputDecoration(
                            labelText: 'Feet',
                            suffixText: 'ft',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _heightInchesController,
                          keyboardType: TextInputType.number,
                          style: AppText.dataM(),
                          decoration: const InputDecoration(
                            labelText: 'Inches',
                            suffixText: 'in',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ];
  List<Widget> _weightStep() => [
        Text('What do you weigh today?', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          'It becomes today’s first weigh-in.',
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                          suffixText: _weightUnit,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    WeightUnitToggle(
                      unit: _weightUnit,
                      onChanged: (u) => setState(() => _weightUnit = u),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ];

  List<Widget> _detailsStep() => [
        Text('A couple more details', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          'Age and sex complete the calorie equation.',
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
      ];
  List<Widget> _activityStep() {
    final estimate = _estimate;
    return [
      Text('How active is your week?', style: AppText.headline()),
      const SizedBox(height: 8),
      Text(
        'Last one — it scales your estimate.',
        style: AppText.bodyMuted(),
      ),
      const SizedBox(height: 20),
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
                    Text('ESTIMATED MAINTENANCE', style: AppText.label()),
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
    ];
  }

  Widget _footer() {
    final isLast = _step == _stepCount - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            if (_step > 0) ...[
              OutlinedButton(
                onPressed: _saving ? null : _back,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : (isLast ? _complete : _next),
                icon: Icon(
                  isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  size: 20,
                ),
                label: Text(
                  isLast ? (_saving ? 'Saving…' : 'Start tracking') : 'Continue',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
