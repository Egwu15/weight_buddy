import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weight_buddy/data/ai_service.dart';
import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/models/memory.dart';

/// Shared schema contract: the backend owns the JSON schemas, and the Dart
/// parser must map exactly the same property names. This test reads the golden
/// key list the Go test also reads and builds every fixture from it, so if a
/// schema property is renamed the app-side parse visibly breaks here.
void main() {
  final golden = jsonDecode(
    File('../backend/internal/ai/testdata/schema_keys.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  List<String> keys(String name) => (golden[name] as List).cast<String>();

  /// Builds a JSON object from [values], asserting it covers exactly the golden
  /// keys for [name] so a renamed/added schema key fails loudly.
  Map<String, dynamic> fixture(String name, Map<String, dynamic> values) {
    final expected = keys(name);
    for (final key in expected) {
      if (!values.containsKey(key)) {
        fail('golden schema "$name" key "$key" is not covered by the Dart fixture');
      }
    }
    for (final key in values.keys) {
      if (!expected.contains(key)) {
        fail('fixture has key "$key" not present in golden schema "$name"');
      }
    }
    return values;
  }

  test('parse schema keys map into a meal', () {
    final item = fixture('parse_item', {
      'name': 'Jollof Rice',
      'quantity': '2 plates',
      'calories': 700,
      'protein_g': 14,
      'carbs_g': 110,
      'fat_g': 20,
    });
    final meal = fixture('parse', {
      'entry_type': 'meal',
      'summary': 'Jollof rice',
      'meal_type': 'lunch',
      'items': [item],
      'total_calories': 700,
      'total_protein_g': 14,
      'total_carbs_g': 110,
      'total_fat_g': 20,
      'activity': null,
      'duration_minutes': null,
      'estimated_calories_burned': null,
      'exercises': <Object>[],
    });

    final parsed = parsedLogFromJson(meal);
    expect(parsed.type, EntryType.meal);
    expect(parsed.summary, 'Jollof rice');
    expect(parsed.mealType, MealType.lunch);
    expect(parsed.calories, 700);
    expect(parsed.proteinG, 14);
    expect(parsed.carbsG, 110);
    expect(parsed.fatG, 20);
    expect(parsed.items.single.name, 'Jollof Rice');
    expect(parsed.items.single.proteinG, 14);
  });

  test('parse schema keys map into a workout', () {
    final exercise = fixture('parse_exercise_item', {
      'name': 'Dips',
      'sets': null,
      'reps': 5,
      'duration_minutes': null,
      'estimated_calories_burned': null,
    });
    final workout = fixture('parse', {
      'entry_type': 'exercise',
      'summary': 'Dips',
      'meal_type': null,
      'items': <Object>[],
      'total_calories': 0,
      'total_protein_g': 0,
      'total_carbs_g': 0,
      'total_fat_g': 0,
      'activity': null,
      'duration_minutes': null,
      'estimated_calories_burned': null,
      'exercises': [exercise],
    });

    final parsed = parsedLogFromJson(workout, weightKg: 80);
    expect(parsed.type, EntryType.exercise);
    expect(parsed.exercises.single.name, 'Dips');
    expect(parsed.exercises.single.reps, 5);
  });

  test('memory schema keys map into drafts', () async {
    final memory = fixture('memory_item', {
      'topic': 'training_goal',
      'content': 'Marathon in May',
      'category': 'goal',
      'action': 'create',
    });
    final body = fixture('memory', {'memories': [memory]});

    final service = AiService(
      client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      baseUrl: 'http://backend.test',
      token: 't',
    );
    final drafts = await service.distillMemories(
      exchange: const [ChatTurn(role: 'user', content: 'I run marathons')],
    );
    expect(drafts.single.topic, 'training_goal');
    expect(drafts.single.content, 'Marathon in May');
    expect(drafts.single.category, MemoryCategory.goal);
    expect(drafts.single.action, 'create');
  });

  test('exercise schema keys map into recommendations', () async {
    final rec = fixture('exercise_item', {
      'name': 'Bodyweight Squat',
      'description': 'Keep heels down',
      'muscle_groups': ['quads'],
      'difficulty': 'beginner',
      'plan_name': 'Leg Day A',
      'sets': 3,
      'reps': 10,
      'rest_seconds': 60,
      'duration_minutes': null,
    });
    final body = fixture('exercise', {
      'has_exercise_advice': true,
      'recommendations': [rec],
    });

    final service = AiService(
      client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      baseUrl: 'http://backend.test',
      token: 't',
    );
    final result = await service.extractExercises(
      exchange: const [ChatTurn(role: 'user', content: 'leg exercises')],
    );
    expect(result.hasAdvice, isTrue);
    final draft = result.drafts.single;
    expect(draft.name, 'Bodyweight Squat');
    expect(draft.muscleGroups, ['quads']);
    expect(draft.difficulty, 'beginner');
    expect(draft.planName, 'Leg Day A');
    expect(draft.sets, 3);
    expect(draft.reps, 10);
    expect(draft.restSeconds, 60);
  });
}
