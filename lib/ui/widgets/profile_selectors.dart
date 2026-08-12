import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_math.dart';

/// Male / female choice for the maintenance estimate (Mifflin-St Jeor needs a
/// sex constant). Shared by onboarding and Settings → Targets.
class SexSelector extends StatelessWidget {
  const SexSelector({super.key, required this.value, required this.onChanged});

  final Sex? value;
  final ValueChanged<Sex> onChanged;

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
        children: [
          _sexOption('Male', Sex.male),
          _sexOption('Female', Sex.female),
        ],
      ),
    );
  }

  Widget _sexOption(String label, Sex sex) {
    final selected = value == sex;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(sex),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.plantain : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.label(color: selected ? AppColors.pot : AppColors.smoke),
          ),
        ),
      ),
    );
  }
}

/// Activity level picker: each option is a selectable tile with a short
/// description, so the choice means something rather than just a number.
class ActivitySelector extends StatelessWidget {
  const ActivitySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ActivityLevel? value;
  final ValueChanged<ActivityLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final levels = ActivityLevel.values;
    return Column(
      children: [
        for (var i = 0; i < levels.length; i++) ...[
          _activityOption(levels[i]),
          if (i < levels.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _activityOption(ActivityLevel level) {
    final selected = value == level;
    return Material(
      color:
          selected ? AppColors.plantain.withValues(alpha: 0.12) : AppColors.barkRaised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => onChanged(level),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.plantain : AppColors.ember,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.plantain : AppColors.smoke,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(level.label, style: AppText.body()),
                    const SizedBox(height: 2),
                    Text(
                      level.description,
                      style: AppText.bodyMuted(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// cm / ft toggle for the height input. Height itself is always stored in
/// centimetres; the toggle only changes how it's typed.
class HeightUnitToggle extends StatelessWidget {
  const HeightUnitToggle({super.key, required this.unit, required this.onChanged});

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
          _unitButton('cm', unit == 'cm', () => onChanged('cm')),
          _unitButton('ft', unit == 'ft', () => onChanged('ft')),
        ],
      ),
    );
  }

  Widget _unitButton(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.plantain : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: AppText.label(color: selected ? AppColors.pot : AppColors.smoke),
        ),
      ),
    );
  }
}

/// kg / lb toggle, matching the weigh-in sheet's control.
class WeightUnitToggle extends StatelessWidget {
  const WeightUnitToggle({super.key, required this.unit, required this.onChanged});

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
          _unitButton('kg', unit == 'kg', () => onChanged('kg')),
          _unitButton('lb', unit == 'lb', () => onChanged('lb')),
        ],
      ),
    );
  }

  Widget _unitButton(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.plantain : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: AppText.label(color: selected ? AppColors.pot : AppColors.smoke),
        ),
      ),
    );
  }
}
