import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/openai_service.dart';
import '../data/reminder_service.dart';
import '../data/secure_settings.dart';
import '../models/app_settings_data.dart';
import '../models/chat_message.dart';
import '../models/exercise_recommendation.dart';
import '../models/log_entry.dart';
import '../models/memory.dart';
import '../models/weigh_in.dart';
import '../utils/calorie_math.dart';
import '../utils/nudge_message.dart';
import '../utils/periods.dart';
import '../utils/streaks.dart';

/// The single local database.
final databaseProvider = FutureProvider<AppDatabase>(
  (ref) => AppDatabase.open(),
);

/// Persisted app settings (BYOK key + custom vocabulary).
class AppSettings {
  const AppSettings({required this.apiKey, required this.vocabulary});

  final String apiKey;
  final String vocabulary;

  bool get isConfigured => apiKey.trim().isNotEmpty;
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final store = SecureSettings();
    final key = await store.readApiKey();
    final vocab = await store.readVocabulary();
    return AppSettings(apiKey: key ?? '', vocabulary: vocab ?? '');
  }

  Future<void> save({
    required String apiKey,
    required String vocabulary,
  }) async {
    final store = SecureSettings();
    await store.writeApiKey(apiKey.trim());
    await store.writeVocabulary(vocabulary.trim());
    state = AsyncData(
      AppSettings(apiKey: apiKey.trim(), vocabulary: vocabulary.trim()),
    );
  }
}

/// The day currently shown on the dashboard.
final selectedDayProvider = NotifierProvider<SelectedDay, DateTime>(
  SelectedDay.new,
);

class SelectedDay extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void setDay(DateTime day) {
    state = DateTime(day.year, day.month, day.day);
  }
}

/// Entries for the selected day, with add/delete actions.
final dayLogsProvider =
    AsyncNotifierProvider<DayLogsController, List<LogEntry>>(
      DayLogsController.new,
    );

class DayLogsController extends AsyncNotifier<List<LogEntry>> {
  @override
  Future<List<LogEntry>> build() async {
    final day = ref.watch(selectedDayProvider);
    final db = await ref.watch(databaseProvider.future);
    return db.logsForDay(day);
  }

  Future<void> add(LogEntry entry) async {
    final db = await ref.read(databaseProvider.future);
    final settings = await ref.read(appSettingsProvider.future);
    // Snapshot the target in effect today so this day is judged by it later.
    await db.insertLog(entry, maintenanceKcal: settings.maintenanceKcal);
    ref.invalidateSelf();
    // Logging today means the 8pm nudge has nothing left to say.
    await ref.read(rearmDailyReminderProvider)(db: db);
  }

  Future<void> delete(LogEntry entry) async {
    final id = entry.id;
    if (id == null) return;
    final db = await ref.read(databaseProvider.future);
    await db.deleteLog(id);
    ref.invalidateSelf();
    // Deleting today's last entry puts the nudge back on duty.
    await ref.read(rearmDailyReminderProvider)(db: db);
  }
}

/// Daily aggregate derived from the visible logs.
final dayTotalsProvider = Provider<LogTotals>((ref) {
  final logs = ref.watch(dayLogsProvider).value ?? const <LogEntry>[];
  return LogTotals.fromEntries(logs);
});

/// The OpenAI service, available only once the user has saved their key.
final openaiServiceProvider = Provider<OpenAIService?>((ref) {
  final settings = ref.watch(settingsProvider).value;
  if (settings == null || !settings.isConfigured) return null;
  return OpenAIService(apiKey: settings.apiKey);
});

// ---------------------------------------------------------------------------
// Non-secret app settings (maintenance kcal, weight unit, reminders, memory)
// ---------------------------------------------------------------------------

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettingsData>(
      AppSettingsController.new,
    );

class AppSettingsController extends AsyncNotifier<AppSettingsData> {
  static const kMaintenance = 'maintenance_kcal';
  static const kWeightUnit = 'weight_unit';
  static const kReminderEnabled = 'reminder_enabled';
  static const kReminderTime = 'reminder_time';
  static const kMemoryEnabled = 'memory_enabled';
  static const kHeightCm = 'height_cm';
  static const kAge = 'age';
  static const kSex = 'sex';
  static const kActivityLevel = 'activity_level';
  static const kProfileCompleted = 'profile_completed';

