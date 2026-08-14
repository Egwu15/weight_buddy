import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/models/weigh_in.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/ui/settings/targets_screen.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  /// A realistic existing install: a full profile with a manual target,
  /// weigh-ins and three weeks of food logs (enough for the observed
  /// maintenance estimate to appear).
  Future<AppDatabase> seedDb() async {
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    await db.setSetting('maintenance_kcal', '1900');
    await db.setSetting('height_cm', '168');
    await db.setSetting('age', '31');
    await db.setSetting('sex', 'male');
    await db.setSetting('activity_level', 'light');
    await db.setSetting('profile_completed', 'true');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 21));
    await db.insertWeighIn(WeighIn(date: start, weightKg: 85));
    await db.insertWeighIn(WeighIn(date: today, weightKg: 83));
    for (var d = 0; d <= 21; d++) {
      await db.insertLog(LogEntry(
        timestamp: start
            .add(Duration(days: d))
            .add(const Duration(hours: 13))
            .millisecondsSinceEpoch,
        type: EntryType.meal,
        summary: 'Lunch',
        calories: 2200,
        proteinG: 100,
        carbsG: 250,
        fatG: 80,
        rawTranscript: 'lunch',
      ));
    }
    return db;
  }

  testWidgets('targets screen works against a real database (manual target '
      'preserved, from-logging card shown, activity edit is safe)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = (await tester.runAsync(() => seedDb()))!;
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await container.read(appSettingsProvider.future);
      await container.read(weighInsProvider.future);
      final observed = await container.read(observedMaintenanceProvider.future);
      expect(observed, isNotNull);
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TargetsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // A manual target (1900) differs from the formula estimate (2434), so
    // the screen opens in custom mode with the saved number in the field.
    expect(find.widgetWithText(TextField, '1900'), findsOneWidget);
    // Enough logging → the adaptive "from your logging" card is present, with
    // the apply action (the old opt-in sync toggle is gone — sync is always on).
    expect(find.text('FROM YOUR LOGGING'), findsOneWidget);
    expect(find.text('Use as my target'), findsOneWidget);

    // Editing the activity level re-calculates safely and never crashes. The
    // settings form uses a compact dropdown: tap the field showing the current
    // choice, then pick a different level from the bottom sheet.
    await tester.tap(find.text('Lightly active'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostly sitting'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Custom mode keeps the manual number, with the estimate hint updated.
    expect(find.textContaining('Your profile suggests'), findsOneWidget);
  });

  testWidgets('activity dropdown shows every option without scrolling',
      (tester) async {
    // 360×844 ≈ a modern phone. Widget tests render with the Ahem font, whose
    // square glyphs inflate text ~2×, so this tall-enough viewport is a strict
    // stand-in for a real small screen.
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = (await tester.runAsync(() => seedDb()))!;
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await container.read(appSettingsProvider.future);
      await container.read(weighInsProvider.future);
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TargetsScreen()),
    ));
    await tester.pumpAndSettle();

    // The profile form is long and the ListView builds lazily — scroll the
    // activity field into view first. The point of this test is the sheet it
    // opens, not where the field sits on the page.
    await tester.dragUntilVisible(
      find.text('Lightly active'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lightly active'));
    await tester.pumpAndSettle();

    // The bottom sheet hugs its content — no overflow, and the last option is
    // on-screen and tappable without scrolling.
    expect(tester.takeException(), isNull);
    expect(find.text('Mostly sitting'), findsOneWidget);
    expect(find.text('Very active').hitTestable(), findsOneWidget);
  });
}
