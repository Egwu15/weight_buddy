import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:weight_buddy/data/app_database.dart';
import 'package:weight_buddy/data/coach_context.dart';
import 'package:weight_buddy/main.dart';
import 'package:weight_buddy/models/app_settings_data.dart';
import 'package:weight_buddy/models/chat_message.dart';
import 'package:weight_buddy/models/exercise_recommendation.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/models/memory.dart';
import 'package:weight_buddy/models/weigh_in.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/theme/app_colors.dart';
import 'package:weight_buddy/theme/app_theme.dart';
import 'package:weight_buddy/ui/widgets/ledger_card.dart';
import 'package:weight_buddy/ui/weigh/weigh_in_sheet.dart';
import 'package:weight_buddy/utils/calorie_math.dart';
import 'package:weight_buddy/utils/streaks.dart';

class _TestSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(apiKey: '', vocabulary: '');
}

class _KeyedSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
        apiKey: 'sk-test1234567890abcd',
        vocabulary: 'Jollof, Egusi',
      );
}

/// Default targets so widget tests never touch the database plugin.
class _TestAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettingsData> build() async =>
      const AppSettingsData(profileCompleted: true);
}

/// A brand-new install — no profile yet, so the shell shows onboarding.
/// Saves update state in-memory only, so widget tests never block on real
/// database I/O inside pumpAndSettle.
class _FreshAppSettingsController extends AppSettingsController {
  AppSettingsData _data = const AppSettingsData();

  @override
  Future<AppSettingsData> build() async => _data;

  @override
  Future<void> save(AppSettingsData data) async {
    _data = data;
    state = AsyncData(data);
  }
}

/// In-memory controller so widget tests never touch platform plugins.
class _FakeLogsController extends DayLogsController {
  List<LogEntry> _logs = const [];

  @override
  Future<List<LogEntry>> build() async => _logs;

  @override
  Future<void> add(LogEntry entry) async {
    _logs = [..._logs, entry.copyWith(id: _logs.length + 1)];
    ref.invalidateSelf();
  }

  @override
  Future<void> delete(LogEntry entry) async {
    _logs = _logs.where((e) => e.id != entry.id).toList();
    ref.invalidateSelf();
  }
}

/// In-memory weigh-ins so widget tests never touch platform plugins.
class _FakeWeighInsController extends WeighInsController {
  List<WeighIn> _weighIns = const [];

  /// The recorded list, for assertions.
  List<WeighIn> get items => _weighIns;

  @override
  Future<List<WeighIn>> build() async => _weighIns;

  @override
  Future<double?> add(WeighIn weighIn) async {
    _weighIns = [..._weighIns, weighIn.copyWith(id: _weighIns.length + 1)];
    ref.invalidateSelf();
    return null;
  }

  @override
  Future<void> delete(WeighIn weighIn) async {
    _weighIns = _weighIns.where((e) => e.id != weighIn.id).toList();
    ref.invalidateSelf();
  }
}

/// A completed profile (168 cm / 31 y / male / lightly active) whose stored
/// target matches the formula estimate, so the targets screen opens in auto
/// mode.
class _ProfiledSettingsController extends AppSettingsController {
  @override
  Future<AppSettingsData> build() async {
    final now = DateTime.now();
    return AppSettingsData(
      profileCompleted: true,
      heightCm: 168,
      birthday: DateTime(now.year - 31, now.month, now.day),
      sex: Sex.male,
      activityLevel: ActivityLevel.light,
      maintenanceKcal: 2434,
    );
  }
}

/// A single latest weigh-in of 87 kg.
class _OneWeighInController extends WeighInsController {
  @override
  Future<List<WeighIn>> build() async =>
      [WeighIn(date: DateTime.now(), weightKg: 87)];
}

/// In-memory chat thread so widget tests never touch platform plugins.
class _FakeChatController extends ChatController {
  _FakeChatController([this._messages = const []]);

  List<ChatMessage> _messages;

  @override
  Future<List<ChatMessage>> build() async => _messages;

  @override
  Future<void> addUser(String text) async {
    _messages = [
      ..._messages,
      ChatMessage(
        role: 'user',
        content: text,
        createdAt: _messages.length,
      ),
    ];
    ref.invalidateSelf();
  }

  @override
  Future<void> addAssistant(String text) async {
    _messages = [
      ..._messages,
      ChatMessage(
        role: 'assistant',
        content: text,
        createdAt: _messages.length,
      ),
    ];
    ref.invalidateSelf();
  }

  @override
  Future<void> clear() async {
    _messages = const [];
    ref.invalidateSelf();
  }
}

/// In-memory memories so widget tests never touch platform plugins.
class _FakeMemoriesController extends MemoriesController {
  List<Memory> _memories = const [];

  @override
  Future<List<Memory>> build() async => _memories;

