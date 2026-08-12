import 'package:flutter/material.dart';

import '../utils/calorie_math.dart';

/// Non-secret user configuration, persisted in the local `app_settings`
/// table. Secrets (API key, vocabulary) stay in the platform secure store.
class AppSettingsData {
  const AppSettingsData({
    this.maintenanceKcal = 2200,
    this.weightUnit = 'kg',
    this.heightUnit = 'cm',
    this.reminderEnabled = false,
    this.reminderTime = const TimeOfDay(hour: 20, minute: 0),
    this.memoryEnabled = true,
    this.heightCm,
    this.age,
    this.sex,
    this.activityLevel,
    this.profileCompleted = false,
  });

  /// The daily target used by the calendar colors and the coach: eat
  /// at/under this to stay on plan.
  final double maintenanceKcal;

  /// 'kg' or 'lb'.
  final String weightUnit;

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

  /// Age in years.
  final int? age;

  final Sex? sex;

  final ActivityLevel? activityLevel;

  /// True once the first-run onboarding has been completed, so the shell
  /// stops showing the questionnaire.
  final bool profileCompleted;

  /// The whole profile is present, so the maintenance estimate can be made.
  bool get hasProfile =>
      heightCm != null && age != null && sex != null && activityLevel != null;

  bool get usesKg => weightUnit == 'kg';

  AppSettingsData copyWith({
    double? maintenanceKcal,
    String? weightUnit,
    String? heightUnit,
    bool? reminderEnabled,
    TimeOfDay? reminderTime,
    bool? memoryEnabled,
    double? heightCm,
    int? age,
    Sex? sex,
    ActivityLevel? activityLevel,
    bool? profileCompleted,
  }) =>
      AppSettingsData(
        maintenanceKcal: maintenanceKcal ?? this.maintenanceKcal,
        weightUnit: weightUnit ?? this.weightUnit,
        heightUnit: heightUnit ?? this.heightUnit,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderTime: reminderTime ?? this.reminderTime,
        memoryEnabled: memoryEnabled ?? this.memoryEnabled,
        heightCm: heightCm ?? this.heightCm,
        age: age ?? this.age,
        sex: sex ?? this.sex,
        activityLevel: activityLevel ?? this.activityLevel,
        profileCompleted: profileCompleted ?? this.profileCompleted,
      );
}
