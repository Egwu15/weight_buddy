import '../models/chat_message.dart';
import '../models/exercise_recommendation.dart';
import '../models/log_entry.dart';
import '../models/memory.dart';
import '../models/weigh_in.dart';
import 'app_database.dart';

/// Marker in `app_settings` set once a demo dataset has been loaded, so the
/// seed stays idempotent across launches.
const String kDemoSeeded = 'demo_seeded';

/// Seeds a realistic, busy dataset so every screen can be reviewed without
/// weeks of real logging: ~14 days of meals and workouts, a weigh-in trend,
/// a coach conversation, distilled memories and a saved exercise library.
///
/// Idempotent — once `demo_seeded` is set it is a no-op unless [force] is
/// true (the Settings flow wipes all records first and passes force so the
/// marker alone can’t block a reseed). Secrets and user targets are never
/// touched; maintenance calories are only set when absent.
Future<void> seedDemoData(AppDatabase db, {bool force = false}) async {
  final seeded = await db.getSetting(kDemoSeeded);
  if (seeded == 'true' && !force) return;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  if (await db.getSetting('maintenance_kcal') == null) {
    await db.setSetting('maintenance_kcal', '2300');
  }
  final maintenanceKcal =
      double.tryParse(await db.getSetting('maintenance_kcal') ?? '') ?? 2300;

  // ---- Logs: 14 days of meals + exercise -------------------------------
  for (var i = 0; i <= 13; i++) {
    final day = today.subtract(Duration(days: i));
    for (final m in _dayMeals(day)) {
      await db.insertLog(m, maintenanceKcal: maintenanceKcal);
    }
    for (final e in _dayExercises(day)) {
      await db.insertLog(e, maintenanceKcal: maintenanceKcal);
    }
  }

  // ---- Weigh-ins: a slow downward trend over the past month -------------
  for (var i = 28; i >= 4; i -= 4) {
    final date = today.subtract(Duration(days: i));
    final weightKg = 84.8 - (28 - i) * 0.06;
    await db.insertWeighIn(
      WeighIn(date: date, weightKg: (weightKg * 10).round() / 10),
    );
  }
  await db.insertWeighIn(
    WeighIn(date: today, weightKg: 83.0, note: 'Morning'),
  );

  // ---- Coach conversation ------------------------------------------------
  final yesterday = today.subtract(const Duration(days: 1));
  final chat = <(String, String, int)>[
    ('user',
        'Hey coach, I want to get stronger and drop a few kilos before December.',
        yesterday.millisecondsSinceEpoch + 7 * 3600000),
    ('assistant',
        'Nice goal. Over the last 7 days you’ve been averaging around 2,400 kcal, '
        'a touch over your 2,300 target. A 250 kcal daily cut plus 2–3 strength '
        'sessions a week will do it. Want a simple leg routine to start with?',
        yesterday.millisecondsSinceEpoch + 7 * 3600000 + 60000),
    ('user',
        'Yes please — I’d like a leg day I can do at the gym twice a week.',
        yesterday.millisecondsSinceEpoch + 7 * 3600000 + 120000),
    ('assistant',
        'Leg Day A: 3×12 bodyweight squats, 3×10 walking lunges each leg, '
        '3×10 Romanian deadlifts with 60–90s rest between sets. Start light, add '
        'a little weight each week. I’ve saved it to your workouts.',
        yesterday.millisecondsSinceEpoch + 7 * 3600000 + 180000),
    ('user', 'I usually train in the evening after work, around 7pm.',
        today.millisecondsSinceEpoch + 19 * 3600000),
    ('assistant',
        'Evening training works well — just have a protein snack about an hour '
        'before, like grilled suya. Remembered that for our future chats.',
        today.millisecondsSinceEpoch + 19 * 3600000 + 60000),
  ];
  for (final (role, content, ts) in chat) {
    await db.insertChatMessage(ChatMessage(
      role: role,
      content: content,
      createdAt: ts,
    ));
  }

  // ---- Memories ---------------------------------------------------------
  final ms = DateTime.now().millisecondsSinceEpoch;
  await db.upsertMemory(Memory(
    topic: 'training_goal',
    content: 'Wants to get stronger and drop a few kilos before December',
    category: MemoryCategory.goal,
    createdAt: ms,
    updatedAt: ms,
  ));
  await db.upsertMemory(Memory(
    topic: 'training_time',
    content: 'Usually trains in the evening around 7pm',
    category: MemoryCategory.preference,
    source: MemorySource.user,
    createdAt: ms,
    updatedAt: ms,
  ));
  await db.upsertMemory(Memory(
    topic: 'workout_style',
    content: 'Prefers gym strength training over cardio',
    category: MemoryCategory.preference,
    source: MemorySource.user,
    createdAt: ms,
    updatedAt: ms,
  ));
  await db.upsertMemory(Memory(
    topic: 'pre_workout_snack',
    content: 'Likes a protein snack like grilled suya before evening workouts',
    category: MemoryCategory.pattern,
    createdAt: ms,
    updatedAt: ms,
  ));

  // ---- Exercise library --------------------------------------------------
  for (final e in _demoExercises(ms)) {
    await db.insertExercise(e);
  }

  await db.setSetting(kDemoSeeded, 'true');
}

