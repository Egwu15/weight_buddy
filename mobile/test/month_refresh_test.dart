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

/// Frozen "today": refresh() is a no-op, mirroring production where a same-day
/// refresh writes the same DateTime value and so never triggers a rebuild.
class _FrozenNowController extends NowController {
  _FrozenNowController(this._initial);

  final DateTime _initial;

  @override
  DateTime build() => _initial;

  @override
  void refresh() {}
}

LogEntry _meal(DateTime day, int hour, double kcal) => LogEntry(
      timestamp: DateTime(day.year, day.month, day.day, hour)
          .millisecondsSinceEpoch,
      type: EntryType.meal,
      summary: 'Meal',
      calories: kcal,
      proteinG: 0,
      carbsG: 0,
      fatG: 0,
      rawTranscript: 'test',
    );

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  setUpAll(sqfliteFfiInit);

  test('month page refreshes immediately after logging and deleting', () async {
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final today = DateTime.now();
    final now = DateTime(today.year, today.month, today.day);
    final month = DateTime(now.year, now.month, 1);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        appSettingsProvider.overrideWith(
            () => _StubSettingsController(_settings)),
        nowProvider.overrideWith(() => _FrozenNowController(now)),
      ],
    );
    addTearDown(container.dispose);

    // Keep the month-page providers alive, exactly like the mounted Month tab.
    container.listen(monthTotalsProvider(month), (_, _) {});
    container.listen(monthPeriodTotalsProvider(month), (_, _) {});
    container.listen(monthMaintenanceProvider(month), (_, _) {});
    container.listen(weekTotalsProvider(startOfWeek(now)), (_, _) {});
    container.listen(streakProvider, (_, _) {});

    // A fresh database: nothing logged, everything reads zero.
    final totalsBefore = await container.read(monthTotalsProvider(month).future);
    final periodBefore =
        await container.read(monthPeriodTotalsProvider(month).future);
    final snapsBefore =
        await container.read(monthMaintenanceProvider(month).future);
    final weekBefore =
        await container.read(weekTotalsProvider(startOfWeek(now)).future);
    final streaksBefore = await container.read(streakProvider.future);
    expect(totalsBefore.containsKey(_key(now)), isFalse);
    expect(periodBefore.totals.netKcal, 0);
    expect(snapsBefore, isEmpty);
    expect(weekBefore.totals.netKcal, 0);
    expect(streaksBefore.logging, 0);

    // Log a meal through the app's real write path.
    await container.read(dayLogsProvider.notifier).add(_meal(now, 0, 1000));

    // Calendar tints, both ledgers, the day snapshot and the streaks must
    // re-read the database instead of serving the pre-log cache.
    final totalsAfter = await container.read(monthTotalsProvider(month).future);
    final periodAfter =
        await container.read(monthPeriodTotalsProvider(month).future);
    final snapsAfter =
        await container.read(monthMaintenanceProvider(month).future);
    final weekAfter =
        await container.read(weekTotalsProvider(startOfWeek(now)).future);
    final streaksAfter = await container.read(streakProvider.future);
    expect(totalsAfter[_key(now)]?.eatenKcal, 1000,
        reason: 'calendar tint must refresh after logging');
    expect(periodAfter.totals.netKcal, 1000,
        reason: 'month ledger must refresh after logging');
    expect(snapsAfter[_key(now)], _settings.maintenanceKcal,
        reason: 'day maintenance snapshot must appear after logging');
    expect(weekAfter.totals.netKcal, 1000,
        reason: 'week ledger must refresh after logging');
    expect(streaksAfter.logging, 1,
        reason: 'streaks must refresh after logging');

    // Deleting must refresh too: remove the second meal and the calendar
    // should settle back to the first meal's numbers.
    await container.read(dayLogsProvider.notifier).add(_meal(now, 12, 500));
    final rows = await db.logsForDay(now);
    await container.read(dayLogsProvider.notifier).delete(rows.last);
    final totalsDeleted =
        await container.read(monthTotalsProvider(month).future);
    expect(totalsDeleted[_key(now)]?.eatenKcal, 1000,
        reason: 'calendar must refresh after deleting');
  });
}
