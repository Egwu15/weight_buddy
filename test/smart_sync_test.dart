import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/models/app_settings_data.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/models/weigh_in.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/utils/adaptive_math.dart';
import 'package:weight_buddy/utils/calorie_math.dart';

/// The always-on weight sync: a weigh-in that moves the weight meaningfully
/// updates the maintenance target — observed estimate (clamped to the formula)
/// when there's enough logging, formula fallback otherwise — while water-weight
/// wobble and hand-set targets leave it alone.
void main() {
  setUpAll(sqfliteFfiInit);

  Future<AppDatabase> freshDb() async {
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    return db;
  }

  ProviderContainer container(AppDatabase db) {
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A complete profile (175 cm / 1990-05-10 / male / lightly active) with an
  /// automatic target at [maintenanceKcal] kcal. `targetCustom: true` marks it
  /// hand-set; `legacy: true` omits the key entirely to simulate an install
  /// from before the mode was persisted.
  Future<void> seedProfile(
    AppDatabase db, {
    double maintenanceKcal = 2200,
    bool? targetCustom,
    bool legacy = false,
  }) async {
    await db.setSetting('maintenance_kcal', maintenanceKcal.toString());
    await db.setSetting('height_cm', '175');
    await db.setSetting('birthday', '1990-05-10');
    await db.setSetting('sex', 'male');
    await db.setSetting('activity_level', 'light');
    if (!legacy) {
      await db.setSetting('target_custom', (targetCustom ?? false).toString());
    }
  }

  /// A weigh-in [daysAgo] days before today at [kg].
  Future<void> seedWeighIn(
      AppDatabase db, {required int daysAgo, required double kg}) {
    final day = DateTime.now().subtract(Duration(days: daysAgo));
    return db.insertWeighIn(
        WeighIn(date: DateTime(day.year, day.month, day.day), weightKg: kg));
  }

  /// Logs a 2000 kcal meal [daysAgo] days back (enough days for the observed
  /// estimate to be trustworthy).
  Future<void> seedMeal(AppDatabase db, int daysAgo) {
    final ts = DateTime.now()
        .subtract(Duration(days: daysAgo))
        .add(const Duration(hours: 13))
        .millisecondsSinceEpoch;
    return db.insertLog(LogEntry(
      timestamp: ts,
      type: EntryType.meal,
      summary: 'Meal',
      calories: 2000,
      proteinG: 0,
      carbsG: 0,
      fatG: 0,
      rawTranscript: 'meal',
    ));
  }

  /// The formula estimate for a complete profile at [kg].
  double formulaKg(AppSettingsData s, double kg) {
    return CalorieMath.maintenance(
      weightKg: kg,
      heightCm: s.heightCm!,
      age: s.age!,
      sex: s.sex!,
      activity: s.activityLevel!,
    );
  }

  test('a ≥0.5 kg weigh-in updates the target from the observed estimate',
      () async {
    final db = await freshDb();
    await seedProfile(db);
    await seedWeighIn(db, daysAgo: 21, kg: 85);
    // 12 logged days across the window → the observed estimate is trustworthy.
    for (var i = 0; i <= 21; i++) {
      if (i.isEven) await seedMeal(db, i);
    }
    final c = container(db);
    final before = await c.read(appSettingsProvider.future);
    final base = before.copyWith(heightCm: 175, birthday: DateTime(1990, 5, 10));

    // 2.0 kg drop — a real change, not water-weight noise.
    final updated = await c.read(weighInsProvider.notifier).add(
          WeighIn(date: DateTime.now(), weightKg: 83),
        );

    final weighIns = await db.weighIns();
    final intake = await _intakeFromDb(db);
    final observed = AdaptiveMath.observedMaintenance(
      weighIns: weighIns,
      dailyIntakeKcal: intake,
      now: DateTime.now(),
    );
    expect(observed, isNotNull);
    final expected =
        AdaptiveMath.clampToFormula(observed!, formulaKg(base, 83)).roundToDouble();

    expect(updated, expected);
    final after = await c.read(appSettingsProvider.future);
    expect(after.maintenanceKcal, expected);
    // The sync only moves the current target — old days keep their snapshots.
    expect(after.isTargetCustom, isFalse);
    // The change is persisted, not just in-memory, and the weigh-in day's
    // snapshot follows so its calendar/streak judgment matches the target.
    final persisted =
        double.parse((await db.getSetting('maintenance_kcal'))!);
    expect(persisted, expected);
    final today = DateTime.now();
    expect(
      await db.dayMaintenance(DateTime(today.year, today.month, today.day)),
      expected,
    );
  });

  test('a <0.5 kg weigh-in (water-weight wobble) leaves the target alone',
      () async {
    final db = await freshDb();
    await seedProfile(db);
    await seedWeighIn(db, daysAgo: 21, kg: 85);
    for (var i = 0; i <= 21; i++) {
      if (i.isEven) await seedMeal(db, i);
    }
    final c = container(db);

    final updated = await c.read(weighInsProvider.notifier).add(
          WeighIn(date: DateTime.now(), weightKg: 85.3),
        );

    expect(updated, isNull);
    expect((await c.read(appSettingsProvider.future)).maintenanceKcal, 2200);
  });

  test('with too little logging the target follows the formula from the new '
      'weight (works from the first weigh-in)', () async {
    final db = await freshDb();
    await seedProfile(db, maintenanceKcal: 2000);
    await seedWeighIn(db, daysAgo: 21, kg: 85);
    final c = container(db);
    final settings = await c.read(appSettingsProvider.future);

    final updated = await c.read(weighInsProvider.notifier).add(
          WeighIn(date: DateTime.now(), weightKg: 83),
        );

    final expected = formulaKg(settings, 83).roundToDouble();
    expect(updated, expected);
    expect((await c.read(appSettingsProvider.future)).maintenanceKcal, expected);
    // Persisted, not just in-memory.
    final persisted =
        double.parse((await db.getSetting('maintenance_kcal'))!);
    expect(persisted, expected);
  });

  test('a hand-set (custom) target is never overridden by a weigh-in',
      () async {
    final db = await freshDb();
    await seedProfile(db, maintenanceKcal: 1800, targetCustom: true);
    await seedWeighIn(db, daysAgo: 21, kg: 85);
    for (var i = 0; i <= 21; i++) {
      if (i.isEven) await seedMeal(db, i);
    }
    final c = container(db);

    final updated = await c.read(weighInsProvider.notifier).add(
          WeighIn(date: DateTime.now(), weightKg: 83),
        );

    expect(updated, isNull);
    expect((await c.read(appSettingsProvider.future)).maintenanceKcal, 1800);
  });

  test('a legacy install whose target differs from the formula is treated as '
      'custom (no override)', () async {
    final db = await freshDb();
    // No target_custom key: a legacy install where the mode was inferred.
    await seedProfile(db, maintenanceKcal: 1800, legacy: true);
    await seedWeighIn(db, daysAgo: 21, kg: 85);
    for (var i = 0; i <= 21; i++) {
      if (i.isEven) await seedMeal(db, i);
    }
    final c = container(db);

    final updated = await c.read(weighInsProvider.notifier).add(
          WeighIn(date: DateTime.now(), weightKg: 83),
        );

    expect(updated, isNull);
    expect((await c.read(appSettingsProvider.future)).maintenanceKcal, 1800);
  });

  test('deleting a weigh-in re-syncs the target', () async {
    final db = await freshDb();
    await seedProfile(db);
    await seedWeighIn(db, daysAgo: 21, kg: 85);
    final c = container(db);
    final settings = await c.read(appSettingsProvider.future);

    final added = await c.read(weighInsProvider.notifier).add(
          WeighIn(date: DateTime.now(), weightKg: 83),
        );
    expect(added, formulaKg(settings, 83).roundToDouble());

    // Removing the newest weigh-in leaves a single weigh-in → the target
    // reverts to the formula for that remaining weight.
    final newest = (await db.weighIns()).first;
    await c.read(weighInsProvider.notifier).delete(newest);

    final expected = formulaKg(settings, 85).roundToDouble();
    expect((await c.read(appSettingsProvider.future)).maintenanceKcal, expected);
    expect(double.parse((await db.getSetting('maintenance_kcal'))!), expected);
  });
}

/// Rebuilds the 60-day daily-intake map exactly as the sync does.
Future<Map<DateTime, double>> _intakeFromDb(AppDatabase db) async {
  final now = DateTime.now();
  final logs = await db.logsForRange(now.subtract(const Duration(days: 60)), now);
  final intake = <DateTime, double>{};
  for (final e in logs) {
    if (e.type != EntryType.meal) continue;
    final d = DateTime.fromMillisecondsSinceEpoch(e.timestamp).toLocal();
    final day = DateTime(d.year, d.month, d.day);
    intake[day] = (intake[day] ?? 0) + e.calories;
  }
  return intake;
}