  @override
  Future<AppSettingsData> build() async {
    final db = await ref.watch(databaseProvider.future);
    final maintenance =
        double.tryParse(await db.getSetting(kMaintenance) ?? '') ?? 2200;
    final unit = await db.getSetting(kWeightUnit) ?? 'kg';
    final reminderEnabled =
        (await db.getSetting(kReminderEnabled) ?? 'false') == 'true';
    final timeParts = (await db.getSetting(kReminderTime) ?? '20:00')
        .split(':')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final memoryEnabled =
        (await db.getSetting(kMemoryEnabled) ?? 'true') == 'true';
    final heightCm = double.tryParse(await db.getSetting(kHeightCm) ?? '');
    final age = int.tryParse(await db.getSetting(kAge) ?? '');
    final sex = Sex.fromName(await db.getSetting(kSex));
    final activityLevel = ActivityLevel.fromName(await db.getSetting(kActivityLevel));
    // Existing users who already recorded anything (or set a maintenance
    // target) are treated as profile-complete, so the first-run onboarding
    // only greets genuinely new installs.
    final profileCompleted =
        (await db.getSetting(kProfileCompleted) ?? '') == 'true' ||
            await db.hasAnyData() ||
            await db.getSetting(kMaintenance) != null;
    return AppSettingsData(
      maintenanceKcal: maintenance,
      weightUnit: unit,
      reminderEnabled: reminderEnabled,
      reminderTime: TimeOfDay(
        hour: timeParts.isNotEmpty ? timeParts[0] : 20,
        minute: timeParts.length > 1 ? timeParts[1] : 0,
      ),
      memoryEnabled: memoryEnabled,
      heightCm: heightCm,
      age: age,
      sex: sex,
      activityLevel: activityLevel,
      profileCompleted: profileCompleted,
    );
  }

  Future<void> save(AppSettingsData data) async {
    final db = await ref.read(databaseProvider.future);
    await db.setSetting(kMaintenance, data.maintenanceKcal.toString());
    await db.setSetting(kWeightUnit, data.weightUnit);
    await db.setSetting(kReminderEnabled, data.reminderEnabled.toString());
    await db.setSetting(
      kReminderTime,
      '${data.reminderTime.hour}:${data.reminderTime.minute}',
    );
    await db.setSetting(kMemoryEnabled, data.memoryEnabled.toString());
    await db.setSetting(kHeightCm, data.heightCm?.toString() ?? '');
    await db.setSetting(kAge, data.age?.toString() ?? '');
    await db.setSetting(kSex, data.sex?.name ?? '');
    await db.setSetting(kActivityLevel, data.activityLevel?.name ?? '');
    await db.setSetting(kProfileCompleted, data.profileCompleted.toString());
    state = AsyncData(data);
  }

  /// Apply a partial update and persist it.
  Future<void> patch(AppSettingsData Function(AppSettingsData) fn) async {
    final current = state.value;
    if (current == null) return;
    await save(fn(current));
  }
}

// ---------------------------------------------------------------------------
// Weigh-ins
// ---------------------------------------------------------------------------

final weighInsProvider =
    AsyncNotifierProvider<WeighInsController, List<WeighIn>>(
      WeighInsController.new,
    );

class WeighInsController extends AsyncNotifier<List<WeighIn>> {
  @override
  Future<List<WeighIn>> build() async {
    final db = await ref.watch(databaseProvider.future);
    return db.weighIns();
  }

  Future<void> add(WeighIn weighIn) async {
    final db = await ref.read(databaseProvider.future);
    await db.insertWeighIn(weighIn);
    ref.invalidateSelf();
  }

  Future<void> delete(WeighIn weighIn) async {
    final id = weighIn.id;
    if (id == null) return;
    final db = await ref.read(databaseProvider.future);
    await db.deleteWeighIn(id);
    ref.invalidateSelf();
  }
}

// ---------------------------------------------------------------------------
// Month calendar
// ---------------------------------------------------------------------------

/// Daily totals for the month containing [month], keyed by "yyyy-MM-dd".
final monthTotalsProvider =
    FutureProvider.family<Map<String, LogTotals>, DateTime>((ref, month) async {
      final db = await ref.watch(databaseProvider.future);
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final logs = await db.logsForRange(start, end);
      final map = <String, LogTotals>{};
      for (final e in logs) {
        final day = DateTime.fromMillisecondsSinceEpoch(e.timestamp).toLocal();
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}'
            '-${day.day.toString().padLeft(2, '0')}';
        map[key] = (map[key] ?? LogTotals()) + LogTotals.fromEntries([e]);
      }
      return map;
    });

