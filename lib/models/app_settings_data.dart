import 'package:flutter/material.dart';

import '../utils/calorie_math.dart';

/// Non-secret user configuration, persisted in the local `app_settings`
/// table. Secrets (API key, vocabulary) stay in the platform secure store.
class AppSettingsData {
  const AppSettingsData({
    this.maintenanceKcal = 2200,
    this.heightUnit = 'cm',
    this.reminderEnabled = false,
    this.reminderTime = const TimeOfDay(hour: 20, minute: 0),
    this.memoryEnabled = true,
    this.heightCm,
    this.birthday,
    this.sex,
    this.activityLevel,
    this.profileCompleted = false,
    this.targetCustom,
  });

  /// The daily target used by the calendar colors and the coach: eat
  /// at/under this to stay on plan.
  final double maintenanceKcal;

  /// Display unit for height input ('cm' or 'ft'); the height itself is
  /// always stored in centimetres in [heightCm].
  final String heightUnit;

  final bool reminderEnabled;
  final TimeOfDay reminderTime;

  /// Master switch for the coach memory layer (write + inject).
  final bool memoryEnabled;

  // ---- First-run profile (feeds the maintenance estimate) ---------------

  /// Height in centimetres, from onboarding / Settings → Targets.
  final double? heightCm;

  /// Date of birth. Age is derived from it on the fly ([ageOn]) so the
  /// estimate never uses a stale number.
  final DateTime? birthday;

  final Sex? sex;

  final ActivityLevel? activityLevel;

  /// True once the first-run onboarding has been completed, so the shell
  /// stops showing the questionnaire.
  final bool profileCompleted;

  /// Whether the daily target was hand-set in Settings → Targets (custom
  /// mode) rather than derived from the profile and weigh-ins. Always-on
  /// weight sync pauses for hand-set targets so a weigh-in never silently
  /// overrides an explicit number. Null on legacy installs, where the mode
  /// was inferred instead of stored.
  final bool? targetCustom;

  /// True when the target was hand-set in Settings → Targets. Always-on
  /// weight sync pauses for hand-set targets so it never overrides an
  /// explicit choice. Null on legacy installs, where the mode was inferred
  /// rather than stored.
  bool get isTargetCustom => targetCustom ?? false;

  /// Whole years old on [on] (defaults to today), or null without a
  /// birthday. Derived, never stored.
  int? ageOn([DateTime? on]) {
    final b = birthday;
    if (b == null) return null;
    return ageFromBirthday(b, on ?? DateTime.now());
  }

  /// Whole years old today.
  int? get age => ageOn();

  /// The whole profile is present, so the maintenance estimate can be made.
  bool get hasProfile =>
      heightCm != null && birthday != null && sex != null && activityLevel != null;

  AppSettingsData copyWith({
    double? maintenanceKcal,
    String? heightUnit,
    bool? reminderEnabled,
    TimeOfDay? reminderTime,
    bool? memoryEnabled,
    double? heightCm,
    DateTime? birthday,
    Sex? sex,
    ActivityLevel? activityLevel,
    bool? profileCompleted,
    bool? targetCustom,
  }) =>
      AppSettingsData(
        maintenanceKcal: maintenanceKcal ?? this.maintenanceKcal,
        heightUnit: heightUnit ?? this.heightUnit,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderTime: reminderTime ?? this.reminderTime,
        memoryEnabled: memoryEnabled ?? this.memoryEnabled,
        heightCm: heightCm ?? this.heightCm,
        birthday: birthday ?? this.birthday,
        sex: sex ?? this.sex,
        activityLevel: activityLevel ?? this.activityLevel,
        profileCompleted: profileCompleted ?? this.profileCompleted,
        targetCustom: targetCustom ?? this.targetCustom,
      );
}
