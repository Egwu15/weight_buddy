import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings_data.dart';
import '../../models/weigh_in.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/adaptive_math.dart';
import '../../utils/calorie_math.dart';
import '../../utils/formatters.dart';
import '../../utils/units.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_selectors.dart';

/// Targets & profile: the daily target, the weight unit and the first-run
/// profile (height, birthday, sex, activity).
///
/// The target is *display-only* by default — change any profile input and it
/// re-calculates instantly, so there is no hidden "apply" step. A hand-set
/// number is an explicit, clearly-labelled override.
class TargetsScreen extends ConsumerStatefulWidget {
  const TargetsScreen({super.key});

  @override
  ConsumerState<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends ConsumerState<TargetsScreen> {
  final _targetController = TextEditingController();
  final _heightController = TextEditingController();
  final _heightFeetController = TextEditingController();
  final _heightInchesController = TextEditingController();

  bool _hydrated = false;
  bool _modeDecided = false;
  bool _customMode = false;
  bool _syncFromLogs = false;
  String _targetText = '';
  String? _profileError;
  String? _targetError;
  bool _saving = false;
  String _heightUnit = 'cm';
  DateTime? _birthday;
  Sex? _sex;
  ActivityLevel? _activity;

  @override
  void dispose() {
    _targetController.dispose();
    _heightController.dispose();
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    super.dispose();
  }

  void _hydrate(AppSettingsData data) {
    if (_hydrated) return;
    _hydrated = true;
    _targetText = data.maintenanceKcal.round().toString();
    _targetController.text = _targetText;
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
    _birthday = data.birthday;
    _sex = data.sex;
    _activity = data.activityLevel;
    _syncFromLogs = data.smartTargetSync;
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

  /// The Mifflin-St Jeor maintenance estimate from the current draft profile
  /// and the latest weigh-in, or null while anything is missing.
  double? _estimate(List<WeighIn> weighIns) {
    final height = _profileHeightCm();
    final age = _birthday == null ? null : ageFromBirthday(_birthday!, DateTime.now());
    if (height == null || age == null || _sex == null || _activity == null) {
      return null;
    }
    if (weighIns.isEmpty) return null;
    return CalorieMath.maintenance(
      weightKg: weighIns.first.weightKg,
      heightCm: height,
      age: age,
      sex: _sex!,
      activity: _activity!,
    );
  }

  /// Re-runs the estimate after a profile edit and rewrites the displayed
  /// target — the "changing activity changes the calories" moment, live.
  void _editProfile(List<WeighIn> weighIns, VoidCallback mutate) {
    setState(() {
      mutate();
      if (_syncFromLogs) {
        // Sync mode follows the observed estimate, re-clamped against the
        // freshly-edited profile formula.
        final obs = ref.read(observedMaintenanceProvider).value;
        if (obs != null) {
          _targetText = _clampedObserved(obs, weighIns).round().toString();
          _targetController.text = _targetText;
          return;
        }
      }
      if (!_customMode) {
        final est = _estimate(weighIns);
        if (est != null) {
          _targetText = est.round().toString();
          _targetController.text = _targetText;
        }
      }
    });
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

  void _enableCustom() {
    setState(() {
      _customMode = true;
      _targetController.text = _targetText;
      _targetText = _targetController.text;
    });
  }

  void _enableAuto() {
    final weighIns = ref.read(weighInsProvider).value ?? const <WeighIn>[];
    setState(() {
      _customMode = false;
      _targetError = null;
      final est = _estimate(weighIns);
      if (est != null) {
        _targetText = est.round().toString();
        _targetController.text = _targetText;
      }
    });
  }

  double _clampedObserved(double observed, List<WeighIn> weighIns) {
    final est = _estimate(weighIns);
    if (est == null) return observed;
    return AdaptiveMath.clampToFormula(observed, est);
  }

  void _useObserved(double observed, List<WeighIn> weighIns) {
    setState(() {
      _customMode = true;
      _targetText = _clampedObserved(observed, weighIns).round().toString();
      _targetController.text = _targetText;
    });
  }

  void _onSyncChanged(bool v, List<WeighIn> weighIns, double observed) {
    setState(() {
      _syncFromLogs = v;
      if (v) {
        _customMode = false;
        _targetText = _clampedObserved(observed, weighIns).round().toString();
        _targetController.text = _targetText;
      } else if (!_customMode) {
        final est = _estimate(weighIns);
        if (est != null) {
          _targetText = est.round().toString();
          _targetController.text = _targetText;
        }
      }
    });
  }

  String get _displayTarget {
    final v = double.tryParse(_targetText.trim().replaceAll(',', ''));
    if (v == null || v <= 0) return '—';
    return '${Formatters.kcal(v)} kcal';
  }

  Future<void> _save() async {
    final target = double.tryParse(_targetText.trim().replaceAll(',', ''));
    if (target == null || target <= 0) {
      setState(() => _targetError = 'Enter your target above zero.');
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
      setState(() => _profileError = _heightUnit == 'cm'
          ? 'Enter a height between 1 and 300 cm.'
          : 'Enter a height in feet and inches.');
      return;
    }
    if (_birthday != null) {
      final age = ageFromBirthday(_birthday!, DateTime.now());
      if (age < 1 || age > 120) {
        setState(() => _profileError = 'Pick a date of birth in the past.');
        return;
      }
    }
    setState(() {
      _profileError = null;
      _targetError = null;
      _saving = true;
    });
    final appSettings = await ref.read(appSettingsProvider.future);
    await ref.read(appSettingsProvider.notifier).save(
          appSettings.copyWith(
            maintenanceKcal: target,
            heightUnit: _heightUnit,
            heightCm: heightCm,
            birthday: _birthday,
            sex: _sex,
            activityLevel: _activity,
            smartTargetSync: _syncFromLogs,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(context, 'Saved — target ${Formatters.kcal(target)} kcal.');
  }

  @override
  Widget build(BuildContext context) {
    final appSettingsAsync = ref.watch(appSettingsProvider);
    appSettingsAsync.whenOrNull(data: _hydrate);
    final weighInsAsync = ref.watch(weighInsProvider);
    final weighIns = weighInsAsync.value ?? const <WeighIn>[];
    final observedAsync = ref.watch(observedMaintenanceProvider);
    final observed = observedAsync.value;

    // On first open, preserve an existing manual target: if the saved number
    // differs from what the profile now estimates, start in custom mode so a
    // deliberately-chosen value is never silently overwritten.
    if (!_modeDecided && appSettingsAsync.hasValue && weighInsAsync.hasValue) {
      _modeDecided = true;
      final settings = appSettingsAsync.value!;
      final est = _estimate(weighIns);
      if (est != null && settings.maintenanceKcal.round() != est.round()) {
        _customMode = true;
      }
    }

    ref.listen(observedMaintenanceProvider, (prev, next) {
      final obs = next.value;
      if (obs != null && _syncFromLogs && !_customMode && mounted) {
        final latest = ref.read(weighInsProvider).value ?? const <WeighIn>[];
        setState(() {
          _targetText = _clampedObserved(obs, latest).round().toString();
          _targetController.text = _targetText;
        });
      }
    });

    final estimate = _estimate(weighIns);
    final latestKg = weighIns.isEmpty ? null : weighIns.first.weightKg;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Targets & profile', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Your daily target', style: AppText.label()),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.plantain),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'YOUR DAILY TARGET',
                        style: AppText.label(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _customMode ? _enableAuto : _enableCustom,
                      child: Text(
                        _customMode
                            ? 'Back to automatic'
                            : 'Set my own target',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (_customMode)
                  TextField(
                    controller: _targetController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.dataL(),
                    decoration: InputDecoration(
                      labelText: 'Your daily target',
                      suffixText: 'kcal',
                      errorText: _targetError,
                    ),
                    onChanged: (v) => setState(() => _targetText = v),
                  )
                else
                  Text(_displayTarget,
                      style: AppText.dataL(color: AppColors.plantain)),
                const SizedBox(height: 8),
                Text(
                  _customMode
                      ? 'Custom — you set this number. Switch back to automatic '
                          'anytime to follow your profile again.'
                      : 'Auto-calculated from your profile and latest weigh-in. '
                          'It updates as you change your details below.',
                  style: AppText.bodyMuted(fontSize: 12),
                ),
                if (_customMode && estimate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Your profile suggests '
                      '${Formatters.kcal(estimate)} kcal — tap '
                      '"Back to automatic" to use it.',
                      style: AppText.bodyMuted(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          if (!_customMode) ...[
            const SizedBox(height: 8),
            if (estimate != null && latestKg != null)
              Text(
                '${Formatters.weight(latestKg)} kg · '
                '${_profileHeightCm()!.round()} cm · '
                '${ageFromBirthday(_birthday!, DateTime.now())} y · '
                '${_activity!.label} × ${_activity!.factor}',
                style: AppText.bodyMuted(fontSize: 12),
              )
            else
              Text(
                weighIns.isEmpty
                    ? 'Add a weigh-in — the estimate uses your latest weight.'
                    : 'Fill in height, date of birth, sex and activity to see '
                        'the estimate.',
                style: AppText.bodyMuted(fontSize: 12),
              ),
          ],
          const SizedBox(height: 24),
          Text('Profile', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'The target above is calculated from these — change anything and '
            'it updates.',
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
                    decoration: InputDecoration(
                      labelText: 'Height',
                      suffixText: 'cm',
                      errorText: _profileError,
                    ),
                    onChanged: (_) => _editProfile(weighIns, () {}),
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
                    decoration: InputDecoration(
                      labelText: 'Feet',
                      suffixText: 'ft',
                      errorText: _profileError,
                    ),
                    onChanged: (_) => _editProfile(weighIns, () {}),
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
                    onChanged: (_) => _editProfile(weighIns, () {}),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          BirthdayField(
            value: _birthday,
            errorText: _profileError,
            onChanged: (b) => _editProfile(weighIns, () => _birthday = b),
          ),
          const SizedBox(height: 12),
          SexSelector(
            value: _sex,
            onChanged: (s) => _editProfile(weighIns, () => _sex = s),
          ),
          const SizedBox(height: 12),
          ActivityDropdown(
            value: _activity,
            onChanged: (a) => _editProfile(weighIns, () => _activity = a),
          ),
          const SizedBox(height: 16),
          if (observed != null) ...[
            _LoggingCard(
              observed: observed,
              syncing: _syncFromLogs,
              onSyncChanged: (v) => _onSyncChanged(v, weighIns, observed),
              onUse: () => _useObserved(observed, weighIns),
            ),
            const SizedBox(height: 16),
          ],
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

/// The smart-target card: the observed maintenance read from the user's own
/// weigh-ins and food logs, with an apply action and an opt-in auto-sync.
class _LoggingCard extends StatelessWidget {
  const _LoggingCard({
    required this.observed,
    required this.syncing,
    required this.onSyncChanged,
    required this.onUse,
  });

  final double observed;
  final bool syncing;
  final ValueChanged<bool> onSyncChanged;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ember),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FROM YOUR LOGGING', style: AppText.label()),
          const SizedBox(height: 4),
          Text(
            '${Formatters.kcal(observed)} kcal/day',
            style: AppText.dataL(color: AppColors.plantain),
          ),
          const SizedBox(height: 4),
          Text(
            'Read from your recent weigh-ins and food logs — what your body '
            'actually runs on. Logged workouts already show up in your weight '
            'trend, so nothing is double-counted.',
            style: AppText.bodyMuted(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onUse,
              icon: const Icon(Icons.auto_graph_rounded, size: 18),
              label: const Text('Use as my target'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep it in sync as I log'),
            subtitle: Text(
              'Auto-updates your target as new weigh-ins and meals come in.',
              style: AppText.bodyMuted(fontSize: 12),
            ),
            value: syncing,
            onChanged: onSyncChanged,
          ),
        ],
      ),
    );
  }
}