/// Maintenance snapshot per day for the month containing [month], keyed by
/// "yyyy-MM-dd". Days without a snapshot (nothing logged then) are absent.
final monthMaintenanceProvider =
    FutureProvider.family<Map<String, double>, DateTime>((ref, month) async {
      final db = await ref.watch(databaseProvider.future);
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final snaps = await db.dayMaintenanceBetween(start, end);
      return {
        for (final e in snaps.entries)
          _dayKey(DateTime.fromMillisecondsSinceEpoch(e.key).toLocal()):
              e.value,
      };
    });

String _dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}'
    '-${day.day.toString().padLeft(2, '0')}';

/// Logging + on-plan streaks over the last 90 days, recomputed when the
/// maintenance target changes.
final streakProvider = FutureProvider<Streaks>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final today = DateTime.now();
  final start = today.subtract(const Duration(days: 90));
  final logs = await db.logsForRange(start, today);
  final perDay = <DateTime, LogTotals>{};
  for (final e in logs) {
    final day = DateTime.fromMillisecondsSinceEpoch(e.timestamp).toLocal();
    final d = DateTime(day.year, day.month, day.day);
    perDay[d] = (perDay[d] ?? LogTotals()) + LogTotals.fromEntries([e]);
  }
  final maintenance =
      ref.watch(appSettingsProvider).value?.maintenanceKcal ?? 2200;
  // Judge each day by the target that was in effect when it was logged.
  final snaps = await db.dayMaintenanceBetween(start, today);
  final dayMaintenance = <DateTime, double>{
    for (final e in snaps.entries)
      DateTime.fromMillisecondsSinceEpoch(e.key).toLocal(): e.value,
  };
  return computeStreaks(
    perDay,
    today,
    maintenance,
    dayMaintenance: dayMaintenance,
  );
});

/// The month currently shown on the calendar (first day of month).
final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(
  SelectedMonth.new,
);

class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  void setMonth(DateTime month) {
    state = DateTime(month.year, month.month, 1);
  }

  void shift(int months) {
    state = DateTime(state.year, state.month + months, 1);
  }
}

// ---------------------------------------------------------------------------
// Week & month calorie summaries
// ---------------------------------------------------------------------------

/// The Monday of the week currently shown on the Month screen's week card.
final selectedWeekProvider = NotifierProvider<SelectedWeek, DateTime>(
  SelectedWeek.new,
);

class SelectedWeek extends Notifier<DateTime> {
  @override
  DateTime build() => startOfWeek(DateTime.now());

  void shift(int weeks) =>
      state = startOfWeek(state.add(Duration(days: 7 * weeks)));
}

/// Ledger totals plus the maintenance budget for a half-open local-day range
/// `(start, end)`. The budget counts every day in the range — logged or not —
/// at that day's snapshot target when one exists, falling back to the current
/// target for days that were never logged. LEFT therefore answers "how many
/// calories do I have left across this whole period?".
final periodTotalsProvider =
    FutureProvider.family<PeriodTotals, (DateTime, DateTime)>(
  (ref, range) async {
    final (start, end) = range;
    final db = await ref.watch(databaseProvider.future);
    final totals = LogTotals.fromEntries(await db.logsBetween(start, end));
    final snaps = await db.dayMaintenanceBetween(start, end);
    final current =
        ref.watch(appSettingsProvider).value?.maintenanceKcal ?? 2200;
    var budget = 0.0;
    final first = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    var day = first;
    while (day.isBefore(last)) {
      final key =
          DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      budget += snaps[key] ?? current;
      day = day.add(const Duration(days: 1));
    }
    return PeriodTotals(totals: totals, budgetKcal: budget);
  },
);

/// The week beginning on the Monday of [monday].
final weekTotalsProvider =
    FutureProvider.family<PeriodTotals, DateTime>((ref, monday) {
  final start = startOfWeek(monday);
  final end = start.add(const Duration(days: 7));
  return ref.watch(periodTotalsProvider((start, end)).future);
});

/// The month containing [month].
final monthPeriodTotalsProvider =
    FutureProvider.family<PeriodTotals, DateTime>((ref, month) {
  final start = startOfMonth(month);
  final end = DateTime(start.year, start.month + 1, 1);
  return ref.watch(periodTotalsProvider((start, end)).future);
});

// ---------------------------------------------------------------------------
// Coach: chat thread, memories, exercise library
// ---------------------------------------------------------------------------

/// The persisted coach conversation, oldest first.
final chatMessagesProvider =
    AsyncNotifierProvider<ChatController, List<ChatMessage>>(
      ChatController.new,
    );

