import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/data/reminder_service.dart';
import 'package:weight_buddy/models/app_settings_data.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/providers/providers.dart';

const _on = AppSettingsData(
  reminderEnabled: true,
  reminderTime: TimeOfDay(hour: 20, minute: 0),
);

/// Records reminder calls (including the chosen message) instead of touching
/// the notification plugin.
class _FakeReminderService extends ReminderService {
  final List<String> calls = [];

  @override
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    String message = 'Time to log — what did you eat today?',
  }) async {
    calls.add('schedule:$hour:${minute.toString().padLeft(2, '0')}:$message');
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
  }
}

class _StubSettingsController extends AppSettingsController {
  _StubSettingsController(this._data);

  final AppSettingsData _data;

  @override
  Future<AppSettingsData> build() async => _data;
}

LogEntry _entry(EntryType type, {MealType mealType = MealType.meal}) =>
    LogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: type,
      summary: 'Test entry',
      calories: 100,
      proteinG: 1,
      carbsG: 1,
      fatG: 1,
      rawTranscript: 'test',
      mealType: mealType,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  Future<(AppDatabase, _FakeReminderService, ProviderContainer)> setUp(
    AppSettingsData settings,
    List<LogEntry> todayLogs,
  ) async {
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    for (final e in todayLogs) {
      await db.insertLog(e);
    }
    final reminder = _FakeReminderService();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        appSettingsProvider.overrideWith(
            () => _StubSettingsController(settings)),
        reminderServiceProvider.overrideWith((ref) => reminder),
      ],
    );
    addTearDown(container.dispose);
    return (db, reminder, container);
  }

  Future<void> rearm(ProviderContainer container, AppDatabase db) async {
    await container.read(rearmDailyReminderProvider)(db: db);
  }

  test('nothing logged schedules the standard nudge', () async {
    final (db, reminder, container) = await setUp(_on, const []);
    addTearDown(db.close);

    await rearm(container, db);

    expect(reminder.calls,
        ['schedule:20:00:Time to log — what did you eat today?']);
  });

  test('breakfast only leaves lunch and dinner open', () async {
    final (db, reminder, container) = await setUp(
      _on,
      [_entry(EntryType.meal, mealType: MealType.breakfast)],
    );
    addTearDown(db.close);

    await rearm(container, db);

    expect(reminder.calls,
        ['schedule:20:00:Anything else today? (lunch and dinner still open)']);
  });

  test('snacks never fill a meal slot', () async {
    final (db, reminder, container) = await setUp(
      _on,
      [_entry(EntryType.meal, mealType: MealType.snack)],
    );
    addTearDown(db.close);

    await rearm(container, db);

    expect(reminder.calls, [
      'schedule:20:00:Anything else today? (breakfast, lunch and dinner still open)'
    ]);
  });

  test('meals complete but no workout asks about exercise', () async {
    final (db, reminder, container) = await setUp(_on, [
      _entry(EntryType.meal, mealType: MealType.breakfast),
      _entry(EntryType.meal, mealType: MealType.lunch),
      _entry(EntryType.meal, mealType: MealType.dinner),
    ]);
    addTearDown(db.close);

    await rearm(container, db);

    expect(reminder.calls, ['schedule:20:00:Did you get your workout in?']);
  });

  test('a complete day (meals + workout) stays silent', () async {
    final (db, reminder, container) = await setUp(_on, [
      _entry(EntryType.meal, mealType: MealType.breakfast),
      _entry(EntryType.meal, mealType: MealType.lunch),
      _entry(EntryType.meal, mealType: MealType.dinner),
      _entry(EntryType.exercise),
    ]);
    addTearDown(db.close);

    await rearm(container, db);

    expect(reminder.calls, ['cancel']);
  });

  test('cancels when the reminder is switched off', () async {
    final (db, reminder, container) = await setUp(
      const AppSettingsData(reminderEnabled: false),
      const [],
    );
    addTearDown(db.close);

    await rearm(container, db);

    expect(reminder.calls, ['cancel']);
  });

  test('deleting today’s only entry re-arms the nudge', () async {
    final (db, reminder, container) = await setUp(
      _on,
      [_entry(EntryType.meal, mealType: MealType.breakfast)],
    );
    addTearDown(db.close);

    await rearm(container, db);
    expect(reminder.calls, hasLength(1));

    final today = await db.logsForDay(DateTime.now());
    await db.deleteLog(today.first.id!);
    await rearm(container, db);

    expect(reminder.calls, hasLength(2));
    expect(reminder.calls.last,
        'schedule:20:00:Time to log — what did you eat today?');
  });
}
