import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/log_entry.dart';
import '../models/memory.dart';
import '../utils/exercise_math.dart';

/// One exercise parsed out of a spoken workout.
class ParsedExercise {
  const ParsedExercise({
    required this.name,
    this.sets,
    this.reps,
    this.durationMinutes,
    this.caloriesBurned = 0,
  });

  final String name;

  /// Sets and reps when the speaker gave them — the ground truth the burn
  /// engine prices (mechanical work), not the model's guess.
  final int? sets;
  final int? reps;
  final double? durationMinutes;

  /// The burn this exercise was logged with. Computed deterministically from
  /// the structure above when the user's weight is known; otherwise a
  /// best-effort estimate parsed out of the model's reply.
  final double caloriesBurned;
}

/// A meal or exercise parsed from a transcript by the backend AI proxy.
class ParsedLog {
  const ParsedLog({
    required this.type,
    required this.summary,
    this.items = const [],
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.activity,
    this.durationMinutes,
    this.mealType = MealType.meal,
    this.exercises = const [],
  });

  final EntryType type;
  final String summary;
  final List<MealItem> items;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final String? activity;
  final double? durationMinutes;

  /// breakfast/lunch/dinner/snack when [type] is a meal (default for
  /// exercises and legacy parses).
  final MealType mealType;

  /// Parsed exercises, when the model returned the exercises array.
  final List<ParsedExercise> exercises;

  /// Seeds a [ParsedLog] from an already-saved [LogEntry], so the editor can
  /// reopen a logged meal or workout for fixing without re-dictating it.
  ///
  /// The mirror of [toEntries]: meals round-trip their items and meal type;
  /// workouts round-trip their nested exercises; legacy single-exercise rows
  /// (no `exerciseItems`, just the top-level fields) are wrapped back into the
  /// exercises array so the editor treats every workout the same.
  factory ParsedLog.fromEntry(LogEntry entry) {
    if (entry.type == EntryType.meal) {
      // Older saves could hold macros but no parsed items — give the editor
      // one synthetic item so the meal stays adjustable instead of zeroing.
      final items = entry.items.isEmpty
          ? [
              MealItem(
                name: entry.summary,
                quantity: '1',
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
              ),
            ]
          : entry.items;
      return ParsedLog(
        type: entry.type,
        summary: entry.summary,
        items: items,
        calories: entry.calories,
        proteinG: entry.proteinG,
        carbsG: entry.carbsG,
        fatG: entry.fatG,
        mealType: entry.mealType,
      );
    }
    final exercises = entry.exerciseItems.isEmpty
        ? [
            ParsedExercise(
              name: entry.summary,
              sets: entry.sets,
              reps: entry.reps,
              durationMinutes: entry.durationMinutes,
              caloriesBurned: entry.calories,
            ),
          ]
        : [
            for (final e in entry.exerciseItems)
              ParsedExercise(
                name: e.name,
                sets: e.sets,
                reps: e.reps,
                durationMinutes: e.durationMinutes,
                caloriesBurned: e.caloriesBurned,
              ),
          ];
    return ParsedLog(
      type: entry.type,
      summary: entry.summary,
      exercises: exercises,
      calories: exercises.fold(0.0, (s, e) => s + e.caloriesBurned),
      mealType: entry.mealType,
    );
  }

  /// The exercises array when present; otherwise the legacy single-exercise
  /// shape (the top-level activity/duration/calories).
  List<ParsedExercise> get exerciseList {
    if (exercises.isNotEmpty) return exercises;
    if (type == EntryType.exercise) {
      return [
        ParsedExercise(
          name: activity ?? summary,
          durationMinutes: durationMinutes,
          caloriesBurned: calories,
        ),
      ];
    }
    return const [];
  }

  LogEntry toEntry({required int timestamp, required String rawTranscript}) =>
      toEntries(timestamp: timestamp, rawTranscript: rawTranscript).first;

