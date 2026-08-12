import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/models/app_settings_data.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/utils/periods.dart';

const _settings = AppSettingsData(maintenanceKcal: 2200);

class _StubSettingsController extends AppSettingsController {
  _StubSettingsController(this._data);

  final AppSettingsData _data;

  @override
  Future<AppSettingsData> build() async => _data;
}

LogEntry _meal(DateTime day, double kcal) => LogEntry(
      timestamp: DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
      type: EntryType.meal,
      summary: 'Meal',
      calories: kcal,
      proteinG: 0,
      carbsG: 0,
      fatG: 0,
      rawTranscript: 'test',
    );

LogEntry _exercise(DateTime day, double kcal) => LogEntry(
      timestamp: DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
      type: EntryType.exercise,
      summary: 'Workout',
      calories: kcal,
      proteinG: 0,
      carbsG: 0,
      fatG: 0,
      rawTranscript: 'test',
    );

void main() {
  setUpAll(sqfliteFfiInit);

  Future<AppDatabase> openDb() async {
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    return db;
  }

  Future<ProviderContainer> makeContainer(AppDatabase db) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        appSettingsProvider.overrideWith(
            () => _StubSettingsController(_settings)),
      ],
    );
    addTearDown(container.dispose);
    return Future.value(container);
  }

  test('startOfWeek lands on the Monday of the containing week', () {
    // 2026-08-12 is a Wednesday; its week starts Monday 2026-08-10.
    final monday = startOfWeek(DateTime(2026, 8, 12));
    expect(monday, DateTime(2026, 8, 10));

    // A Monday maps to itself; a Sunday still belongs to the same week.
    expect(startOfWeek(DateTime(2026, 8, 10)), DateTime(2026, 8, 10));
    expect(startOfWeek(DateTime(2026, 8, 16)), DateTime(2026, 8, 10));
    expect(startOfWeek(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
  });

  test('week totals sum eaten/burned and budget 7 daily targets', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    await db.insertLog(_meal(DateTime(2026, 8, 12), 2000)); // Wed
    await db.insertLog(_exercise(DateTime(2026, 8, 13), 500)); // Thu

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    expect(period.totals.eatenKcal, 2000);
    expect(period.totals.burnedKcal, 500);
    expect(period.totals.netKcal, 1500);
    expect(period.budgetKcal, 7 * 2200);
    expect(period.leftKcal, 7 * 2200 - 1500);
  });

  test('budget honours the per-day maintenance snapshot when one exists', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // Wednesday was logged under a raised target of 3000; the other six days
    // of the week still count the current 2200.
    await db.insertLog(
      _meal(DateTime(2026, 8, 12), 1000),
      maintenanceKcal: 3000,
    );

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    expect(period.budgetKcal, 3000 + 6 * 2200);
  });

  test('unlogged days fall back to the current maintenance target', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    await db.insertLog(
      _meal(DateTime(2026, 8, 10), 600),
      maintenanceKcal: 2000,
    );

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    expect(period.budgetKcal, 2000 + 6 * 2200);
    expect(period.totals.eatenKcal, 600);
  });

  test('month period covers exactly the days in that month', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // 31 August 2026 (a Monday, last day of the month) counts; the 1st of
    // September belongs to September's budget, not August's.
    await db.insertLog(_meal(DateTime(2026, 8, 31), 900));
    await db.insertLog(_meal(DateTime(2026, 9, 1), 800));

    final august = await container
        .read(monthPeriodTotalsProvider(DateTime(2026, 8, 15)).future);
    expect(august.totals.eatenKcal, 900);
    expect(august.budgetKcal, 31 * 2200);
    expect(august.leftKcal, 31 * 2200 - 900);
  });

  test('adjacent weeks stay independent', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    await db.insertLog(_meal(DateTime(2026, 8, 12), 1000));
    await db.insertLog(_meal(DateTime(2026, 8, 19), 500)); // next week

    final thisWeek =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    final nextWeek =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 17)).future);
    expect(thisWeek.totals.eatenKcal, 1000);
    expect(nextWeek.totals.eatenKcal, 500);
  });
}
