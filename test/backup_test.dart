import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/data/backup_service.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/models/weigh_in.dart';

LogEntry _entry(String summary, {MealType mealType = MealType.breakfast}) =>
    LogEntry(
      timestamp: DateTime(2026, 8, 20, 9).millisecondsSinceEpoch,
      type: EntryType.meal,
      summary: summary,
      calories: 420,
      proteinG: 30,
      carbsG: 40,
      fatG: 12,
      rawTranscript: 'spoken $summary',
      mealType: mealType,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  Future<AppDatabase> freshDb() async {
    databaseFactory = databaseFactoryFfi;
    return AppDatabase.open(path: inMemoryDatabasePath);
  }

  test('export then import round-trips entries, weigh-ins and settings',
      () async {
    final source = await freshDb();
    await source.insertLog(_entry('porridge'));
    await source.insertLog(_entry('rice and stew', mealType: MealType.lunch));
    await source.insertWeighIn(
      WeighIn(date: DateTime(2026, 8, 20), weightKg: 81.4),
    );
    await source.setSetting('maintenance_kcal', '2400');
    await source.setSetting('reminder_time', '19:30');

    final backup = await BackupService.export(source);
    final text = BackupService.encode(backup);
    await source.close();

    // A different, non-empty database — restore must replace, not merge.
    final target = await freshDb();
    await target.insertLog(_entry('should be gone'));
    await target.setSetting('maintenance_kcal', '1111');

    final parsed = BackupService.parse(text);
    await BackupService.import(target, parsed);

    final logs = await target.logsForDay(DateTime(2026, 8, 20));
    expect(logs.map((e) => e.summary).toList()..sort(),
        ['porridge', 'rice and stew']);
    expect(logs.any((e) => e.summary == 'should be gone'), isFalse);
    expect(logs.firstWhere((e) => e.summary == 'porridge').calories, 420);

    final weighIns = await target.weighIns();
    expect(weighIns, hasLength(1));
    expect(weighIns.single.weightKg, 81.4);

    expect(await target.getSetting('maintenance_kcal'), '2400');
    expect(await target.getSetting('reminder_time'), '19:30');
    await target.close();
  });

  test('recordCount ignores settings and counts real records', () async {
    final db = await freshDb();
    await db.insertLog(_entry('porridge'));
    await db.setSetting('maintenance_kcal', '2400');
    final backup = await BackupService.export(db);
    expect(BackupService.recordCount(backup), 1);
    await db.close();
  });

  test('rejects a file that is not a backup', () {
    expect(() => BackupService.parse('{"hello":"world"}'),
        throwsA(isA<BackupException>()));
    expect(() => BackupService.parse('not json at all'),
        throwsA(isA<BackupException>()));
  });

  test('rejects a backup from a newer build', () {
    expect(
      () => BackupService.parse(
          '{"app":"weight_buddy","format":1,"schema":999,"data":{}}'),
      throwsA(isA<BackupException>()),
    );
  });

  test('a row SQLite rejects is skipped, the rest still restore', () async {
    final db = await freshDb();
    await db.insertLog(_entry('good'));
    await db.insertLog(_entry('bad'));
    final backup = await BackupService.export(db);
    final data = backup['data'] as Map;
    data['logs'] = [
      for (final row in data['logs'] as List)
        {...row as Map, if (row['summary'] == 'bad') 'summary': null},
    ];

    final skipped = await BackupService.import(db, backup);

    expect(skipped, 1);
    final restored = await db.logsForDay(DateTime(2026, 8, 20));
    expect(restored.single.summary, 'good');
    await db.close();
  });

  test('a backup missing a table still restores the rest', () async {
    final db = await freshDb();
    await db.insertLog(_entry('kept'));
    final backup = await BackupService.export(db);
    (backup['data'] as Map).remove('memories');
    (backup['data'] as Map).remove('day_maintenance');
    await BackupService.import(db, backup);
    final logs = await db.logsForDay(DateTime(2026, 8, 20));
    expect(logs.single.summary, 'kept');
    await db.close();
  });
}
