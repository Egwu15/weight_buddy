import 'package:flutter/material.dart';

/// Non-secret user configuration, persisted in the local `app_settings`
/// table. Secrets (API key, vocabulary) stay in the platform secure store.
class AppSettingsData {
  const AppSettingsData({
    this.maintenanceKcal = 2200,
    this.weightUnit = 'kg',
    this.reminderEnabled = false,
    this.reminderTime = const TimeOfDay(hour: 20, minute: 0),
    this.memoryEnabled = true,
  });

  /// The daily target used by the calendar colors and the coach: eat
  /// at/under this to stay on plan.
  final double maintenanceKcal;

  /// 'kg' or 'lb'.
  final String weightUnit;

  final bool reminderEnabled;
  final TimeOfDay reminderTime;

  /// Master switch for the coach memory layer (write + inject).
  final bool memoryEnabled;

  bool get usesKg => weightUnit == 'kg';

  AppSettingsData copyWith({
    double? maintenanceKcal,
    String? weightUnit,
    bool? reminderEnabled,
    TimeOfDay? reminderTime,
    bool? memoryEnabled,
  }) =>
      AppSettingsData(
        maintenanceKcal: maintenanceKcal ?? this.maintenanceKcal,
        weightUnit: weightUnit ?? this.weightUnit,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderTime: reminderTime ?? this.reminderTime,
        memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      );
}
