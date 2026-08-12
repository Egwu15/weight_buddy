import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:weight_buddy/data/openai_service.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/theme/app_theme.dart';
import 'package:weight_buddy/ui/record/record_sheet.dart';

/// A service that parses locally so the test never hits the network or the
/// mic — only the second stage of the pipeline is exercised.
class _FakeService extends OpenAIService {
  _FakeService() : super(apiKey: 'sk-test');

  @override
  Future<ParsedLog> parseTranscript(
    String transcript, {
    String model = 'gpt-4o-mini',
  }) async {
    return const ParsedLog(
      type: EntryType.meal,
      mealType: MealType.lunch,
      summary: 'Jollof rice and fried chicken',
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
      calories: 1100,
      proteinG: 52,
      carbsG: 110,
      fatG: 42,
    );
  }
}

/// A service that blocks until [gate] completes, so the loading state can
/// be observed mid-parse.
class _DelayedService extends OpenAIService {
  _DelayedService(this._gate) : super(apiKey: 'sk-test');

  final Completer<void> _gate;

  @override
  Future<ParsedLog> parseTranscript(
    String transcript, {
    String model = 'gpt-4o-mini',
  }) async {
    await _gate.future;
    return const ParsedLog(
      type: EntryType.meal,
      mealType: MealType.lunch,
      summary: 'Jollof rice and fried chicken',
      calories: 1100,
      proteinG: 52,
      carbsG: 110,
      fatG: 42,
    );
  }
}

/// In-memory logs so saving never touches platform plugins.
class _FakeLogsController extends DayLogsController {
  final List<LogEntry> logs = [];

  @override
  Future<List<LogEntry>> build() async => List.of(logs);

  @override
  Future<void> add(LogEntry entry) async {
    logs.add(entry.copyWith(id: logs.length + 1));
    ref.invalidateSelf();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('record sheet accepts typed input as a voice fallback',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final logsController = _FakeLogsController();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        openaiServiceProvider.overrideWith((ref) => _FakeService()),
        dayLogsProvider.overrideWith(() => logsController),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const RecordSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Idle view offers the typing fallback next to the mic.
    expect(find.text('Log by voice'), findsOneWidget);
    expect(find.text('Type instead'), findsOneWidget);

    await tester.tap(find.text('Type instead'));
    await tester.pumpAndSettle();

    expect(find.text('Log by typing'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'two plates of jollof rice and fried chicken',
    );
    await tester.tap(find.text('Parse'));
    await tester.pumpAndSettle();

    // Parsed result shown for confirmation, labelled as typed.
    expect(find.text('Does this look right?'), findsOneWidget);
    expect(find.textContaining('You wrote:'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The sheet closed and the typed entry went through the same pipeline.
    expect(find.text('Does this look right?'), findsNothing);
    expect(logsController.logs, hasLength(1));
    expect(logsController.logs.first.summary, 'Jollof rice and fried chicken');
    expect(logsController.logs.first.mealType, MealType.lunch);
    expect(
      logsController.logs.first.rawTranscript,
      'two plates of jollof rice and fried chicken',
    );
  });

  testWidgets('typing shows a loading state while parsing', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final gate = Completer<void>();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        openaiServiceProvider.overrideWith((ref) => _DelayedService(gate)),
        dayLogsProvider.overrideWith(() => _FakeLogsController()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const RecordSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'two plates of jollof rice');

    await tester.tap(find.text('Parse'));
    await tester.pump();

    // The button is disabled and shows a spinner while parsing.
    expect(find.text('Parsing…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Parsing…'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Does this look right?'), findsOneWidget);
  });
}
