import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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

/// A meal or exercise parsed from a transcript by the GPT API.
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

  /// One row per parsed item (meals) or per parsed exercise. Meals always
  /// produce a single entry; exercises produce one entry per exercise in the
  /// `exercises` array so a workout that mentions several exercises records
  /// them all. Rows for the same parse get a +1 ms timestamp bump so the
  /// timeline shows them in the order they were spoken (it orders by
  /// timestamp only).
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
    if (list.length == 1) {
      final e = list.first;
      return [
        LogEntry(
          timestamp: timestamp,
          type: type,
          summary: summary.isNotEmpty ? summary : e.name,
          calories: e.caloriesBurned,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          rawTranscript: rawTranscript,
          mealType: mealType,
          sets: e.sets,
          reps: e.reps,
          durationMinutes: e.durationMinutes,
        ),
      ];
    }
    return [
      for (var i = 0; i < list.length; i++)
        LogEntry(
          timestamp: timestamp + i,
          type: type,
          summary: list[i].name,
          calories: list[i].caloriesBurned,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          rawTranscript: rawTranscript,
          mealType: mealType,
          sets: list[i].sets,
          reps: list[i].reps,
          durationMinutes: list[i].durationMinutes,
        ),
    ];
  }
}

class OpenAIServiceException implements Exception {
  const OpenAIServiceException(this.message);
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

/// Two-stage pipeline (PRD §4): audio -> transcript -> structured JSON.
class OpenAIService {
  OpenAIService({http.Client? client, required this.apiKey})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String apiKey;

  static const _transcribeEndpoint =
      'https://api.openai.com/v1/audio/transcriptions';
  static const _chatEndpoint = 'https://api.openai.com/v1/chat/completions';

