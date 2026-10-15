import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/data/ai_service.dart';
import 'package:weight_buddy/models/app_settings_data.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/models/weigh_in.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/theme/app_theme.dart';
import 'package:weight_buddy/ui/today/today_screen.dart';
import 'package:weight_buddy/utils/streaks.dart';

/// The edit/resend feature: fix a saved entry — forgot an item, the AI priced
/// something wrong — by re-parsing the words or tweaking the numbers by hand,
/// then saving back in place (same id and timestamp).
/// In-memory logs so the edit flow never touches platform plugins — the same
/// pattern the record-sheet and app widget tests use.
class _FakeLogsController extends DayLogsController {
  List<LogEntry> logs = [];

  @override
  Future<List<LogEntry>> build() async => List.of(logs);

  @override
  Future<void> add(LogEntry entry) async {
    logs.add(entry.copyWith(id: logs.length + 1));
    ref.invalidateSelf();
  }

  @override
  Future<void> delete(LogEntry entry) async {
    logs.removeWhere((e) => e.id == entry.id);
    ref.invalidateSelf();
  }

  @override
  Future<void> edit(LogEntry entry) async {
    final i = logs.indexWhere((e) => e.id == entry.id);
    if (i >= 0) logs[i] = entry;
    ref.invalidateSelf();
  }
}

class _TestSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(token: '', vocabulary: '');
}

class _TestAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettingsData> build() async =>
      const AppSettingsData(profileCompleted: true);
}

class _FakeWeighInsController extends WeighInsController {
  @override
  Future<List<WeighIn>> build() async => const [];
}