  @override
  Future<void> upsert(Memory memory) async {
    _memories = [..._memories, memory];
    ref.invalidateSelf();
  }

  @override
  Future<void> remove(Memory memory) async {
    _memories = _memories.where((m) => m.id != memory.id).toList();
    ref.invalidateSelf();
  }
}

/// In-memory exercise library so widget tests never touch platform plugins.
class _FakeExercisesController extends ExercisesController {
  List<ExerciseRecommendation> _exercises = const [];

  @override
  Future<List<ExerciseRecommendation>> build() async => _exercises;

  @override
  Future<bool> add(ExerciseRecommendation exercise) async {
    _exercises = [..._exercises, exercise];
    ref.invalidateSelf();
    return true;
  }

  @override
  Future<void> remove(ExerciseRecommendation exercise) async {
    _exercises = _exercises.where((e) => e.id != exercise.id).toList();
    ref.invalidateSelf();
  }
}

Future<ProviderScope> _testApp() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(_TestSettingsController.new),
      dayLogsProvider.overrideWith(_FakeLogsController.new),
      appSettingsProvider.overrideWith(_TestAppSettingsController.new),
      weighInsProvider.overrideWith(_FakeWeighInsController.new),
      chatMessagesProvider.overrideWith(_FakeChatController.new),
      memoriesProvider.overrideWith(_FakeMemoriesController.new),
      exercisesProvider.overrideWith(_FakeExercisesController.new),
      monthTotalsProvider.overrideWith(
          (ref, month) async => const <String, LogTotals>{}),
      streakProvider.overrideWith(
          (ref) async => const Streaks(logging: 4, onPlan: 3)),
    ],
    child: const WeightBuddyApp(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('app', () {
    testWidgets('shows the empty day, ledger and voice dock', (tester) async {
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      expect(find.text('weightbuddy'), findsOneWidget);
      expect(find.text('Log by voice'), findsWidgets);
      expect(find.text('EATEN'), findsOneWidget);
      expect(find.text('BURNED'), findsOneWidget);
      expect(find.text('NET'), findsOneWidget);
      // Maintenance budget left (default 2200, nothing eaten yet).
      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('2,200'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Nothing logged today'),
        120,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Nothing logged today'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Macros'),
        -120,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Macros'), findsOneWidget);
    });

    testWidgets('tapping a meal in the timeline opens its details',
        (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final logs = _FakeLogsController();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(() => logs),
          appSettingsProvider.overrideWith(_TestAppSettingsController.new),
          weighInsProvider.overrideWith(_FakeWeighInsController.new),
          chatMessagesProvider.overrideWith(_FakeChatController.new),
          memoriesProvider.overrideWith(_FakeMemoriesController.new),
          exercisesProvider.overrideWith(_FakeExercisesController.new),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 4, onPlan: 3)),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      await logs.add(LogEntry(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: EntryType.meal,
        summary: 'Jollof rice and fried chicken',
        calories: 1350,
        proteinG: 53.5,
        carbsG: 158,
        fatG: 50,
        rawTranscript: 'jollof rice with 2 pieces of fried chicken',
        items: const [
          MealItem(
            name: 'Jollof rice',
            quantity: '1 plate',
            calories: 900,
            proteinG: 20,
            carbsG: 120,
            fatG: 30,
          ),
          MealItem(
            name: 'Fried chicken',
            quantity: '2 pieces',
            calories: 450,
            proteinG: 33.5,
            carbsG: 38,
            fatG: 20,
          ),
        ],
        mealType: MealType.lunch,
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Jollof rice and fried chicken'),
        250,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(find.text('Jollof rice and fried chicken'));
      await tester.pumpAndSettle();

      // The sheet shows the meal context, per-item breakdown and the
      // spoken text.
      expect(find.text('LUNCH'), findsOneWidget);
      expect(find.text('IN THIS MEAL'), findsOneWidget);
      expect(find.text('Jollof rice'), findsOneWidget);
      expect(find.text('1 plate'), findsOneWidget);
      expect(find.text('900 kcal'), findsOneWidget);
      expect(find.text('YOU SAID'), findsOneWidget);
      expect(find.textContaining('jollof rice with 2 pieces'), findsOneWidget);
    });

    testWidgets('tapping an exercise in the timeline opens its details',
        (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final logs = _FakeLogsController();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(() => logs),
          appSettingsProvider.overrideWith(_TestAppSettingsController.new),
          weighInsProvider.overrideWith(_FakeWeighInsController.new),
          chatMessagesProvider.overrideWith(_FakeChatController.new),
          memoriesProvider.overrideWith(_FakeMemoriesController.new),
          exercisesProvider.overrideWith(_FakeExercisesController.new),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 4, onPlan: 3)),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      await logs.add(LogEntry(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: EntryType.exercise,
        summary: 'Leg day: squats, lunges and deadlifts',
        calories: 240,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: 'ran on the treadmill for 30 minutes',
        exerciseItems: const [
          ExerciseItem(
              name: 'Bodyweight squats',
              sets: 3,
              reps: 12,
              durationMinutes: 6,
              caloriesBurned: 70),
          ExerciseItem(
              name: 'Walking lunges',
              sets: 3,
              reps: 10,
              durationMinutes: 7,
              caloriesBurned: 80),
          ExerciseItem(
              name: 'Romanian deadlifts',
              reps: 10,
              durationMinutes: 7,
              caloriesBurned: 90),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Bodyweight squats + 2 more'),
        250,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first,
      );
      // A circuit workout reads as one timeline row — first exercise plus the
      // remaining count — with a count in the subtitle, not a row per
      // exercise.
      expect(find.text('3 exercises · 240 kcal burned'), findsOneWidget);
      await tester.tap(find.text('Bodyweight squats + 2 more'));
      await tester.pumpAndSettle();

      // The sheet shows the workout context (each exercise with its own
      // structure and burn). No "YOU SAID" quote — the parsed exercise cards
      // already capture what was spoken.
      expect(find.text('EXERCISE'), findsOneWidget);
      expect(find.text('IN THIS WORKOUT'), findsOneWidget);
      expect(find.text('Bodyweight squats'), findsOneWidget);
      expect(find.text('3 × 12 reps'), findsOneWidget);
      // Reps given without sets still show the count ("10 pressups" style).
      expect(find.text('10 reps'), findsOneWidget);
      expect(find.text('80 kcal'), findsOneWidget);
      expect(find.text('90 kcal'), findsOneWidget);
      expect(find.text('YOU SAID'), findsNothing);
    });

    testWidgets('a single-exercise workout shows structure as chips, not an '
        'IN THIS WORKOUT section', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final logs = _FakeLogsController();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(() => logs),
          appSettingsProvider.overrideWith(_TestAppSettingsController.new),
          weighInsProvider.overrideWith(_FakeWeighInsController.new),
          chatMessagesProvider.overrideWith(_FakeChatController.new),
          memoriesProvider.overrideWith(_FakeMemoriesController.new),
          exercisesProvider.overrideWith(_FakeExercisesController.new),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 4, onPlan: 3)),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      await logs.add(LogEntry(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: EntryType.exercise,
        summary: 'ran on the treadmill for 30 minutes',
        calories: 240,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: 'ran on the treadmill for 30 minutes',
        exerciseItems: const [
          ExerciseItem(
              name: 'Treadmill run',
              durationMinutes: 30,
              caloriesBurned: 240),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Treadmill run'),
        250,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(find.text('Treadmill run'));
      await tester.pumpAndSettle();

      // Single exercises read compactly: the headline names the exercise, the
      // kcal line sits under it, and the structure shows as chips — no
      // one-card "IN THIS WORKOUT" section. (The name and kcal text appear
      // twice: once in the timeline tile, once in the sheet.)
      expect(find.text('Treadmill run'), findsNWidgets(2));
      expect(find.text('EXERCISE'), findsOneWidget);
      expect(find.text('240 kcal burned'), findsNWidgets(2));
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('IN THIS WORKOUT'), findsNothing);
    });

    testWidgets('first launch shows onboarding; the tabs stay locked until the '
        'profile is completed', (tester) async {
      // Tall viewport so the whole questionnaire — including the
      // 'Continue' button — is on screen without scrolling.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(_FakeLogsController.new),
          appSettingsProvider.overrideWith(_FreshAppSettingsController.new),
          weighInsProvider.overrideWith(_FakeWeighInsController.new),
          chatMessagesProvider.overrideWith(_FakeChatController.new),
          memoriesProvider.overrideWith(_FakeMemoriesController.new),
          exercisesProvider.overrideWith(_FakeExercisesController.new),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 4, onPlan: 3)),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      // The first flow step, not the tabs — and there's no skip button.
      expect(find.text('Skip for now'), findsNothing);
      expect(find.text('How tall are you?'), findsOneWidget);
      expect(find.text('Today'), findsNothing);

      // Tapping through without answering just bounces with validation —
      // the tabs are unreachable until the profile is completed.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your height in centimetres.'), findsOneWidget);
      expect(find.text('How tall are you?'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('onboarding flow estimates maintenance, saves it and plants a '
        'weigh-in', (tester) async {
      // Tall viewport so each flow step fits without scrolling.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final weighIns = _FakeWeighInsController();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(_FakeLogsController.new),
          appSettingsProvider.overrideWith(_FreshAppSettingsController.new),
          weighInsProvider.overrideWith(() => weighIns),
          chatMessagesProvider.overrideWith(_FakeChatController.new),
          memoriesProvider.overrideWith(_FakeMemoriesController.new),
          exercisesProvider.overrideWith(_FakeExercisesController.new),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 4, onPlan: 3)),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      // No skip button — completion is the only way past the questionnaire.
      expect(find.text('Skip for now'), findsNothing);
      expect(find.text('How tall are you?'), findsOneWidget);

      // Step 1 — height in cm.
      await tester.enterText(find.widgetWithText(TextField, 'Height'), '175');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 2 — weight in kg.
      expect(find.text('What do you weigh today?'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '70');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 3 — birthday and sex.
      expect(find.text('A couple more details'), findsOneWidget);
      await tester.tap(find.text('Pick a date'));
      await tester.pumpAndSettle();
      // Accept the picker's default (30 years ago today) — the derived age
      // is 30, which the estimate then uses.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 4 — activity: the live estimate appears, then finish.
      expect(find.text('How active is your week?'), findsOneWidget);
      await tester.tap(find.text('Lightly active'));
      await tester.pumpAndSettle();
      expect(find.text('2267 kcal/day'), findsOneWidget);

      await tester.tap(find.text('Start tracking'));
      await tester.pumpAndSettle();

      // The shell swapped to the tabs, and the estimate is the new budget.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Start tracking'), findsNothing);
      expect(find.text('2,267'), findsOneWidget);

      // Today's first weigh-in was planted for the estimate.
      expect(weighIns.items, hasLength(1));
      expect(weighIns.items.single.weightKg, closeTo(70, 0.001));
    });

    testWidgets('ledger LEFT turns red when over the maintenance budget',
        (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      // A 320dp phone: all four readouts must fit on one line.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: LedgerCard(
              totals: const LogTotals(eatenKcal: 2500, burnedKcal: 100),
              maintenanceKcal: 2200,
            ),
          ),
        ),
      ));

      // net = 2400, so 200 over budget -> LEFT reads -200 in jollof.
      expect(tester.takeException(), isNull);
      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('-200'), findsOneWidget);
      final value = tester.widget<Text>(find.text('-200'));
      expect(value.style?.color, AppColors.jollof);
    });

    testWidgets('record sheet asks for the key first and can jump to settings',
        (tester) async {
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log by voice').first);
      await tester.pumpAndSettle();

      expect(find.text('Your key goes here first'), findsOneWidget);
      expect(find.text('Hold to speak'), findsNothing);

      // "Go to Settings" actually lands on the Settings tab.
      await tester.tap(find.text('Go to Settings'));
      await tester.pumpAndSettle();
      expect(find.text('OpenAI API key'), findsOneWidget);
    });

    testWidgets('settings hub fans out to focused pages', (tester) async {
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();

      // The hub lists every concern instead of one long grab-bag.
      expect(find.text('OpenAI API key'), findsOneWidget);
      expect(find.text('Targets & profile'), findsOneWidget);
      expect(find.text('Daily reminder'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Your OpenAI key'), findsNothing);

      // OpenAI & voice page.
      await tester.tap(find.text('OpenAI API key'));
      await tester.pumpAndSettle();
      expect(find.text('Your OpenAI key'), findsOneWidget);
      expect(find.text('Foods it should recognize'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Targets & profile page.
      await tester.tap(find.text('Targets & profile'));
      await tester.pumpAndSettle();
      // The target is a live readout, not a manual field.
      expect(find.text('2,200 kcal'), findsOneWidget);
      expect(find.text('Set my own target'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        120,
        scrollable: find
            .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Save changes'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Data page.
      await tester.tap(find.text('Data'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all entries'), findsOneWidget);
      // Demo seeding is a debug-only affordance (kDebugMode is true in tests).
      expect(find.text('Load demo data'), findsOneWidget);
    });

    testWidgets('changing the activity level instantly re-calculates the '
        'daily target', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      // Tall viewport so the whole targets page fits without scrolling.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(_FakeLogsController.new),
          appSettingsProvider.overrideWith(_ProfiledSettingsController.new),
          weighInsProvider.overrideWith(_OneWeighInController.new),
          chatMessagesProvider.overrideWith(_FakeChatController.new),
          memoriesProvider.overrideWith(_FakeMemoriesController.new),
          exercisesProvider.overrideWith(_FakeExercisesController.new),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 4, onPlan: 3)),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Targets & profile'));
      await tester.pumpAndSettle();

      // Lightly active estimate for 87 kg / 168 cm / 31 y / male.
      expect(find.text('2,434 kcal'), findsOneWidget);

      // Flip the activity level — the displayed target must re-calculate
      // on its own, with no extra button and no save yet. The settings form
      // uses a compact dropdown: tap the field, then pick a new level.
      await tester.tap(find.text('Lightly active'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostly sitting'));
      await tester.pumpAndSettle();

      expect(find.text('2,124 kcal'), findsOneWidget);
      expect(find.text('2,434 kcal'), findsNothing);
    });

    testWidgets('saved key is masked and not revealable', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_KeyedSettingsController.new),
          dayLogsProvider.overrideWith(_FakeLogsController.new),
          appSettingsProvider.overrideWith(_TestAppSettingsController.new),
          weighInsProvider.overrideWith(_FakeWeighInsController.new),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI API key'));
      await tester.pumpAndSettle();

      expect(find.text('sk-••••••••abcd'), findsOneWidget);
      expect(find.text('Replace key'), findsOneWidget);
      expect(find.text('sk-test1234567890abcd'), findsNothing);
      expect(find.byTooltip('Show key'), findsNothing);
    });

    testWidgets('weigh-in sheet converts lb input to stored kilograms',
        (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final weighIns = _FakeWeighInsController();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          weighInsProvider.overrideWith(() => weighIns),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showWeighInSheet(context),
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

      // kg/lb is a per-entry input choice; readings are always stored in kg.
      await tester.tap(find.text('lb'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '180');
      await tester.tap(find.text('Save weigh-in'));
      await tester.pumpAndSettle();

      // 180 lb is stored as kilograms.
      expect(weighIns.items.single.weightKg, closeTo(81.646, 0.01));
    });
  });

  group('data', () {
    test('totals aggregate meals and exercise correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      const meal = LogEntry(
        timestamp: 0,
        type: EntryType.meal,
        summary: 'Jollof rice and chicken',
        calories: 1350,
        proteinG: 53.5,
        carbsG: 158,
        fatG: 50,
        rawTranscript: 'jollof',
      );
      final workout = LogEntry(
        timestamp: now,
        type: EntryType.exercise,
        summary: 'Treadmill run',
        calories: 300,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: 'ran 30 minutes',
      );

      final totals = LogTotals.fromEntries([meal, workout]);
      expect(totals.eatenKcal, 1350);
      expect(totals.burnedKcal, 300);
      expect(totals.netKcal, 1050);
      expect(totals.proteinG, 53.5);
      expect(totals.carbsG, 158);
      expect(totals.fatG, 50);
    });

    testWidgets('day logs add and delete through the controller',
        (tester) async {
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final db = await AppDatabase.open(path: inMemoryDatabasePath);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
          ],
        );
        addTearDown(container.dispose);

        await container.read(databaseProvider.future);
        final now = DateTime.now();
        container.read(selectedDayProvider.notifier).setDay(now);

        final controller = container.read(dayLogsProvider.notifier);
        await controller.add(LogEntry(
          timestamp: now.millisecondsSinceEpoch,
          type: EntryType.meal,
          summary: 'Egusi and pounded yam',
          calories: 800,
          proteinG: 20,
          carbsG: 90,
          fatG: 30,
          rawTranscript: 'egusi',
        ));

        final logs = await container.read(dayLogsProvider.future);
        expect(logs, hasLength(1));
        expect(logs.first.summary, 'Egusi and pounded yam');
        expect(logs.first.id, isNotNull);

        await controller.delete(logs.first);
        final after = await container.read(dayLogsProvider.future);
        expect(after, isEmpty);
      });
    });

    testWidgets('v2 tables: settings, weigh-ins, memories, exercises',
        (tester) async {
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final db = await AppDatabase.open(path: inMemoryDatabasePath);

        // Settings KV round-trip.
        expect(await db.getSetting('nope'), isNull);
        await db.setSetting('maintenance_kcal', '2350');
        expect(await db.getSetting('maintenance_kcal'), '2350');
        await db.setSetting('maintenance_kcal', '2400');
        expect(await db.getSetting('maintenance_kcal'), '2400');

        // Weigh-ins round-trip (newest first).
        final day1 = DateTime(2026, 7, 1);
        final day2 = DateTime(2026, 7, 15);
        await db.insertWeighIn(WeighIn(date: day1, weightKg: 84.2));
        final id = await db.insertWeighIn(
            WeighIn(date: day2, weightKg: 83.1, note: 'Morning'));
        final all = await db.weighIns();
        expect(all, hasLength(2));
        expect(all.first.weightKg, 83.1);
        expect(all.first.note, 'Morning');
        await db.deleteWeighIn(id);
        expect(await db.weighIns(), hasLength(1));

        // Memories: latest-wins upsert by topic.
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.upsertMemory(Memory(
          topic: 'training_goal',
          content: 'Marathon in May',
          createdAt: now,
          updatedAt: now,
        ));
        await db.upsertMemory(Memory(
          topic: 'training_goal',
          content: 'Half marathon in June',
          createdAt: now,
          updatedAt: now + 1,
        ));
        final memories = await db.memories();
        expect(memories, hasLength(1));
        expect(memories.first.content, 'Half marathon in June');
        await db.deactivateMemory(memories.first.id!);
        expect(await db.memories(), isEmpty);

        // Exercises: name dedupe (case-insensitive).
        await db.insertExercise(ExerciseRecommendation(
          name: 'Bodyweight Squat',
          sets: 3,
          reps: 10,
          createdAt: now,
        ));
        final dup = await db.insertExercise(ExerciseRecommendation(
          name: 'bodyweight squat',
          sets: 4,
          reps: 12,
          createdAt: now,
        ));
        expect(dup, isNull);
        expect(await db.exercises(), hasLength(1));

        // v3: meal_type round-trips and day maintenance is snapshotted.
        await db.insertLog(LogEntry(
          timestamp: now,
          type: EntryType.meal,
          summary: 'Tagged meal',
          calories: 300,
          proteinG: 10,
          carbsG: 40,
          fatG: 5,
          rawTranscript: '',
          mealType: MealType.lunch,
        ), maintenanceKcal: 2350);
        final tagged = (await db.allLogs()).single;
        expect(tagged.mealType, MealType.lunch);
        expect(await db.dayMaintenance(DateTime.now()), 2350);

        // v4: structured exercise context round-trips.
        await db.insertLog(LogEntry(
          timestamp: now + 1,
          type: EntryType.exercise,
          summary: '20 dips',
          calories: 7,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          rawTranscript: '20 dips',
          sets: 1,
          reps: 20,
          durationMinutes: 0.75,
        ), maintenanceKcal: 2350);
        final dips = (await db.allLogs()).firstWhere((e) => e.summary == '20 dips');
        expect(dips.sets, 1);
        expect(dips.reps, 20);
        expect(dips.durationMinutes, 0.75);

        // A circuit workout persists as one row with the exercises nested.
        await db.insertLog(LogEntry(
          timestamp: now + 2,
          type: EntryType.exercise,
          summary: 'Leg day: squats and lunges',
          calories: 150,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          rawTranscript: 'squats and lunges',
          exerciseItems: const [
            ExerciseItem(
                name: 'Squats',
                sets: 3,
                reps: 12,
                durationMinutes: 6,
                caloriesBurned: 70),
            ExerciseItem(
                name: 'Lunges',
                sets: 3,
                reps: 10,
                durationMinutes: 7,
                caloriesBurned: 80),
          ],
        ), maintenanceKcal: 2350);
        final legDay = (await db.allLogs())
            .firstWhere((e) => e.summary == 'Leg day: squats and lunges');
        expect(legDay.exerciseItems, hasLength(2));
        expect(legDay.exerciseItems[0].name, 'Squats');
        expect(legDay.exerciseItems[0].sets, 3);
        expect(legDay.exerciseItems[1].name, 'Lunges');
        expect(legDay.exerciseItems[1].reps, 10);
        expect(legDay.calories, 150);

        // Wipe clears all user data (snapshots and settings included),
        // returning the app to a fresh-install state.
        await db.wipeAllData();
        expect(await db.weighIns(), isEmpty);
        expect(await db.memories(), isEmpty);
        expect(await db.exercises(), isEmpty);
        expect(await db.getSetting('maintenance_kcal'), isNull);
        expect(await db.dayMaintenance(DateTime.now()), isNull);

        await db.close();
      });
    });

    testWidgets('a v2 database migrates to v4 (meal_type, day maintenance, exercise fields)',
        (tester) async {
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = Directory.systemTemp;
        final path = p.join(dir.path, 'wb_migrate_test_${DateTime.now().millisecondsSinceEpoch}.db');

        // Build a v2 file by hand: logs without the meal_type column.
        final raw = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, v) async {
              await db.execute('''
                CREATE TABLE logs (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  timestamp INTEGER NOT NULL,
                  type TEXT NOT NULL,
                  summary TEXT NOT NULL,
                  calories REAL NOT NULL DEFAULT 0,
                  protein_g REAL NOT NULL DEFAULT 0,
                  carbs_g REAL NOT NULL DEFAULT 0,
                  fat_g REAL NOT NULL DEFAULT 0,
                  raw_transcript TEXT NOT NULL DEFAULT '',
                  items TEXT NOT NULL DEFAULT '[]'
                )
              ''');
              await db.insert('logs', {
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'type': 'meal',
                'summary': 'Legacy meal',
                'calories': 100,
                'protein_g': 1,
                'carbs_g': 1,
                'fat_g': 1,
                'raw_transcript': '',
                'items': '[]',
              });
            },
          ),
        );
        await raw.close();

        final db = await AppDatabase.open(path: path);
        final logs = await db.allLogs();
        expect(logs, hasLength(1));
        // Legacy rows default to the generic meal type.
        expect(logs.first.mealType, MealType.meal);

        // The v4 migration also adds the structured exercise columns, so a
        // workout logged on a migrated install keeps its sets/reps/duration.
        await db.insertLog(LogEntry(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: EntryType.exercise,
          summary: '10 pull-ups',
          calories: 5,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          rawTranscript: '10 pull-ups',
          sets: 1,
          reps: 10,
          durationMinutes: 0.5,
        ), maintenanceKcal: 2400);
        final pullUps = (await db.allLogs())
            .firstWhere((e) => e.summary == '10 pull-ups');
        expect(pullUps.sets, 1);
        expect(pullUps.reps, 10);
        expect(pullUps.durationMinutes, 0.5);

        await db.insertLog(LogEntry(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: EntryType.meal,
          summary: 'New lunch',
          calories: 300,
          proteinG: 10,
          carbsG: 40,
          fatG: 5,
          rawTranscript: '',
          mealType: MealType.lunch,
        ), maintenanceKcal: 2400);
        final all = await db.allLogs();
        expect(all, hasLength(3));
        final legacy = all.firstWhere((e) => e.summary == 'Legacy meal');
        final lunch = all.firstWhere((e) => e.summary == 'New lunch');
        expect(legacy.mealType, MealType.meal);
        expect(lunch.mealType, MealType.lunch);
        expect(await db.dayMaintenance(DateTime.now()), 2400);

        await db.close();
        try {
          await File(path).delete();
        } catch (_) {}
      });
    });

    testWidgets('logsForRange spans multiple local days', (tester) async {
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final db = await AppDatabase.open(path: inMemoryDatabasePath);
        final today = DateTime.now();
        final yesterday = today.subtract(const Duration(days: 1));
        final tomorrow = today.add(const Duration(days: 1));

        Future<void> addAt(DateTime day) => db.insertLog(LogEntry(
              timestamp: DateTime(day.year, day.month, day.day)
                  .millisecondsSinceEpoch,
              type: EntryType.meal,
              summary: day == today ? 'Today meal' : 'Other meal',
              calories: 500,
              proteinG: 0,
              carbsG: 0,
              fatG: 0,
              rawTranscript: '',
            ));

        await addAt(yesterday);
        await addAt(today);
        await addAt(tomorrow);

        final range = await db.logsForRange(yesterday, today);
        expect(range, hasLength(2));
        expect(range.map((e) => e.summary),
            containsAll(['Other meal', 'Today meal']));
        await db.close();
      });
    });

    test('computeStreaks counts logging and on-plan days', () {
      final today = DateTime(2026, 8, 12);
      LogTotals totals(double eaten) => LogTotals(eatenKcal: eaten);

      // Three consecutive logged days; yesterday was over maintenance.
      final perDay = {
        DateTime(2026, 8, 10): totals(2000),
        DateTime(2026, 8, 11): totals(2600),
        DateTime(2026, 8, 12): totals(1800),
      };

      final streaks = computeStreaks(perDay, today, 2200);
      expect(streaks.logging, 3);
      expect(streaks.onPlan, 2);

      // A gap breaks the streak.
      final gapped = Map.of(perDay)
        ..remove(DateTime(2026, 8, 11));
      expect(computeStreaks(gapped, today, 2200).logging, 1);
      expect(computeStreaks(gapped, today, 2200).onPlan, 1);

      // A per-day maintenance snapshot judges that day by its own target:
      // 2026-08-11 was 2600 kcal but under its 2800 snapshot, so it counts.
      final snapshotStreaks = computeStreaks(
        perDay,
        today,
        2200,
        dayMaintenance: {DateTime(2026, 8, 11): 2800},
      );
      expect(snapshotStreaks.onPlan, 3);
    });

    test('coach context includes data, memories and saved exercises', () {
      final context = CoachContext.build(
        today: const LogTotals(
          eatenKcal: 2000,
          burnedKcal: 300,
          proteinG: 100,
          carbsG: 200,
          fatG: 60,
        ),
        last7Days: const [],
        maintenanceKcal: 2200,
        weighIns: [
          WeighIn(date: DateTime(2026, 8, 1), weightKg: 85.0),
        ],
        streaks: const Streaks(logging: 2, onPlan: 1),
        memories: [
          Memory(
            topic: 'training_goal',
            content: 'Marathon in May',
            category: MemoryCategory.goal,
            createdAt: 0,
            updatedAt: 0,
          ),
        ],
        exercises: const [
          ExerciseRecommendation(
            name: 'Bodyweight Squat',
            sets: 3,
            reps: 10,
            createdAt: 0,
          ),
        ],
      );

      expect(context, contains('MAINTENANCE TARGET: 2200'));
      expect(context, contains('TODAY:'));
      expect(context, contains('net 1700 kcal'));
      expect(context, contains('Marathon in May'));
      expect(context, contains('Bodyweight Squat'));
      expect(context, contains('STREAKS: logging 2'));
    });
  });

  group('month + coach', () {
    testWidgets('month tab shows streaks and the calendar grid',
        (tester) async {
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(find.text('LOG STREAK'), findsOneWidget);
      expect(find.text('ON-PLAN'), findsOneWidget);
      expect(find.text('4 d'), findsOneWidget);
      expect(find.text('3 d'), findsOneWidget);
      expect(
        find.text(DateFormat('MMMM yyyy').format(DateTime.now())),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('at / below'),
        120,
        scrollable: find
            .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('at / below'), findsOneWidget);
    });

    testWidgets('tapping a month day jumps Today to that day',
        (tester) async {
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      // Back on Today with its dock.
      expect(find.text('Log by voice'), findsWidgets);
    });

    testWidgets('coach tab shows the welcome card and library entry',
        (tester) async {
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coach'));
      await tester.pumpAndSettle();

      expect(find.text('Your coach, with your numbers'), findsOneWidget);
      expect(find.text('Workouts'), findsWidgets);
      expect(find.text('Memory'), findsWidgets);
      // No key configured -> composer prompts for it.
      expect(find.text('Add your OpenAI key first'), findsOneWidget);
    });

    testWidgets('coach renders a persisted conversation', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_TestSettingsController.new),
          dayLogsProvider.overrideWith(_FakeLogsController.new),
          appSettingsProvider.overrideWith(_TestAppSettingsController.new),
          weighInsProvider.overrideWith(_FakeWeighInsController.new),
          memoriesProvider.overrideWith(_FakeMemoriesController.new),
          exercisesProvider.overrideWith(_FakeExercisesController.new),
          chatMessagesProvider.overrideWith(() => _FakeChatController(const [
                ChatMessage(
                    role: 'user',
                    content: 'How do I progress?',
                    createdAt: 1),
                ChatMessage(
                    role: 'assistant',
                    content: 'Add 2 reps weekly.',
                    createdAt: 2),
              ])),
          monthTotalsProvider.overrideWith(
              (ref, month) async => const <String, LogTotals>{}),
          streakProvider.overrideWith(
              (ref) async => const Streaks(logging: 4, onPlan: 3)),
        ],
        child: const WeightBuddyApp(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coach'));
      await tester.pumpAndSettle();

      expect(find.text('How do I progress?'), findsOneWidget);
      expect(find.text('Add 2 reps weekly.'), findsOneWidget);
    });

    testWidgets('coach header fits on a narrow phone (no overflow)',
        (tester) async {
      // A 320 dp wide phone — the width that used to overflow the header by
      // ~39 px because the subtitle was fixed-width next to three icon
      // buttons. Any RenderFlex overflow here fails the test.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coach'));
      await tester.pumpAndSettle();

      // The header must fit without overflowing at this width.
      expect(find.text('coach'), findsOneWidget);
      expect(find.text('sees today + 7 days + weight'), findsOneWidget);
      // The welcome card is in view (the chips sit below the fold on a
      // short screen and are lazily skipped, which is fine).
      expect(find.text('Your coach, with your numbers'), findsOneWidget);
    });
  });

  group('back button', () {
    /// Records real platform calls so a test can assert the exit path without
    /// the app actually terminating. Only `SystemNavigator.pop` is captured —
    /// the platform channel is noisy (clipboard, sounds, etc.).
    List<String> capturePlatformPops() {
      final pops = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') pops.add(call.method);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      return pops;
    }

    testWidgets('back from another tab returns to Today instead of closing',
        (tester) async {
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Targets & profile'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Back on Today — the app is still alive, with its voice dock.
      expect(find.text('Log by voice'), findsWidgets);
      expect(find.text('Targets & profile'), findsNothing);
    });

    testWidgets('back on Today arms the exit toast; second back exits',
        (tester) async {
      final pops = capturePlatformPops();
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);

      // Second back inside the grace window requests a real exit.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(pops, contains('SystemNavigator.pop'));

      // Flush the toast timer so the test ends with no pending timers.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('a back after the grace window re-arms instead of exiting',
        (tester) async {
      final pops = capturePlatformPops();
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);

      // Let the 2s grace window lapse, then back again: still a toast, no exit.
      await tester.pump(const Duration(seconds: 3));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(pops, isEmpty);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('a tab change resets the exit grace period', (tester) async {
      final pops = capturePlatformPops();
      await tester.pumpWidget(await _testApp());
      await tester.pumpAndSettle();

      // Arm the toast on Today.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);

      // Switching tabs clears the arm, so the next back shows the toast again
      // instead of exiting.
      await tester.tap(find.text('Coach'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Press back again to exit'), findsOneWidget);

      // Now back on Today, a back only re-arms — still no exit.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(pops, isEmpty);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
