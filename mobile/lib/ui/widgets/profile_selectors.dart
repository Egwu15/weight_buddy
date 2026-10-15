import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
/// Full-height version, used on the onboarding step where a whole screen is
/// dedicated to this one question.
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
          ActivityOptionTile(
            level: levels[i],
            selected: value == levels[i],
            onTap: () => onChanged(levels[i]),
          ),
          if (i < levels.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// One selectable activity option — label, description and the ×factor that
/// scales the estimate. Shared by the onboarding tiles and the settings sheet.
class ActivityOptionTile extends StatelessWidget {
  const ActivityOptionTile({
    super.key,
    required this.level,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final ActivityLevel level;
  final bool selected;
  final VoidCallback onTap;

  /// Tighter padding — used inside the settings bottom sheet so every option
  /// fits on screen without scrolling. Onboarding keeps the airier tiles.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected ? AppColors.plantain.withValues(alpha: 0.12) : AppColors.barkRaised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 10 : 12,
          ),
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
              const SizedBox(width: 8),
              Text(
                '×${level.factor}',
                style: AppText.label(
                  color: selected ? AppColors.plantain : AppColors.smoke,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact activity picker for settings. One clearly-labelled field shows the
/// current choice; tapping it opens a bottom sheet with all five options
/// (label, description and ×factor), so the profile form stays short and the
/// field's purpose is explicit.
class ActivityDropdown extends StatelessWidget {
  const ActivityDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final ActivityLevel? value;
  final ValueChanged<ActivityLevel> onChanged;
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<ActivityLevel>(
      context: context,
      // Let the sheet grow to its natural height so all five options are
      // visible at once instead of being capped at 9/16 of the screen.
      isScrollControlled: true,
      builder: (context) => _ActivityLevelSheet(value: value),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Activity level',
          errorText: errorText,
          helperText: current == null
              ? 'Scales your maintenance estimate'
              : '×${current.factor} — ${current.description}',
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          current?.label ?? 'Choose a level',
          style: current == null ? AppText.bodyMuted() : AppText.dataM(),
        ),
      ),
    );
  }
}

/// Bottom sheet behind [ActivityDropdown]: every level with its description
/// and factor, and the current one pre-selected.
class _ActivityLevelSheet extends StatelessWidget {
  const _ActivityLevelSheet({required this.value});

  final ActivityLevel? value;

  @override
  Widget build(BuildContext context) {
    final levels = ActivityLevel.values;
    return SafeArea(
      top: false,
      // isScrollControlled + a min-height column make the sheet hug its
      // content, so all five compact options are visible at once on phones.
      // (Same content-sized pattern as the app's other sheets.)
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity level', style: AppText.headline()),
            const SizedBox(height: 4),
            Text(
              'How active is an average week for you? It scales your '
              'estimate (×1.2–×1.9).',
              style: AppText.bodyMuted(),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < levels.length; i++) ...[
              ActivityOptionTile(
                level: levels[i],
                selected: value == levels[i],
                compact: true,
                onTap: () => Navigator.pop(context, levels[i]),
              ),
              if (i < levels.length - 1) const SizedBox(height: 6),
            ],
          ],
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

/// A tappable date-of-birth field shared by onboarding and Settings →
/// Targets. Opens a calendar picker and shows the chosen date plus the
/// derived age, so "how old am I?" is answered for the user instead of
/// asking them to type a number that goes stale.
class BirthdayField extends StatelessWidget {
  const BirthdayField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final age = value == null ? null : ageFromBirthday(value!, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate:
                  value ?? DateTime(now.year - 30, now.month, now.day),
              firstDate: DateTime(now.year - 120, now.month, now.day),
              lastDate: now,
              helpText: 'When were you born?',
            );
            if (picked != null) {
              onChanged(DateTime(picked.year, picked.month, picked.day));
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Date of birth',
              errorText: errorText,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
            child: Text(
              value == null
                  ? 'Pick a date'
                  : DateFormat.yMMMMd().format(value!),
              style:
                  value == null ? AppText.bodyMuted() : AppText.dataM(),
            ),
          ),
        ),
        if (age != null) ...[
          const SizedBox(height: 6),
          Text(
            '$age ${age == 1 ? 'year' : 'years'} old — used in the '
            'calorie estimate.',
            style: AppText.bodyMuted(fontSize: 12),
          ),
        ],
      ],
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