  /// Stage 1 — transcribe recorded audio. The custom vocabulary is passed as
  /// the transcription `prompt` to boost recognition of regional dish names.
  Future<String> transcribe({
    required Uint8List audioBytes,
    required String filename,
    String? prompt,
    String model = 'gpt-transcribe',
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_transcribeEndpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = model
      ..files.add(
          http.MultipartFile.fromBytes('file', audioBytes, filename: filename));
    if (prompt != null && prompt.trim().isNotEmpty) {
      request.fields['prompt'] = prompt;
    }

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw OpenAIServiceException(_errorMessage(response, 'transcription'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (body['text'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      throw const OpenAIServiceException(
          'Couldn\'t hear anything in that recording — try again a little closer.');
    }
    return text;
  }

  /// Stage 2 — parse a transcript into a structured meal or exercise using
  /// OpenAI Structured Outputs (JSON Schema from the PRD).
  ///
  /// When [weightKg] is given, the model's own `estimated_calories_burned`
  /// values are ignored and every exercise burn is computed deterministically
  /// from its sets/reps/duration by the exercise engine — so a 20-rep set
  /// can never log a workout-sized number.
  Future<ParsedLog> parseTranscript(
    String transcript, {
    String model = 'gpt-4o-mini',
    double? weightKg,
  }) async {
    final response = await _client.post(
      Uri.parse(_chatEndpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0,
        'messages': [
          {
            'role': 'system',
            'content': _systemPromptWithTime(),
          },
          {'role': 'user', 'content': transcript},
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'food_exercise_log',
            'strict': true,
            'schema': _schema,
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      throw OpenAIServiceException(_errorMessage(response, 'parsing'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw const OpenAIServiceException(
          'Couldn\'t make sense of that — try again in plain words.');
    }
    return _fromJson(
      jsonDecode(content) as Map<String, dynamic>,
      weightKg: weightKg,
    );
  }

  /// The coach: a free-form conversation with the same BYOK key. Returns the
  /// assistant's reply.
  Future<String> chat({
    required List<ChatTurn> history,
    required String systemPrompt,
    String model = 'gpt-4o-mini',
  }) async {
    final response = await _client.post(
      Uri.parse(_chatEndpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...history.map((t) => {'role': t.role, 'content': t.content}),
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw OpenAIServiceException(_errorMessage(response, 'chatting'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw const OpenAIServiceException(
          'The coach went quiet — try asking again.');
    }
    return content.trim();
  }

  /// Reviews a conversation exchange against the memory schema and returns
  /// distilled facts to create, update or retire.
  Future<List<MemoryDraft>> distillMemories({
    required List<ChatTurn> exchange,
    String model = 'gpt-4o-mini',
  }) async {
    final response = await _client.post(
      Uri.parse(_chatEndpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0,
        'messages': [
          {'role': 'system', 'content': _memorySystemPrompt},
          {
            'role': 'user',
            'content': exchange
                .map((t) => '${t.role.toUpperCase()}: ${t.content}')
                .join('\n\n'),
          },
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'memory_distill',
            'strict': true,
            'schema': _memorySchema,
          },
        },
      }),
    );
    if (response.statusCode != 200) {
      throw OpenAIServiceException(_errorMessage(response, 'memory review'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.isEmpty) return const [];
    final json = jsonDecode(content) as Map<String, dynamic>;
    final list = (json['memories'] as List?) ?? const [];
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

  /// Scans a coaching exchange for concrete exercise recommendations using a
  /// strict schema, so the response is always well-formed.
  Future<ExerciseExtraction> extractExercises({
    required List<ChatTurn> exchange,
    String model = 'gpt-4o-mini',
  }) async {
    final response = await _client.post(
      Uri.parse(_chatEndpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0,
        'messages': [
          {'role': 'system', 'content': _exerciseSystemPrompt},
          {
            'role': 'user',
            'content': exchange
                .map((t) => '${t.role.toUpperCase()}: ${t.content}')
                .join('\n\n'),
          },
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'exercise_extraction',
            'strict': true,
            'schema': _exerciseSchema,
          },
        },
      }),
    );
    if (response.statusCode != 200) {
      throw OpenAIServiceException(_errorMessage(response, 'workout review'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      return const ExerciseExtraction(hasAdvice: false);
    }
    final json = jsonDecode(content) as Map<String, dynamic>;
    final hasAdvice = (json['has_exercise_advice'] as bool?) ?? false;
    final list = (json['recommendations'] as List?) ?? const [];
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

  static String _errorMessage(http.Response response, String stage) {
    var detail = '';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      detail = (body['error']?['message'] as String?) ?? '';
    } catch (_) {}
    if (response.statusCode == 401) {
      return 'Your API key was rejected. Check it in Settings and save again.';
    }
    if (response.statusCode == 429) {
      return 'OpenAI is rate-limiting right now — wait a few seconds and try again.';
    }
    return 'OpenAI failed during $stage${detail.isNotEmpty ? ': $detail' : ''}. Try again.';
  }

  static ParsedLog _fromJson(Map<String, dynamic> json, {double? weightKg}) {
    final type =
        EntryType.fromApiName((json['entry_type'] as String?) ?? 'meal');
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

  static String _systemPromptWithTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return 'The current local time is $h:$m. Use it to classify each food '
        'entry as breakfast, lunch, dinner or snack (a snack is something '
        'small eaten between meals). Exercises have no meal type (null). '
        '$_systemPrompt';
  }

  static double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
  static double? _numOrNull(dynamic v) => (v as num?)?.toDouble();

  /// The deterministic burn for a parsed exercise. With the user's weight the
  /// engine prices the exercise itself (mechanical work for reps, MET for
  /// duration); without it the model's guess is kept as a best-effort
  /// fallback so callers that don't know the weight still get a number.
  static double _exerciseBurn({
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

  static const _systemPrompt = '''
You turn spoken meal and exercise descriptions into a structured log.
For meals, break the food into individual items with estimated portion
sizes, calories and macros (protein, carbs, fat in grams). Estimate
reasonably when the speaker does not give amounts.
For exercises, list every distinct activity the speaker mentions as its
own entry in the exercises array, each with its sets and reps (when the
speaker gives reps) and its duration in minutes (when the speaker gives
a time). Never merge exercises together and never drop one — if the person
says "5 knee press-ups and 5 dips", both exercises belong in the array.
Never estimate calories: the app computes the burn itself from the sets,
reps and duration, so always set estimated_calories_burned to null.
Be accurate about the spirit of what was said; do not invent items that
were not mentioned. Use the schema exactly. Return JSON only.''';

  static const _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'entry_type',
      'summary',
      'meal_type',
      'items',
      'total_calories',
      'total_protein_g',
      'total_carbs_g',
      'total_fat_g',
      'activity',
      'duration_minutes',
      'estimated_calories_burned',
      'exercises',
    ],
    'properties': {
      'entry_type': {'enum': ['meal', 'exercise'], 'type': 'string'},
      'summary': {'type': 'string'},
      'meal_type': {
        'type': ['string', 'null'],
        'enum': ['breakfast', 'lunch', 'dinner', 'snack', null],
      },
      'items': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'name',
            'quantity',
            'calories',
            'protein_g',
            'carbs_g',
            'fat_g'
          ],
          'properties': {
            'name': {'type': 'string'},
            'quantity': {'type': 'string'},
            'calories': {'type': 'number'},
            'protein_g': {'type': 'number'},
            'carbs_g': {'type': 'number'},
            'fat_g': {'type': 'number'},
          },
        },
      },
      'total_calories': {'type': 'number'},
      'total_protein_g': {'type': 'number'},
      'total_carbs_g': {'type': 'number'},
      'total_fat_g': {'type': 'number'},
      'activity': {'type': ['string', 'null']},
      'duration_minutes': {'type': ['number', 'null']},
      'estimated_calories_burned': {'type': ['number', 'null']},
      'exercises': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'name',
            'sets',
            'reps',
            'duration_minutes',
            'estimated_calories_burned'
          ],
          'properties': {
            'name': {'type': 'string'},
            'sets': {'type': ['integer', 'null']},
            'reps': {'type': ['integer', 'null']},
            'duration_minutes': {'type': ['number', 'null']},
            'estimated_calories_burned': {'type': ['number', 'null']},
          },
        },
      },
    },
  };

  /// Exposed for tests: the strict parsing schema.
  static const parseSchema = _schema;

  static const _memorySystemPrompt = '''
You review coaching conversations and distil what is worth remembering
about this person into short, stable facts that will help future
conversations. A "topic" is a stable identifier for one fact (for example
"training_goal" or "workout_preference"). Keep content to one clear
sentence. Only output "create" for genuinely new facts, "update" when the
conversation changes an existing fact, and "remove" when the person clearly
says an old fact is no longer true. Do not invent facts that were not said.
Use the schema exactly. Return JSON only.''';

  static const _memorySchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['memories'],
    'properties': {
      'memories': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['topic', 'content', 'category', 'action'],
          'properties': {
            'topic': {'type': 'string'},
            'content': {'type': 'string'},
            'category': {
              'enum': ['goal', 'preference', 'pattern', 'fact', 'note'],
              'type': 'string',
            },
            'action': {
              'enum': ['create', 'update', 'remove'],
              'type': 'string',
            },
          },
        },
      },
    },
  };

  static const _exerciseSystemPrompt = '''
You scan coaching conversations for concrete exercise recommendations the
coach gave. Only extract exercises that are specific enough to act on
(named, with at least one of sets, reps, rest or duration). Extract routine
groupings into plan_name when the coach presents a named plan (for example
"Leg Day A"). Set has_exercise_advice to false when the conversation is not
about exercises. Use the schema exactly. Return JSON only.''';

  static const _exerciseSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['has_exercise_advice', 'recommendations'],
    'properties': {
      'has_exercise_advice': {'type': 'boolean'},
      'recommendations': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'name',
            'description',
            'muscle_groups',
            'difficulty',
            'plan_name',
            'sets',
            'reps',
            'rest_seconds',
            'duration_minutes',
          ],
          'properties': {
            'name': {'type': 'string'},
            'description': {'type': 'string'},
            'muscle_groups': {'type': 'array', 'items': {'type': 'string'}},
            'difficulty': {
              'enum': ['beginner', 'intermediate', 'advanced'],
              'type': 'string',
            },
            'plan_name': {'type': 'string'},
            'sets': {'type': ['integer', 'null']},
            'reps': {'type': ['integer', 'null']},
            'rest_seconds': {'type': ['integer', 'null']},
            'duration_minutes': {'type': ['integer', 'null']},
          },
        },
      },
    },
  };
}