/// A meal saved the way the record sheet saves one.
LogEntry _loggedMeal() => LogEntry(
      id: 1,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: EntryType.meal,
      summary: 'Jollof rice',
      calories: 700,
      proteinG: 14,
      carbsG: 110,
      fatG: 20,
      rawTranscript: 'I had two plates of jollof rice',
      items: const [
        MealItem(
            name: 'Jollof Rice',
            quantity: '2 plates',
            calories: 700,
            proteinG: 14,
            carbsG: 110,
            fatG: 20),
      ],
      mealType: MealType.lunch,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('ParsedLog.fromEntry', () {
    test('round-trips a meal with its items, macros and meal type', () {
      const entry = LogEntry(
        timestamp: 1,
        type: EntryType.meal,
        summary: 'Jollof rice and fried chicken',
        calories: 1100,
        proteinG: 52,
        carbsG: 110,
        fatG: 42,
        rawTranscript: 'I had jollof rice and fried chicken',
        items: [
          MealItem(
              name: 'Jollof Rice',
              quantity: '2 plates',
              calories: 700,
              proteinG: 14,
              carbsG: 110,
              fatG: 20),
          MealItem(
              name: 'Fried Chicken',
              quantity: '2 pieces',
              calories: 400,
              proteinG: 38,
              carbsG: 0,
              fatG: 22),
        ],
        mealType: MealType.lunch,
      );

      final parsed = ParsedLog.fromEntry(entry);
      expect(parsed.type, EntryType.meal);
      expect(parsed.summary, 'Jollof rice and fried chicken');
      expect(parsed.items, hasLength(2));
      expect(parsed.items.first.quantity, '2 plates');
      expect(parsed.mealType, MealType.lunch);

      // And back — the editor's save path.
      final back = parsed
          .toEntries(timestamp: 1, rawTranscript: entry.rawTranscript)
          .first;
      expect(back.calories, 1100);
      expect(back.items.first.name, 'Jollof Rice');
      expect(back.mealType, MealType.lunch);
    });

    test('round-trips a multi-exercise workout with its nested exercises', () {
      final entry = LogEntry(
        timestamp: 2,
        type: EntryType.exercise,
        summary: '5 knee press-ups and 5 dips',
        calories: 3,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: 'I did 5 knee press-ups and 5 dips',
        exerciseItems: const [
          ExerciseItem(
              name: 'Knee Press-ups', sets: 1, reps: 5, caloriesBurned: 1),
          ExerciseItem(name: 'Dips', sets: 1, reps: 5, caloriesBurned: 2),
        ],
      );

      final parsed = ParsedLog.fromEntry(entry);
      expect(parsed.exerciseList, hasLength(2));
      expect(parsed.exerciseList.last.name, 'Dips');
      expect(parsed.exerciseList.first.caloriesBurned, 1);

      final back = parsed
          .toEntries(timestamp: 2, rawTranscript: entry.rawTranscript)
          .first;
      expect(back.exerciseItems, hasLength(2));
      expect(back.calories, 3);
    });

    test('wraps a legacy single-exercise row back into the exercises array',
        () {
      final entry = LogEntry(
        timestamp: 3,
        type: EntryType.exercise,
        summary: 'Treadmill',
        calories: 250,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: 'ran on the treadmill for 30 minutes',
        durationMinutes: 30,
      );

      final parsed = ParsedLog.fromEntry(entry);
      final exercise = parsed.exerciseList.single;
      expect(exercise.name, 'Treadmill');
      expect(exercise.durationMinutes, 30);
      expect(exercise.caloriesBurned, 250);

      // The legacy top-level fields are mirrored back on save.
      final back = parsed
          .toEntries(timestamp: 3, rawTranscript: entry.rawTranscript)
          .first;
      expect(back.durationMinutes, 30);
      expect(back.calories, 250);
    });

    test('a meal saved without items gets a synthetic editable item', () {
      // Older saves could hold macros but no parsed items — the editor must
      // still let the user adjust them instead of zeroing the meal.
      final entry = LogEntry(
        timestamp: 4,
        type: EntryType.meal,
        summary: 'Bowl of oats',
        calories: 350,
        proteinG: 12,
        carbsG: 50,
        fatG: 8,
        rawTranscript: 'I had a bowl of oats',
      );

      final parsed = ParsedLog.fromEntry(entry);
      expect(parsed.items, hasLength(1));
      expect(parsed.items.single.name, 'Bowl of oats');
      expect(parsed.items.single.calories, 350);
    });
  });

  group('updateLog', () {
    test('replaces every field in place, keeping id and timestamp', () async {
      databaseFactory = databaseFactoryFfi;
      final db = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(db.close);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final id = await db.insertLog(LogEntry(
        timestamp: ts,
        type: EntryType.meal,
        summary: 'Before',
        calories: 100,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: 'before',
      ));

      await db.updateLog(LogEntry(
        id: id,
        timestamp: ts,
        type: EntryType.meal,
        summary: 'After',
        calories: 250,
        proteinG: 10,
        carbsG: 5,
        fatG: 2,
        rawTranscript: 'after',
        items: const [
          MealItem(
              name: 'After',
              quantity: '1 bowl',
              calories: 250,
              proteinG: 10,
              carbsG: 5,
              fatG: 2),
        ],
        mealType: MealType.dinner,
      ));

      final rows = await db.allLogs();
      expect(rows, hasLength(1), reason: 'update must not add a row');
      expect(rows.single.id, id);
      expect(rows.single.timestamp, ts);
      expect(rows.single.summary, 'After');
      expect(rows.single.calories, 250);
      expect(rows.single.rawTranscript, 'after');
      expect(rows.single.items.single.quantity, '1 bowl');
      expect(rows.single.mealType, MealType.dinner);
    });
  });

  group('DayLogsController.edit', () {
    test('reflects the change in dayLogsProvider and keeps the row', () async {
      databaseFactory = databaseFactoryFfi;
      final db = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final ts = today.add(const Duration(hours: 13)).millisecondsSinceEpoch;
      final id = await db.insertLog(LogEntry(
        timestamp: ts,
        type: EntryType.meal,
        summary: 'Before',
        calories: 500,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: 'before',
      ));

      final before = await container.read(dayLogsProvider.future);
      expect(before.single.summary, 'Before');

      await container.read(dayLogsProvider.notifier).edit(
            before.single.copyWith(
              summary: 'After',
              calories: 999,
              rawTranscript: 'after',
            ),
          );

      final after = await container.read(dayLogsProvider.future);
      expect(after, hasLength(1));
      expect(after.single.id, id);
      expect(after.single.summary, 'After');
      expect(after.single.calories, 999);
      expect(after.single.timestamp, ts);
    });
  });




  group('edit flow', () {
    /// Pumps Today with one lunch on the timeline, backed by in-memory fakes.
    Future<_FakeLogsController> pumpToday(
      WidgetTester tester,
      List<LogEntry> logs,
    ) async {
      final logsController = _FakeLogsController()..logs = List.of(logs);
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(() => logsController),
          appSettingsProvider.overrideWith(_TestAppSettingsController.new),
          weighInsProvider.overrideWith(_FakeWeighInsController.new),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 0, onPlan: 0)),
          weekTotalsProvider.overrideWith(
              (ref, monday) async =>
                  const PeriodTotals(totals: LogTotals(), budgetKcal: 2200)),
          monthPeriodTotalsProvider.overrideWith(
              (ref, month) async =>
                  const PeriodTotals(totals: LogTotals(), budgetKcal: 2200)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TodayScreen(onOpenSettings: () {}, onOpenMonth: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      return logsController;
    }

    testWidgets('timeline pencil opens the editor; quantity + add item save '
        'back in place', (tester) async {
      final logsController = await pumpToday(tester, [_loggedMeal()]);

      // The meal is on the timeline; open the editor from the pencil.
      expect(find.text('Jollof rice'), findsWidgets);
      await tester.tap(find.byTooltip('Edit entry'));
      await tester.pumpAndSettle();

      // Pre-filled: header, item, transcript.
      expect(find.text('EDIT MEAL'), findsOneWidget);
      expect(find.text('Jollof Rice'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      // Fix the quantity: 2 plates -> 4 plates doubles the item's kcal.
      await tester.enterText(
        find.byKey(const ValueKey('entry-editor-qty-0')),
        '4 plates',
      );
      await tester.pump();

      // And add the bit they forgot: a drink.
      await tester.tap(find.byKey(const ValueKey('entry-editor-add-item')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-editor-add-name')),
        'Orange juice',
      );
      await tester.enterText(
        find.byKey(const ValueKey('entry-editor-add-kcal')),
        '90',
      );
      await tester.tap(find.byKey(const ValueKey('entry-editor-add-save')));
      await tester.pumpAndSettle();
      expect(find.text('Orange juice'), findsOneWidget);

      // Save.
      await tester.ensureVisible(
          find.byKey(const ValueKey('entry-editor-save')));
      await tester.tap(find.byKey(const ValueKey('entry-editor-save')));
      await tester.pumpAndSettle();

      // The sheet closed and the entry was updated in place (same id).
      expect(find.text('Save changes'), findsNothing);
      expect(logsController.logs, hasLength(1));
      expect(logsController.logs.single.id, 1);
      expect(logsController.logs.single.calories, 700 * 2 + 90);
      expect(logsController.logs.single.items, hasLength(2));
      expect(logsController.logs.single.items.last.name, 'Orange juice');
      expect(
        logsController.logs.single.rawTranscript,
        'I had two plates of jollof rice',
      );

      // Flush the toast timer so the test ends clean.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('entry details offers an edit action that opens the editor',
        (tester) async {
      await pumpToday(tester, [_loggedMeal()]);

      // Open the details sheet by tapping the timeline row.
      await tester.tap(find.text('Jollof rice'));
      await tester.pumpAndSettle();
      expect(find.text('Edit this entry'), findsOneWidget);

      // The action closes the details and hands off to the editor.
      await tester.tap(find.text('Edit this entry'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT MEAL'), findsOneWidget);

      // Cancel closes the editor without touching the entry.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT MEAL'), findsNothing);
      expect(find.text('Jollof rice'), findsWidgets);
    });
  });
}

