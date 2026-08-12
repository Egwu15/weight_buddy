import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings_data.dart';
import '../../models/weigh_in.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_math.dart';
import '../../utils/units.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_selectors.dart';

/// Targets & profile: the maintenance-calorie line, the weight unit and the
/// first-run profile (height, age, sex, activity). Everything the calendar,
/// streaks and the coach measure against, on one page.
class TargetsScreen extends ConsumerStatefulWidget {
  const TargetsScreen({super.key});

  @override
  ConsumerState<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends ConsumerState<TargetsScreen> {
  final _maintenanceController = TextEditingController();
  final _heightController = TextEditingController();
  final _heightFeetController = TextEditingController();
  final _heightInchesController = TextEditingController();
  final _ageController = TextEditingController();
  bool _hydrated = false;
  String? _targetError;
  bool _saving = false;
  String _weightUnit = 'kg';
  String _heightUnit = 'cm';
  Sex? _sex;
  ActivityLevel? _activity;

  @override
  void dispose() {
    _maintenanceController.dispose();
    _heightController.dispose();
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _hydrate(AppSettingsData data) {
    if (_hydrated) return;
    _hydrated = true;
    _maintenanceController.text = data.maintenanceKcal.round().toString();
    _weightUnit = data.weightUnit;
    _heightUnit = data.heightUnit;
    final height = data.heightCm;
    if (height != null) {
      if (data.heightUnit == 'ft') {
        final (feet, inches) = Units.cmToFeetInches(height);
        _heightFeetController.text = feet.toString();
        _heightInchesController.text = inches.toString();
      } else {
        _heightController.text = height.toString();
      }
    }
    _ageController.text = data.age?.toString() ?? '';
    _sex = data.sex;
    _activity = data.activityLevel;
  }

  /// Reads the height from whichever input the unit toggle is showing,
  /// returning null when it's empty or implausible.
  double? _profileHeightCm() {
    if (_heightUnit == 'cm') {
      final cm =
          double.tryParse(_heightController.text.trim().replaceAll(',', '.'));
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

  /// Carries a typed height across a unit switch so input is never lost.
  void _onHeightUnitChanged(String unit) {
    if (unit == _heightUnit) return;
    final currentCm = _profileHeightCm();
    setState(() {
      _heightUnit = unit;
      if (currentCm == null) return;
      if (unit == 'ft') {
        final (feet, inches) = Units.cmToFeetInches(currentCm);
        _heightFeetController.text = feet.toString();
        _heightInchesController.text = inches.toString();
        _heightController.clear();
      } else {
        _heightController.text = currentCm.toStringAsFixed(0);
        _heightFeetController.clear();
        _heightInchesController.clear();
      }
    });
  }

  Future<void> _save() async {
    final maintenance =
        double.tryParse(_maintenanceController.text.trim().replaceAll(',', '.'));
    if (maintenance == null || maintenance <= 0) {
      setState(() => _targetError = 'Enter maintenance calories above zero.');
      return;
    }
    // Profile fields are optional here (a partial profile is fine), but when
    // present they must be sensible.
    final hasHeightInput = _heightUnit == 'cm'
        ? _heightController.text.trim().isNotEmpty
        : (_heightFeetController.text.trim().isNotEmpty ||
            _heightInchesController.text.trim().isNotEmpty);
    final heightCm = _profileHeightCm();
    if (hasHeightInput && heightCm == null) {
      setState(() => _targetError = _heightUnit == 'cm'
          ? 'Enter a height between 1 and 300 cm.'
          : 'Enter a height in feet and inches.');
      return;
    }
    final ageText = _ageController.text.trim();
    int? age;
    if (ageText.isNotEmpty) {
      age = int.tryParse(ageText);
      if (age == null || age <= 0 || age > 120) {
        setState(() => _targetError = 'Enter an age between 1 and 120.');
        return;
      }
    }
    setState(() {
      _targetError = null;
      _saving = true;
    });
    final appSettings = await ref.read(appSettingsProvider.future);
    await ref.read(appSettingsProvider.notifier).save(
          appSettings.copyWith(
            maintenanceKcal: maintenance,
            weightUnit: _weightUnit,
            heightUnit: _heightUnit,
            heightCm: heightCm,
            age: age,
            sex: _sex,
            activityLevel: _activity,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(context, 'Saved');
  }

  /// Fills the maintenance field from the profile + latest weigh-in, so the
  /// manual target can be a suggestion rather than a guess. Never overwrites
  /// without the user pressing this button.
  Future<void> _estimateFromProfile() async {
    final heightCm = _profileHeightCm();
    final age = int.tryParse(_ageController.text.trim());
    final sex = _sex;
    final activity = _activity;
    if (heightCm == null || age == null || sex == null || activity == null) {
      setState(() => _targetError =
          'Fill in height, age, sex and activity to use the estimate.');
      return;
    }
    final weighIns = ref.read(weighInsProvider).value ?? const <WeighIn>[];
    if (weighIns.isEmpty) {
      setState(() => _targetError =
          'Add a weigh-in first — the estimate needs your current weight.');
      return;
    }
    final estimate = CalorieMath.maintenance(
      weightKg: weighIns.first.weightKg,
      heightCm: heightCm,
      age: age,
      sex: sex,
      activity: activity,
    ).round();
    setState(() {
      _maintenanceController.text = estimate.toString();
      _targetError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(appSettingsProvider);
    appSettings.whenOrNull(data: _hydrate);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Targets & profile', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Targets', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Maintenance calories is the line the calendar and the coach '
            'measure you against. Days at or under it count as on-plan.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _maintenanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.dataM(),
            decoration: InputDecoration(
              labelText: 'Maintenance calories / day',
              hintText: '2200',
              suffixText: 'kcal',
              errorText: _targetError,
            ),
          ),
          const SizedBox(height: 16),
          Text('Weight unit', style: AppText.label()),
          const SizedBox(height: 8),
          _WeightUnitToggle(
            unit: _weightUnit,
            onChanged: (u) => setState(() => _weightUnit = u),
          ),
          const SizedBox(height: 24),
          Text('Profile', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Height, age, sex and activity let the app estimate your '
            'maintenance instead of guessing. The estimate uses your latest '
            'weigh-in for current weight.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 16),
          HeightUnitToggle(
            unit: _heightUnit,
            onChanged: _onHeightUnitChanged,
          ),
          const SizedBox(height: 12),
          if (_heightUnit == 'cm')
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.dataS(),
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      suffixText: 'cm',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    style: AppText.dataS(),
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      suffixText: 'years',
                    ),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heightFeetController,
                    keyboardType: TextInputType.number,
                    style: AppText.dataS(),
                    decoration: const InputDecoration(
                      labelText: 'Feet',
                      suffixText: 'ft',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _heightInchesController,
                    keyboardType: TextInputType.number,
                    style: AppText.dataS(),
                    decoration: const InputDecoration(
                      labelText: 'Inches',
                      suffixText: 'in',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              style: AppText.dataS(),
              decoration: const InputDecoration(
                labelText: 'Age',
                suffixText: 'years',
              ),
            ),
          ],
          const SizedBox(height: 12),
          SexSelector(value: _sex, onChanged: (s) => setState(() => _sex = s)),
          const SizedBox(height: 12),
          ActivitySelector(
            value: _activity,
            onChanged: (a) => setState(() => _activity = a),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _estimateFromProfile,
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text('Use profile to estimate maintenance'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: Text(_saving ? 'Saving…' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}

class _WeightUnitToggle extends StatelessWidget {
  const _WeightUnitToggle({required this.unit, required this.onChanged});

  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UnitChoice(
            label: 'kg',
            selected: unit == 'kg',
            onTap: () => onChanged('kg'),
          ),
          _UnitChoice(
            label: 'lb',
            selected: unit == 'lb',
            onTap: () => onChanged('lb'),
          ),
        ],
      ),
    );
  }
}

class _UnitChoice extends StatelessWidget {
  const _UnitChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.plantain : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: AppText.label(
            color: selected ? AppColors.pot : AppColors.smoke,
          ),
        ),
      ),
    );
  }
}