// ---------------------------------------------------------------------------
// Demo content
// ---------------------------------------------------------------------------

LogEntry _meal(
  DateTime day,
  int hour,
  int minute,
  String summary,
  double kcal,
  double p,
  double c,
  double f, {
  List<MealItem> items = const [],
  MealType mealType = MealType.meal,
}) =>
    LogEntry(
      timestamp: DateTime(day.year, day.month, day.day, hour, minute)
          .millisecondsSinceEpoch,
      type: EntryType.meal,
      summary: summary,
      calories: kcal,
      proteinG: p,
      carbsG: c,
      fatG: f,
      rawTranscript: summary,
      items: items,
      mealType: mealType,
    );

LogEntry _exercise(
  DateTime day,
  int hour,
  int minute,
  String summary,
  double kcal, {
  int? sets,
  int? reps,
  double? durationMinutes,
}) =>
    LogEntry(
      timestamp: DateTime(day.year, day.month, day.day, hour, minute)
          .millisecondsSinceEpoch,
      type: EntryType.exercise,
      summary: summary,
      calories: kcal,
      proteinG: 0,
      carbsG: 0,
      fatG: 0,
      rawTranscript: summary,
      sets: sets,
      reps: reps,
      durationMinutes: durationMinutes,
    );

const _jollofLunch = [
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
  MealItem(
      name: 'Fried Plantain',
      quantity: '1 serving',
      calories: 250,
      proteinG: 1.5,
      carbsG: 48,
      fatG: 8),
];

const _friedRiceLunch = [
  MealItem(
      name: 'Fried Rice',
      quantity: '1 plate',
      calories: 650,
      proteinG: 18,
      carbsG: 80,
      fatG: 28),
  MealItem(
      name: 'Fried Chicken',
      quantity: '1 piece',
      calories: 400,
      proteinG: 38,
      carbsG: 0,
      fatG: 22),
];

const _egusiDinner = [
  MealItem(
      name: 'Egusi Soup',
      quantity: '1 bowl',
      calories: 550,
      proteinG: 24,
      carbsG: 20,
      fatG: 42),
  MealItem(
      name: 'Pounded Yam',
      quantity: '2 balls',
      calories: 300,
      proteinG: 8,
      carbsG: 75,
      fatG: 1),
];


