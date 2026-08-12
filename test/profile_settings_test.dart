import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/utils/calorie_math.dart';

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

  test('fresh install starts without a completed profile', () async {
    final db = await freshDb();
    final c = container(db);

    final settings = await c.read(appSettingsProvider.future);
    expect(settings.profileCompleted, isFalse);
    expect(settings.heightCm, isNull);
    expect(settings.sex, isNull);
  });

  test('profile fields survive a save/rebuild round-trip', () async {
    final db = await freshDb();
    final c = container(db);

    final before = await c.read(appSettingsProvider.future);
    await c.read(appSettingsProvider.notifier).save(before.copyWith(
          heightCm: 175,
          age: 25,
          sex: Sex.male,
          activityLevel: ActivityLevel.light,
          maintenanceKcal: 2301,
          profileCompleted: true,
        ));

    final saved = await c.read(appSettingsProvider.future);
    expect(saved.profileCompleted, isTrue);
    expect(saved.heightCm, 175);
    expect(saved.age, 25);
    expect(saved.sex, Sex.male);
    expect(saved.activityLevel, ActivityLevel.light);
    expect(saved.maintenanceKcal, 2301);
    expect(saved.hasProfile, isTrue);
  });

  test('existing data (a log) skips onboarding', () async {
    final db = await freshDb();
    await db.insertLog(LogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: EntryType.meal,
      summary: 'Test entry',
      calories: 100,
      proteinG: 1,
      carbsG: 1,
      fatG: 1,
      rawTranscript: 'test',
    ));
    final c = container(db);

    final settings = await c.read(appSettingsProvider.future);
    expect(settings.profileCompleted, isTrue);
  });

  test('a stored maintenance target skips onboarding too', () async {
    final db = await freshDb();
    await db.setSetting('maintenance_kcal', '2400');
    final c = container(db);

    final settings = await c.read(appSettingsProvider.future);
    expect(settings.profileCompleted, isTrue);
    expect(settings.maintenanceKcal, 2400);
  });
}
