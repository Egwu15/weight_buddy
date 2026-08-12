import 'dart:convert';

/// A single exercise the coach recommended, auto-saved so it can be
/// referenced later without hunting through chat history.
class ExerciseRecommendation {
  const ExerciseRecommendation({
    this.id,
    required this.name,
    this.description = '',
    this.muscleGroups = const [],
    this.sets,
    this.reps,
    this.restSeconds,
    this.durationMinutes,
    this.difficulty = '',
    this.planName = '',
    this.sourceChatId,
    required this.createdAt,
    this.archived = false,
  });

  final int? id;
  final String name;
  final String description;
  final List<String> muscleGroups;
  final int? sets;
  final int? reps;
  final int? restSeconds;
  final int? durationMinutes;
  final String difficulty;
  final String planName;

  /// Id of the chat message that produced it, when known.
  final int? sourceChatId;
  final int createdAt;
  final bool archived;

  ExerciseRecommendation copyWith({
    int? id,
    String? description,
    bool? archived,
  }) =>
      ExerciseRecommendation(
        id: id ?? this.id,
        name: name,
        description: description ?? this.description,
        muscleGroups: muscleGroups,
        sets: sets,
        reps: reps,
        restSeconds: restSeconds,
        durationMinutes: durationMinutes,
        difficulty: difficulty,
        planName: planName,
        sourceChatId: sourceChatId,
        createdAt: createdAt,
        archived: archived ?? this.archived,
      );

  /// A compact sentence describing the recommended work, e.g. "3 × 10".
  String get prescription {
    final parts = <String>[];
    if (sets != null && sets! > 0) parts.add('$sets sets');
    if (reps != null && reps! > 0) parts.add('$reps reps');
    if (durationMinutes != null && durationMinutes! > 0) {
      parts.add('$durationMinutes min');
    }
    if (restSeconds != null && restSeconds! > 0) {
      parts.add('$restSeconds s rest');
    }
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'description': description,
        'muscle_groups': jsonEncode(muscleGroups),
        'sets': sets,
        'reps': reps,
        'rest_seconds': restSeconds,
        'duration_minutes': durationMinutes,
        'difficulty': difficulty,
        'plan_name': planName,
        'source_chat_id': sourceChatId,
        'created_at': createdAt,
        'archived': archived ? 1 : 0,
      };

  factory ExerciseRecommendation.fromMap(Map<String, Object?> map) {
    final groupsRaw = map['muscle_groups'] as String?;
    List<String> groups = const [];
    if (groupsRaw != null && groupsRaw.isNotEmpty) {
      try {
        groups = (jsonDecode(groupsRaw) as List).map((e) => '$e').toList();
      } catch (_) {
        groups = const [];
      }
    }
    return ExerciseRecommendation(
      id: map['id'] as int?,
      name: (map['name'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      muscleGroups: groups,
      sets: (map['sets'] as num?)?.toInt(),
      reps: (map['reps'] as num?)?.toInt(),
      restSeconds: (map['rest_seconds'] as num?)?.toInt(),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt(),
      difficulty: (map['difficulty'] as String?) ?? '',
      planName: (map['plan_name'] as String?) ?? '',
      sourceChatId: (map['source_chat_id'] as num?)?.toInt(),
      createdAt: (map['created_at'] as num).toInt(),
      archived: (map['archived'] as num?)?.toInt() == 1,
    );
  }
}