/// Meals for a specific day offset. Days 4 and 9 are deliberately rest days
/// with nothing logged, so the month calendar shows a neutral day.
List<LogEntry> _dayMeals(DateTime day) {
  final meals = <
      (int, int, String, double, double, double, double, List<MealItem>)>[];
  switch (_dayOffset(day)) {
    case 0:
      meals.addAll([
        (8, 15, 'Akara and pap', 450, 14, 55, 16, const [
          MealItem(
              name: 'Akara',
              quantity: '2 pieces',
              calories: 250,
              proteinG: 10,
              carbsG: 18,
              fatG: 14),
          MealItem(
              name: 'Pap',
              quantity: '1 bowl',
              calories: 200,
              proteinG: 4,
              carbsG: 37,
              fatG: 2),
        ]),
        (12, 40, 'Jollof rice with fried chicken and plantain', 1350, 53.5,
            158, 50, _jollofLunch),
        (16, 20, 'Suya skewers', 320, 28, 4, 22, const []),
        (20, 10, 'Egusi soup with pounded yam', 850, 32, 95, 43, _egusiDinner),
      ]);
    case 1:
      meals.addAll([
        (7, 50, 'Oats with banana and peanut butter', 520, 16, 82, 14, const []),
        (13, 10, 'Amala and ewedu with beef', 780, 34, 96, 28, const []),
        (20, 30, 'Beans and garri with fish', 690, 30, 104, 18, const []),
      ]);
    case 2:
      meals.addAll([
        (8, 30, 'Two boiled eggs and toast', 320, 18, 28, 14, const []),
        (12, 50, 'Fried rice with shrimp', 880, 30, 92, 38, _friedRiceLunch),
        (20, 0, 'Pepper soup with goat meat', 460, 34, 12, 28, const []),
      ]);
    case 3:
      meals.addAll([
        (9, 0, 'Moi moi and custard', 480, 16, 62, 18, const []),
        (13, 30, 'Eba and vegetable soup with chicken', 840, 36, 104, 30,
            const []),
        (20, 10, 'Fruit bowl with yogurt', 280, 8, 50, 6, const []),
      ]);
    case 5:
      meals.addAll([
        (8, 0, 'Pap and fried plantain', 430, 6, 74, 14, const []),
        (12, 30, 'Jollof rice with turkey', 1100, 44, 128, 44, const [
          MealItem(
              name: 'Jollof Rice',
              quantity: '2 plates',
              calories: 700,
              proteinG: 14,
              carbsG: 110,
              fatG: 20),
          MealItem(
              name: 'Turkey',
              quantity: '2 pieces',
              calories: 400,
              proteinG: 30,
              carbsG: 18,
              fatG: 24),
        ]),
        (20, 0, 'Vegetable stir-fry with tofu', 520, 24, 44, 26, const []),
      ]);
    case 6:
      meals.addAll([
        (8, 20, 'Akara and pap', 450, 14, 55, 16, const []),
        (13, 0, 'Pounded yam with egusi', 820, 30, 92, 40, _egusiDinner),
        (19, 30, 'Grilled fish with plantain', 640, 42, 52, 28, const []),
      ]);
    case 7:
      meals.addAll([
        (7, 40, 'Banana smoothie with oats', 380, 12, 68, 8, const []),
        (12, 10, 'Amala and gbegiri with assorted meat', 910, 40, 108, 34,
            const []),
        (20, 40, 'Chicken pepper soup', 480, 36, 10, 30, const []),
      ]);
    case 8:
      meals.addAll([
        (8, 50, 'Agege bread with egg', 460, 18, 56, 16, const []),
        (13, 20, 'Coconut rice with beef', 940, 36, 104, 40, const []),
        (20, 10, 'Boiled yam and oil with fish', 590, 26, 76, 20, const []),
      ]);
    case 10:
      meals.addAll([
        (8, 10, 'Oats with milk and honey', 400, 12, 70, 8, const []),
        (12, 30, 'Egusi and pounded yam with stockfish', 900, 38, 94, 42,
            _egusiDinner),
        (20, 0, 'Jollof rice with chicken wings', 1080, 40, 124, 42, const []),
      ]);
    case 11:
      meals.addAll([
        (9, 0, 'Moi moi and agidi', 450, 16, 60, 16, const []),
        (13, 10, 'Efo riro with pounded yam', 760, 30, 88, 32, const []),
        (20, 20, 'Akara wraps', 520, 20, 58, 22, const []),
      ]);
    case 12:
      meals.addAll([
        (7, 30, 'Pap and akara', 430, 12, 56, 16, const []),
        (12, 40, 'Fried rice with chicken', 1050, 40, 96, 54, _friedRiceLunch),
        (19, 50, 'Vegetable soup with fish', 540, 30, 42, 26, const []),
      ]);
    case 13:
      meals.addAll([
        (8, 20, 'Egg sandwich', 390, 18, 34, 18, const []),
        (13, 0, 'Rice and beans with stew', 860, 30, 124, 24, const []),
        (20, 10, 'Grilled suya with onions', 420, 36, 6, 26, const []),
      ]);
  }
  return meals
      .map((m) => _meal(day, m.$1, m.$2, m.$3, m.$4, m.$5, m.$6, m.$7,
          items: m.$8, mealType: _seedMealType(m.$1, m.$3)))
      .toList();
}


