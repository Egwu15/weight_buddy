import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/data/seed_demo.dart';
import 'package:weight_buddy/main.dart';
import 'package:weight_buddy/models/log_entry.dart';

/// On-device test of the edit/resend flow: a real SQLite database and the real
/// widget tree, driven like a widget test but running on the emulator.
///
/// Demo data is seeded directly (no API key needed), then the timeline's
/// pencil opens the editor, a quantity is fixed and an item added, and the
/// save is verified in the database — same id and timestamp, updated values.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Wipes the local store and seeds the demo dataset, then returns the
  /// pre-edit "Akara and pap" row for today so the test can assert the edit
  /// kept its identity.
  Future<(AppDatabase, LogEntry)> seed() async {
    final db = await AppDatabase.open();
    await db.wipeAllData();
    await db.setSetting('maintenance_kcal', '2300');
    await seedDemoData(db, force: true);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final akara =
        (await db.logsForDay(today)).firstWhere((e) => e.summary == 'Akara and pap');
    return (db, akara);
  }

  testWidgets('edit a meal from the timeline pencil: quantity + new item, '
      'saved in place', (tester) async {
    final (db, akara) = await seed();
    await db.close();

    await tester.pumpWidget(const ProviderScope(child: WeightBuddyApp()));
    await tester.pumpAndSettle();

    // Bring the timeline into view (scroll to the first entry's title — the
    // pencil finder only exists once the tile is built).
    await tester.scrollUntilVisible(
      find.text('Akara and pap'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit entry').first);
    await tester.pumpAndSettle();

    // The editor is pre-filled from the saved entry.
    expect(find.text('EDIT MEAL'), findsOneWidget);
    expect(find.text('Akara and pap'), findsWidgets);

    // Quantity: 2 pieces -> 3 pieces (×1.5 ⇒ 250 → 375 kcal).
    await tester.enterText(
      find.byKey(const ValueKey('entry-editor-qty-0')),
      '3 pieces',
    );
    await tester.pump();

    // And add the bit they forgot: a drink.
    await tester.tap(find.byKey(const ValueKey('entry-editor-add-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('entry-editor-add-name')),
      'Watermelon',
    );
    await tester.enterText(
      find.byKey(const ValueKey('entry-editor-add-kcal')),
      '120',
    );
    // The add-form sits below the fold on a phone — bring it into view first.
    await tester.ensureVisible(
      find.byKey(const ValueKey('entry-editor-add-save')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-editor-add-save')));
    await tester.pumpAndSettle();
    expect(find.text('Watermelon'), findsOneWidget);

    // Save and verify in the real database: updated in place.
    await tester.ensureVisible(find.byKey(const ValueKey('entry-editor-save')));
    await tester.tap(find.byKey(const ValueKey('entry-editor-save')));
    await tester.pumpAndSettle();

    final db2 = await AppDatabase.open();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final after = (await db2.logsForDay(today))
        .firstWhere((e) => e.summary == 'Akara and pap');
    await db2.close();

    expect(after.id, akara.id, reason: 'edit must keep the row id');
    expect(after.timestamp, akara.timestamp,
        reason: 'edit must keep the original time');
    expect(after.calories, closeTo(250 * 1.5 + 200 + 120, 0.01));
    expect(after.items, hasLength(3));
    expect(after.items.last.name, 'Watermelon');
    expect(after.items.last.calories, closeTo(120, 0.01));
  });

  testWidgets('the details sheet offers an edit action that opens the editor',
      (tester) async {
    final (db, _) = await seed();
    await db.close();

    await tester.pumpWidget(const ProviderScope(child: WeightBuddyApp()));
    await tester.pumpAndSettle();

    // Open the details sheet by tapping the timeline row.
    await tester.scrollUntilVisible(
      find.text('Akara and pap'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Akara and pap'));
    await tester.pumpAndSettle();

    expect(find.text('Edit this entry'), findsOneWidget);
    await tester.tap(find.text('Edit this entry'));
    await tester.pumpAndSettle();

    // The editor took over; Cancel closes it without saving.
    expect(find.text('EDIT MEAL'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('EDIT MEAL'), findsNothing);
  });
}