  /// One row per parsed item for meals; a single row per workout with the
  /// exercises nested underneath as items, so a multi-exercise session reads
  /// in the timeline exactly like a meal — one entry, items beneath it.
  List<LogEntry> toEntries({
    required int timestamp,
    required String rawTranscript,
  }) {
    if (type == EntryType.meal) {
      return [
        LogEntry(
          timestamp: timestamp,
          type: type,
          summary: summary,
          calories: calories,
          proteinG: proteinG,
          carbsG: carbsG,
          fatG: fatG,
          rawTranscript: rawTranscript,
          items: items,
          mealType: mealType,
        ),
      ];
    }
    final list = exerciseList;
    final totalBurned = list.fold(0.0, (s, e) => s + e.caloriesBurned);
    return [
      LogEntry(
        timestamp: timestamp,
        type: type,
        summary: summary.isNotEmpty ? summary : list.first.name,
        calories: totalBurned,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        rawTranscript: rawTranscript,
        mealType: mealType,
        exerciseItems: [
          for (final e in list)
            ExerciseItem(
              name: e.name,
              sets: e.sets,
              reps: e.reps,
              durationMinutes: e.durationMinutes,
              caloriesBurned: e.caloriesBurned,
            ),
        ],
        // Keep the legacy single-exercise fields populated so old rows and
        // single-exercise entries still read the same.
        sets: list.length == 1 ? list.first.sets : null,
        reps: list.length == 1 ? list.first.reps : null,
        durationMinutes: list.length == 1 ? list.first.durationMinutes : null,
      ),
    ];
  }
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One message exchanged with the coach.
class ChatTurn {
  const ChatTurn({required this.role, required this.content});

  /// 'user' or 'assistant'.
  final String role;
  final String content;
}

/// A distilled memory returned by the memory review call.
class MemoryDraft {
  const MemoryDraft({
    required this.topic,
    required this.content,
    this.category = MemoryCategory.note,
    this.action = 'create',
  });

  final String topic;
  final String content;
  final MemoryCategory category;

  /// create | update | remove.
  final String action;
}

/// An exercise recommendation parsed out of a coaching exchange.
class ExerciseDraft {
  const ExerciseDraft({
    required this.name,
    this.description = '',
    this.muscleGroups = const [],
    this.sets,
    this.reps,
    this.restSeconds,
    this.durationMinutes,
    this.difficulty = '',
    this.planName = '',
  });

  final String name;
  final String description;
  final List<String> muscleGroups;
  final int? sets;
  final int? reps;
  final int? restSeconds;
  final int? durationMinutes;
  final String difficulty;
  final String planName;
}

/// Result of the exercise extraction call.
class ExerciseExtraction {
  const ExerciseExtraction({required this.hasAdvice, this.drafts = const []});

  final bool hasAdvice;
  final List<ExerciseDraft> drafts;
}

/// Remaining allowance for one metered feature, as reported by the backend.
class KindUsage {
  const KindUsage({
    required this.kind,
    required this.limit,
    required this.used,
    required this.remaining,
  });

  final String kind;
  final int limit;
  final int used;
  final int remaining;

  factory KindUsage.fromJson(Map<String, dynamic> json) => KindUsage(
        kind: (json['kind'] as String?) ?? '',
        limit: (json['limit'] as num?)?.toInt() ?? 0,
        used: (json['used'] as num?)?.toInt() ?? 0,
        remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      );
}

/// The account view returned by GET /v1/me.
class AccountInfo {
  const AccountInfo({
    required this.tier,
    required this.isActive,
    this.entitlement,
    this.status,
    this.limits = const [],
    this.spendRemainingUsd = 0,
  });

