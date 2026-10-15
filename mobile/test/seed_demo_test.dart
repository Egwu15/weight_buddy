import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/data/seed_demo.dart';
import 'package:weight_buddy/models/log_entry.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('seedDemoData fills every v2 table and is idempotent', () async {
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);

    await seedDemoData(db);

    // Maintenance target is set only when absent.
    expect(await db.getSetting('maintenance_kcal'), '2300');

    final logs = await db.allLogs();
    expect(logs, isNotEmpty);
    expect(logs.where((e) => e.type == EntryType.meal), isNotEmpty);
    expect(logs.where((e) => e.type == EntryType.exercise), isNotEmpty);

    // Today is deliberately busy so the dashboard has a wave to draw.
    final todayLogs = await db.logsForDay(DateTime.now());
    expect(todayLogs, isNotEmpty);

    // Seeded meals are classified, and the mid-afternoon suya is a snack.
    expect(todayLogs.any((e) => e.mealType == MealType.breakfast), isTrue);
    expect(todayLogs.any((e) => e.mealType == MealType.dinner), isTrue);
    expect(todayLogs.any((e) => e.mealType == MealType.snack), isTrue);

    // Strength days are circuits: today's Leg Day A is one timeline row with
    // three exercises nested underneath, like a meal's items.
    final todayWorkouts =
        todayLogs.where((e) => e.type == EntryType.exercise).toList();
    expect(todayWorkouts, hasLength(1));
    final legDay = todayWorkouts.single;
    expect(legDay.summary, 'Leg day: squats, lunges and deadlifts');
    expect(legDay.exerciseItems, hasLength(3));
    expect(
      legDay.exerciseItems.map((i) => i.name),
      containsAll(['Bodyweight squats', 'Walking lunges', 'Romanian deadlifts']),
    );
    // The entry carries the session's total burn.
    expect(legDay.calories, 240);

    // Every seeded day snapshots the maintenance target in effect.
    expect(await db.dayMaintenance(DateTime.now()), 2300);

    expect(await db.weighIns(), isNotEmpty);
    expect(await db.chatMessages(), isNotEmpty);
    expect(await db.memories(), isNotEmpty);
    expect(await db.exercises(), isNotEmpty);

    // A second run without force adds nothing.
    await seedDemoData(db);
    expect(await db.allLogs(), hasLength(logs.length));
  });

  test('seedDemoData(force: true) reseeds after a wipe', () async {
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);

    await seedDemoData(db);
    await db.wipeAllData();

    // A full wipe clears the marker and settings too, so a plain seed is a
    // fresh reseed rather than a no-op…
    await seedDemoData(db);
    expect(await db.allLogs(), isNotEmpty);

    // …and force still reseeds the whole dataset from any state.
    await db.wipeAllData();
    await seedDemoData(db, force: true);
    expect(await db.allLogs(), isNotEmpty);
    expect(await db.memories(), isNotEmpty);
    expect(await db.exercises(), isNotEmpty);
    expect(await db.dayMaintenance(DateTime.now()), 2300);
  });
}
