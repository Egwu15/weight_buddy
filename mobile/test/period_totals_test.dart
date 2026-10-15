import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/models/app_settings_data.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/utils/periods.dart';

const _settings = AppSettingsData(maintenanceKcal: 2200);

/// Fixed "today": Wednesday 12 August 2026, so the 10–16 Aug week is the
/// current week, the 3–9 Aug week and July are in the past, and September is
/// still in the future.
final _now = DateTime(2026, 8, 12);

class _StubSettingsController extends AppSettingsController {
  _StubSettingsController(this._data);

  final AppSettingsData _data;

  @override
  Future<AppSettingsData> build() async => _data;
}

/// Test "today" controller: starts at a fixed date and can be pushed forward
/// to simulate the day rolling over while the app is open.
class _TestNowController extends NowController {
  _TestNowController(this._initial);

  final DateTime _initial;

  @override
  DateTime build() => _initial;

  void jumpTo(DateTime day) => state = day;
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

  Future<ProviderContainer> makeContainer(AppDatabase db, {DateTime? now}) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        appSettingsProvider.overrideWith(
            () => _StubSettingsController(_settings)),
        nowProvider.overrideWith(() => _TestNowController(now ?? _now)),
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

  test('past week keeps the full-period ledger', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // The week of 3–9 Aug is fully before the fixed "today" (12 Aug).
    await db.insertLog(_meal(DateTime(2026, 8, 5), 2000)); // Wed
    await db.insertLog(_exercise(DateTime(2026, 8, 6), 500)); // Thu

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 3)).future);
    expect(period.fromToday, isFalse);
    expect(period.totals.eatenKcal, 2000);
    expect(period.totals.burnedKcal, 500);
    expect(period.totals.netKcal, 1500);
    expect(period.budgetKcal, 7 * 2200);
    expect(period.leftKcal, 7 * 2200 - 1500);
    expect(period.overageKcal, 0);
  });

  test('past-week budget honours the per-day maintenance snapshot', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // Wednesday was logged under a raised target of 3000; the other six days
    // of the week still count the current 2200.
    await db.insertLog(
      _meal(DateTime(2026, 8, 5), 1000),
      maintenanceKcal: 3000,
    );

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 3)).future);
    expect(period.budgetKcal, 3000 + 6 * 2200);
  });

  test('current week budgets from today → end; untracked days count for nothing',
      () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // Fixed today is Wed 12 Aug; the current week runs Mon 10 – Sun 16 Aug.
    // Only the days from the 12th onwards carry a budget.
    await db.insertLog(_meal(DateTime(2026, 8, 12), 2000)); // today

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    expect(period.fromToday, isTrue);
    expect(period.budgetKcal, 5 * 2200); // Wed..Sun
    expect(period.totals.eatenKcal, 2000);
    expect(period.overageKcal, 0);
    expect(period.leftKcal, 5 * 2200 - 2000);
  });

  test('overspend on earlier tracked days carries forward into LEFT', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // Monday (11 Aug) was 300 over target; that debt follows into left.
    await db.insertLog(_meal(DateTime(2026, 8, 11), 2500));
    await db.insertLog(_meal(DateTime(2026, 8, 12), 1000)); // today

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    expect(period.budgetKcal, 5 * 2200);
    expect(period.totals.netKcal, 1000); // today only
    expect(period.overageKcal, 300);
    expect(period.leftKcal, 5 * 2200 - 1000 - 300);
  });

  test('under-eating earlier does not bank extra allowance', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // 200 under on Monday is not banked: left is exactly the remaining days'
    // budget, as if Monday had never been logged.
    await db.insertLog(_meal(DateTime(2026, 8, 11), 2000));

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    expect(period.overageKcal, 0);
    expect(period.leftKcal, 5 * 2200);
  });

  test('overspend uses the per-day maintenance snapshot, not the current target',
      () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // Monday was logged under a raised target of 3000 and ate 3500: the
    // overage is 500 (snapshot), not 1300 (current target).
    await db.insertLog(
      _meal(DateTime(2026, 8, 11), 3500),
      maintenanceKcal: 3000,
    );

    final period =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    expect(period.overageKcal, 500);
    expect(period.leftKcal, 5 * 2200 - 500);
  });

  test('late sign-in: a 30-day month budgets only the remaining days', () async {
    final db = await openDb();
    // 28 April 2026 — a 30-day month — with no logs at all.
    final container = await makeContainer(db, now: DateTime(2026, 4, 28));

    final april =
        await container.read(monthPeriodTotalsProvider(DateTime(2026, 4)).future);
    expect(april.fromToday, isTrue);
    expect(april.budgetKcal, 3 * 2200); // 28, 29, 30
    expect(april.totals.netKcal, 0);
    expect(april.leftKcal, 3 * 2200);
  });

  test('missed days in the middle of the month do not inflate LEFT', () async {
    final db = await openDb();
    final container = await makeContainer(db, now: DateTime(2026, 4, 28));

    // Only today (the 28th) was logged; days 1–27 are untracked and count
    // for nothing.
    await db.insertLog(_meal(DateTime(2026, 4, 28), 2000));

    final april =
        await container.read(monthPeriodTotalsProvider(DateTime(2026, 4)).future);
    expect(april.budgetKcal, 3 * 2200);
    expect(april.totals.eatenKcal, 2000);
    expect(april.overageKcal, 0);
    expect(april.leftKcal, 3 * 2200 - 2000);
  });

  test('past month keeps the full-period review ledger', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    await db.insertLog(_meal(DateTime(2026, 7, 15), 1000));

    final july =
        await container.read(monthPeriodTotalsProvider(DateTime(2026, 7)).future);
    expect(july.fromToday, isFalse);
    expect(july.budgetKcal, 31 * 2200);
    expect(july.leftKcal, 31 * 2200 - 1000);
  });

  test('future month shows the whole period budget', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    final september =
        await container.read(monthPeriodTotalsProvider(DateTime(2026, 9)).future);
    expect(september.fromToday, isFalse);
    expect(september.budgetKcal, 30 * 2200); // September has 30 days
    expect(september.leftKcal, 30 * 2200);
  });

  test('month boundaries stay strict: 31 Aug in August, 1 Sep in September',
      () async {
    final db = await openDb();
    final container = await makeContainer(db);

    // 31 August 2026 (a Monday, last day of the month) counts; the 1st of
    // September belongs to September's budget, not August's.
    await db.insertLog(_meal(DateTime(2026, 8, 31), 900));
    await db.insertLog(_meal(DateTime(2026, 9, 1), 800));

    final august =
        await container.read(monthPeriodTotalsProvider(DateTime(2026, 8)).future);
    expect(august.totals.eatenKcal, 900);
    expect(august.budgetKcal, 20 * 2200); // 12..31 Aug from the fixed today
    expect(august.leftKcal, 20 * 2200 - 900);

    final september =
        await container.read(monthPeriodTotalsProvider(DateTime(2026, 9)).future);
    expect(september.totals.eatenKcal, 800);
    expect(september.budgetKcal, 30 * 2200);
  });

  test('adjacent weeks stay independent', () async {
    final db = await openDb();
    final container = await makeContainer(db);

    await db.insertLog(_meal(DateTime(2026, 8, 12), 1000)); // this week
    await db.insertLog(_meal(DateTime(2026, 8, 19), 500)); // next week

    final thisWeek =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 10)).future);
    final nextWeek =
        await container.read(weekTotalsProvider(DateTime(2026, 8, 17)).future);
    expect(thisWeek.totals.eatenKcal, 1000);
    expect(thisWeek.budgetKcal, 5 * 2200);
    expect(thisWeek.leftKcal, 5 * 2200 - 1000);
    expect(nextWeek.totals.eatenKcal, 500);
    expect(nextWeek.budgetKcal, 7 * 2200);
  });

  test('refreshing "today" re-anchors the ongoing period budget', () async {
    final db = await openDb();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        appSettingsProvider.overrideWith(
            () => _StubSettingsController(_settings)),
        nowProvider.overrideWith(() => _TestNowController(DateTime(2026, 8, 12))),
      ],
    );
    addTearDown(container.dispose);

    final august = await container
        .read(monthPeriodTotalsProvider(DateTime(2026, 8)).future);
    expect(august.fromToday, isTrue);
    expect(august.budgetKcal, 20 * 2200); // 12..31 Aug

    // The day rolls forward while the app stays open: the window must shrink.
    final now =
        container.read(nowProvider.notifier) as _TestNowController;
    now.jumpTo(DateTime(2026, 8, 28));
    final later = await container
        .read(monthPeriodTotalsProvider(DateTime(2026, 8)).future);
    expect(later.budgetKcal, 4 * 2200); // 28, 29, 30, 31
    expect(later.fromToday, isTrue);
  });
}