/// Classifies a seeded meal from its time of day (the 16:20 suya skewers
/// are the one seeded snack).
MealType _seedMealType(int hour, String summary) {
  if (summary == 'Suya skewers') return MealType.snack;
  if (hour < 11) return MealType.breakfast;
  if (hour < 15) return MealType.lunch;
  return MealType.dinner;
}

/// Workouts for a specific day offset.
List<LogEntry> _dayExercises(DateTime day) {
  return switch (_dayOffset(day)) {
    0 => [
        _exercise(day, 18, 30, '30 min moderate treadmill run', 300,
            durationMinutes: 30),
      ],
    1 => [
        _exercise(day, 19, 0, '45 min brisk evening walk', 210,
            durationMinutes: 45),
      ],
    2 => [
        _exercise(day, 18, 15, '30 min bodyweight strength circuit', 240,
            sets: 3, reps: 12, durationMinutes: 30),
      ],
    3 => const <LogEntry>[],
    5 => [
        _exercise(day, 18, 30, '30 min cycle at the gym', 260,
            durationMinutes: 30),
      ],
    6 => const <LogEntry>[],
    7 => [
        _exercise(day, 18, 0, '30 min treadmill intervals', 340,
            durationMinutes: 30),
      ],
    8 => const <LogEntry>[],
    10 => [
        _exercise(day, 18, 15, '40 min brisk walk', 190,
            durationMinutes: 40),
      ],
    11 => const <LogEntry>[],
    12 => [
        _exercise(day, 18, 30, '30 min upper-body strength workout', 230,
            sets: 3, reps: 10, durationMinutes: 30),
      ],
    _ => const <LogEntry>[],
  };
}

/// The days-ago offset used to index the demo tables above.
int _dayOffset(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  return today.difference(d).inDays;
}

List<ExerciseRecommendation> _demoExercises(int now) => [
      ExerciseRecommendation(
        name: 'Bodyweight Squat',
        description:
            'Feet shoulder-width, squat to parallel, keep your heels down the whole way.',
        muscleGroups: const ['quads', 'glutes'],
        sets: 3,
        reps: 12,
        restSeconds: 60,
        difficulty: 'beginner',
        planName: 'Leg Day A',
        createdAt: now,
      ),
      ExerciseRecommendation(
        name: 'Walking Lunge',
        description:
            'Step forward into a deep lunge and drive back up to standing.',
        muscleGroups: const ['quads', 'glutes', 'hamstrings'],
        sets: 3,
        reps: 10,
        restSeconds: 60,
        difficulty: 'intermediate',
        planName: 'Leg Day A',
        createdAt: now,
      ),
      ExerciseRecommendation(
        name: 'Romanian Deadlift',
        description:
            'Hinge at the hips with the bar close to your legs and a flat back.',
        muscleGroups: const ['hamstrings', 'glutes'],
        sets: 3,
        reps: 10,
        restSeconds: 90,
        difficulty: 'intermediate',
        planName: 'Leg Day A',
        createdAt: now,
      ),
      ExerciseRecommendation(
        name: 'Plank',
        description: 'Hold a straight line from head to heels without sagging.',
        muscleGroups: const ['core'],
        durationMinutes: 2,
        restSeconds: 30,
        difficulty: 'beginner',
        createdAt: now,
      ),
      ExerciseRecommendation(
        name: 'Morning Walk',
        description: '30 minutes brisk walking to start the day.',
        muscleGroups: const ['cardio'],
        durationMinutes: 30,
        difficulty: 'beginner',
        createdAt: now,
      ),
    ];