class ChatController extends AsyncNotifier<List<ChatMessage>> {
  @override
  Future<List<ChatMessage>> build() async {
    final db = await ref.watch(databaseProvider.future);
    return db.chatMessages(limit: 60);
  }

  Future<void> addUser(String text) async {
    final db = await ref.read(databaseProvider.future);
    await db.insertChatMessage(
      ChatMessage(
        role: 'user',
        content: text.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> addAssistant(String text) async {
    final db = await ref.read(databaseProvider.future);
    await db.insertChatMessage(
      ChatMessage(
        role: 'assistant',
        content: text.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> clear() async {
    final db = await ref.read(databaseProvider.future);
    await db.clearChat();
    ref.invalidateSelf();
  }
}

/// The coach's distilled memory store, active only.
final memoriesProvider =
    AsyncNotifierProvider<MemoriesController, List<Memory>>(
      MemoriesController.new,
    );

class MemoriesController extends AsyncNotifier<List<Memory>> {
  @override
  Future<List<Memory>> build() async {
    final db = await ref.watch(databaseProvider.future);
    return db.memories();
  }

  Future<void> upsert(Memory memory) async {
    final db = await ref.read(databaseProvider.future);
    await db.upsertMemory(memory);
    ref.invalidateSelf();
  }

  Future<void> remove(Memory memory) async {
    final id = memory.id;
    if (id == null) return;
    final db = await ref.read(databaseProvider.future);
    await db.deactivateMemory(id);
    ref.invalidateSelf();
  }

  Future<void> updateContent(int id, String content) async {
    final db = await ref.read(databaseProvider.future);
    await db.updateMemoryContent(id, content);
    ref.invalidateSelf();
  }
}

/// The saved exercise library (non-archived).
final exercisesProvider =
    AsyncNotifierProvider<ExercisesController, List<ExerciseRecommendation>>(
      ExercisesController.new,
    );

class ExercisesController extends AsyncNotifier<List<ExerciseRecommendation>> {
  @override
  Future<List<ExerciseRecommendation>> build() async {
    final db = await ref.watch(databaseProvider.future);
    return db.exercises();
  }

  /// Returns true when the exercise was newly saved (not a duplicate).
  Future<bool> add(ExerciseRecommendation exercise) async {
    final db = await ref.read(databaseProvider.future);
    final id = await db.insertExercise(exercise);
    ref.invalidateSelf();
    return id != null;
  }

  Future<void> remove(ExerciseRecommendation exercise) async {
    final id = exercise.id;
    if (id == null) return;
    final db = await ref.read(databaseProvider.future);
    await db.archiveExercise(id);
    ref.invalidateSelf();
  }

  Future<void> restore(ExerciseRecommendation exercise) async {
    final id = exercise.id;
    if (id == null) return;
    final db = await ref.read(databaseProvider.future);
    await db.unarchiveExercise(id);
    ref.invalidateSelf();
  }
}

/// Holds a prompt another screen wants the coach to send next.
final coachDraftProvider = NotifierProvider<CoachDraft, String?>(
  CoachDraft.new,
);

class CoachDraft extends Notifier<String?> {
  @override
  String? build() => null;

  void draft(String prompt) => state = prompt;

  void consume() => state = null;
}

/// Daily log reminder scheduling.
final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService();
  ref.onDispose(service.dispose);
  return service;
});

/// Re-arms the daily nudge so it only fires when the day still has gaps:
/// missing meals (snacks never count) or a missing workout -> the pending
/// nudge is re-scheduled with a message about what's open; a complete day or
/// a switched-off reminder -> cancelled. Best-effort, like all reminder work
/// — a failure here must never break the app flow.
final rearmDailyReminderProvider =
    Provider<Future<void> Function({AppDatabase? db})>((ref) {
      return ({AppDatabase? db}) async {
        try {
          final AppDatabase database;
          if (db != null) {
            database = db;
          } else {
            database = await ref.read(databaseProvider.future);
          }
          final settings = await ref.read(appSettingsProvider.future);
          final reminder = ref.read(reminderServiceProvider);
          if (!settings.reminderEnabled) {
            await reminder.cancel();
            return;
          }
          final todayLogs = await database.logsForDay(DateTime.now());
          final message = nudgeMessage(todayLogs);
          if (message == null) {
            // The day looks complete — nothing left to nudge about.
            await reminder.cancel();
            return;
          }
          await reminder.scheduleDaily(
            hour: settings.reminderTime.hour,
            minute: settings.reminderTime.minute,
            message: message,
          );
        } catch (_) {
          // Best-effort: reminders must never break the app.
        }
      };
    });