  /// 'free' or 'paid'.
  final String tier;
  final bool isActive;
  final String? entitlement;
  final String? status;
  final List<KindUsage> limits;
  final double spendRemainingUsd;

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    final entitlement = json['entitlement'] as Map<String, dynamic>?;
    return AccountInfo(
      tier: (json['tier'] as String?) ?? 'free',
      isActive: (entitlement?['is_active'] as bool?) ?? false,
      entitlement: entitlement?['entitlement'] as String?,
      status: entitlement?['status'] as String?,
      limits: ((json['limits'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(KindUsage.fromJson)
          .toList(),
      spendRemainingUsd: (json['spend_remaining_usd'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Client for the Weight Buddy backend's AI proxy. The two-stage pipeline
/// (audio -> transcript -> structured log), the coach, memory review and
/// exercise extraction all run server-side, so the provider key never reaches
/// the device. Every call carries the session token from the anonymous
/// sign-in.
class AiService {
  AiService({
    http.Client? client,
    String? baseUrl,
    required this.token,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? kBackendBaseUrl;

  final http.Client _client;
  final String _baseUrl;
  final String token;

  /// Bounds every backend call so a stalled connection surfaces as an error
  /// instead of hanging the UI indefinitely.
  static const _timeout = Duration(seconds: 60);

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await _client
          .post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw const AiServiceException(
          'Weight Buddy took too long to respond. Try again.');
    }
  }

  Future<http.Response> _get(String path) async {
    try {
      return await _client
          .get(_uri(path), headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
    } on TimeoutException {
      throw const AiServiceException(
          'Weight Buddy took too long to respond. Try again.');
    }
  }

  /// The device's wall clock as HH:MM, so the backend classifies meals against
  /// the user's timezone rather than the server's.
  static String _localTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Stage 1 — transcribe recorded audio. The custom vocabulary is passed as
  /// the transcription `prompt` to boost recognition of regional dish names.
  Future<String> transcribe({
    required Uint8List audioBytes,
    required String filename,
    String? prompt,
    String model = 'gpt-transcribe',
  }) async {
    final request = http.MultipartRequest('POST', _uri('/v1/ai/transcribe'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(
          http.MultipartFile.fromBytes('file', audioBytes, filename: filename));
    if (prompt != null && prompt.trim().isNotEmpty) {
      request.fields['prompt'] = prompt;
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const AiServiceException(
          'Weight Buddy took too long to respond. Try again.');
    }
    if (response.statusCode != 200) {
      throw AiServiceException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (body['text'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      throw const AiServiceException(
          'Couldn\'t hear anything in that recording. Try again a little closer.');
    }
    return text;
  }

  /// Stage 2 — parse a transcript into a structured meal or workout. The
  /// backend runs the strict-schema extraction; the device only maps the
  /// result and (when the weight is known) prices exercise burns itself.
  Future<ParsedLog> parseTranscript(
    String transcript, {
    String model = 'gpt-4o-mini',
    double? weightKg,
  }) async {
    final response = await _post('/v1/ai/parse', {
      'transcript': transcript,
      'weight_kg': weightKg,
      'local_time': _localTime(),
    });
    if (response.statusCode != 200) {
      throw AiServiceException(_errorMessage(response));
    }
    return parsedLogFromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      weightKg: weightKg,
    );
  }

  /// The coach: a free-form conversation. Returns the assistant's reply.
  Future<String> chat({
    required List<ChatTurn> history,
    required String systemPrompt,
    String model = 'gpt-4o-mini',
  }) async {
    final response = await _post('/v1/ai/chat', {
      'system_prompt': systemPrompt,
      'messages': [
        for (final t in history) {'role': t.role, 'content': t.content},
      ],
    });
    if (response.statusCode != 200) {
      throw AiServiceException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final reply = (body['reply'] as String?)?.trim();
    if (reply == null || reply.isEmpty) {
      throw const AiServiceException(
          'The coach went quiet. Try asking again.');
    }
    return reply;
  }

  /// Reviews a conversation exchange and returns distilled facts to create,
  /// update or retire.
  Future<List<MemoryDraft>> distillMemories({
    required List<ChatTurn> exchange,
    String model = 'gpt-4o-mini',
  }) async {
    final response = await _post('/v1/ai/distill-memories', {
      'exchange': [
        for (final t in exchange) {'role': t.role, 'content': t.content},
      ],
    });
    if (response.statusCode != 200) {
      throw AiServiceException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (body['memories'] as List?) ?? const [];
    final drafts = <MemoryDraft>[];
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final topic = (map['topic'] as String?) ?? '';
      final text = (map['content'] as String?) ?? '';
      if (topic.isEmpty || text.isEmpty) continue;
      drafts.add(MemoryDraft(
        topic: topic,
        content: text,
        category:
            MemoryCategory.fromApiName((map['category'] as String?) ?? 'note'),
        action: (map['action'] as String?) ?? 'create',
      ));
    }
    return drafts;
  }

  /// Scans a coaching exchange for concrete exercise recommendations.
  Future<ExerciseExtraction> extractExercises({
    required List<ChatTurn> exchange,
    String model = 'gpt-4o-mini',
  }) async {
    final response = await _post('/v1/ai/extract-exercises', {
      'exchange': [
        for (final t in exchange) {'role': t.role, 'content': t.content},
      ],
    });
    if (response.statusCode != 200) {
      throw AiServiceException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final hasAdvice = (body['has_exercise_advice'] as bool?) ?? false;
    final list = (body['recommendations'] as List?) ?? const [];
    final drafts = <ExerciseDraft>[];
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final name = ((map['name'] as String?) ?? '').trim();
      if (name.isEmpty) continue;
      drafts.add(ExerciseDraft(
        name: name,
        description: (map['description'] as String?) ?? '',
        muscleGroups: ((map['muscle_groups'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        sets: (map['sets'] as num?)?.toInt(),
        reps: (map['reps'] as num?)?.toInt(),
        restSeconds: (map['rest_seconds'] as num?)?.toInt(),
        durationMinutes: (map['duration_minutes'] as num?)?.toInt(),
        difficulty: (map['difficulty'] as String?) ?? '',
        planName: (map['plan_name'] as String?) ?? '',
      ));
    }
    return ExerciseExtraction(hasAdvice: hasAdvice, drafts: drafts);
  }

  /// The signed-in user's tier and remaining daily allowance.
  Future<AccountInfo> me() async {
    final response = await _get('/v1/me');
    if (response.statusCode != 200) {
      throw AiServiceException(_errorMessage(response));
    }
    return AccountInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Surfaces the backend's own error message when it sends one, so metered
  /// limits and spend-cap notices reach the user verbatim.
  static String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is Map && error['message'] is String) {
        final message = error['message'] as String;
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    if (response.statusCode == 401) {
      return 'Your session has expired. Reopen the app to sign in again.';
    }
    return 'Weight Buddy couldn\'t complete that${response.statusCode >= 500 ? ' right now' : ''}. Try again.';
  }
}

/// Maps a parsed log JSON object — the backend's strict-schema reply — into a
/// [ParsedLog]. Exposed so tests can exercise the mapping directly.
ParsedLog parsedLogFromJson(Map<String, dynamic> json, {double? weightKg}) {
  final type = EntryType.fromApiName((json['entry_type'] as String?) ?? 'meal');
  if (type == EntryType.exercise) {
    final exercisesJson = (json['exercises'] as List?) ?? const [];
    final exercises = <ParsedExercise>[];
    for (final item in exercisesJson) {
      if (item is! Map<String, dynamic>) continue;
      final map = item;
      final name = ((map['name'] as String?) ?? '').trim();
      if (name.isEmpty) continue;
      final sets = (map['sets'] as num?)?.toInt();
      final reps = (map['reps'] as num?)?.toInt();
      final durationMinutes = _numOrNull(map['duration_minutes']);
      exercises.add(ParsedExercise(
        name: name,
        sets: sets,
        reps: reps,
        durationMinutes: durationMinutes,
        caloriesBurned: _exerciseBurn(
          name: name,
          sets: sets,
          reps: reps,
          durationMinutes: durationMinutes,
          weightKg: weightKg,
          llmEstimate: _numOrNull(map['estimated_calories_burned']),
        ),
      ));
    }
    if (exercises.isNotEmpty) {
      // Keep the single-exercise fields pointing at the first one so legacy
      // consumers (e.g. the log-exercise sheet) still behave.
      return ParsedLog(
        type: type,
        summary: (json['summary'] as String?) ?? exercises.first.name,
        calories: exercises.first.caloriesBurned,
        activity: exercises.first.name,
        durationMinutes: exercises.first.durationMinutes,
        exercises: exercises,
      );
    }
    // Legacy single-exercise shape.
    final activity = (json['activity'] as String?) ?? '';
    final summary = (json['summary'] as String?) ?? 'Workout';
    return ParsedLog(
      type: type,
      summary: summary,
      calories: _exerciseBurn(
        name: activity.isNotEmpty ? activity : summary,
        durationMinutes: _numOrNull(json['duration_minutes']),
        weightKg: weightKg,
        llmEstimate: _numOrNull(json['estimated_calories_burned']),
      ),
      activity: activity,
      durationMinutes: _numOrNull(json['duration_minutes']),
    );
  }
  final itemsJson = (json['items'] as List?) ?? const [];
  final items = itemsJson
      .map((e) => MealItem.fromJson(e as Map<String, dynamic>))
      .toList();
  return ParsedLog(
    type: type,
    summary: (json['summary'] as String?) ?? 'Meal',
    items: items,
    calories: _num(json['total_calories']),
    proteinG: _num(json['total_protein_g']),
    carbsG: _num(json['total_carbs_g']),
    fatG: _num(json['total_fat_g']),
    mealType: MealType.fromApiName((json['meal_type'] as String?) ?? 'meal'),
  );
}

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
double? _numOrNull(dynamic v) => (v as num?)?.toDouble();

/// The deterministic burn for a parsed exercise. With the user's weight the
/// engine prices the exercise itself (mechanical work for reps, MET for
/// duration); without it the model's guess is kept as a best-effort fallback
/// so callers that don't know the weight still get a number.
double _exerciseBurn({
  required String name,
  int? sets,
  int? reps,
  double? durationMinutes,
  double? weightKg,
  double? llmEstimate,
}) {
  if (weightKg != null && weightKg > 0) {
    return ExerciseMath.burnForExercise(
      name: name,
      weightKg: weightKg,
      sets: sets,
      reps: reps,
      durationMinutes: durationMinutes,
    );
  }
  return llmEstimate ?? 0;
}
