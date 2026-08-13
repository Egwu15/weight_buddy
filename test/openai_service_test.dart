import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weight_buddy/data/openai_service.dart';
import 'package:weight_buddy/models/log_entry.dart';

void main() {
  group('openai service', () {
    test('parseTranscript parses a meal from strict JSON', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['response_format'], isNotNull);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'entry_type': 'meal',
                    'summary': 'Jollof rice and chicken',
                    'meal_type': 'lunch',
                    'items': [
                      {
                        'name': 'Jollof Rice',
                        'quantity': '2 plates',
                        'calories': 700,
                        'protein_g': 14,
                        'carbs_g': 110,
                        'fat_g': 20,
                      }
                    ],
                    'total_calories': 700,
                    'total_protein_g': 14,
                    'total_carbs_g': 110,
                    'total_fat_g': 20,
                    'activity': null,
                    'duration_minutes': null,
                    'estimated_calories_burned': null,
                  }),
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = OpenAIService(client: client, apiKey: 'sk-test');
      final parsed = await service.parseTranscript('I had jollof rice');
      expect(parsed.type, EntryType.meal);
      expect(parsed.mealType, MealType.lunch);
      expect(parsed.calories, 700);
      expect(parsed.items, hasLength(1));
      expect(parsed.items.first.name, 'Jollof Rice');
    });

    test('parse schema requires the exercises array and its structure', () {
      final schema = OpenAIService.parseSchema;
      final required = (schema['required'] as List).cast<String>();
      expect(required, contains('exercises'));
      final exercises =
          (schema['properties'] as Map<String, dynamic>)['exercises']
              as Map<String, dynamic>;
      expect(exercises, isNotNull);
      // Strict mode also guarantees each exercise carries its structure —
      // the burn engine's inputs — not just a name and a guessed number.
      final items = exercises['items'] as Map<String, dynamic>;
      expect((items['required'] as List).cast<String>(),
          containsAll(['sets', 'reps', 'duration_minutes']));
    });

    test('parseTranscript parses an exercise with nullables', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'entry_type': 'exercise',
                    'summary': '30 min treadmill run',
                    'meal_type': null,
                    'items': <Object>[],
                    'total_calories': 0,
                    'total_protein_g': 0,
                    'total_carbs_g': 0,
                    'total_fat_g': 0,
                    'activity': 'Treadmill Running',
                    'duration_minutes': 30,
                    'estimated_calories_burned': 300,
                  }),
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = OpenAIService(client: client, apiKey: 'sk-test');
      final parsed = await service.parseTranscript('I ran on the treadmill');
      expect(parsed.type, EntryType.exercise);
      expect(parsed.calories, 300);
      expect(parsed.durationMinutes, 30);
    });

    test('parseTranscript keeps every exercise in the exercises array',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'entry_type': 'exercise',
                    'summary': '5 knee press-ups and 5 dips',
                    'meal_type': null,
                    'items': <Object>[],
                    'total_calories': 0,
                    'total_protein_g': 0,
                    'total_carbs_g': 0,
                    'total_fat_g': 0,
                    'activity': 'Dips',
                    'duration_minutes': null,
                    'estimated_calories_burned': null,
                    'exercises': [
                      {
                        'name': 'Knee Press-ups',
                        'sets': 1,
                        'reps': 5,
                        'duration_minutes': null,
                        'estimated_calories_burned': 60,
                      },
                      {
                        'name': 'Dips',
                        'sets': 1,
                        'reps': 5,
                        'duration_minutes': null,
                        'estimated_calories_burned': 80,
                      },
                    ],
                  }),
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = OpenAIService(client: client, apiKey: 'sk-test');
      final parsed = await service.parseTranscript('5 knee pressups and 5 dips');
      final entries = parsed.toEntries(timestamp: 0, rawTranscript: 'raw');
      expect(parsed.type, EntryType.exercise);
      expect(parsed.exerciseList, hasLength(2));
      expect(entries, hasLength(2));
      expect(entries[0].summary, 'Knee Press-ups');
      expect(entries[1].summary, 'Dips');
      // Rows get a +1 ms timestamp bump so the timeline shows them in the
      // order they were spoken (it orders by timestamp only).
      expect(entries[1].timestamp, entries[0].timestamp + 1);
    });

    test('burn is computed deterministically when the weight is known',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'entry_type': 'exercise',
                    'summary': '20 dips',
                    'meal_type': null,
                    'items': <Object>[],
                    'total_calories': 0,
                    'total_protein_g': 0,
                    'total_carbs_g': 0,
                    'total_fat_g': 0,
                    'activity': 'Dips',
                    'duration_minutes': null,
                    'estimated_calories_burned': null,
                    'exercises': [
                      {
                        'name': 'Dips',
                        'sets': 1,
                        'reps': 20,
                        'duration_minutes': 0.75,
                        'estimated_calories_burned': 300,
                      },
                    ],
                  }),
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = OpenAIService(client: client, apiKey: 'sk-test');
      final parsed = await service.parseTranscript('20 dips', weightKg: 87);
      // The model "said" 300 kcal — the engine must override it with the
      // mechanical-work answer (spec: 6–10 kcal for a 20-rep dip set).
      expect(parsed.exercises.single.caloriesBurned, closeTo(7.42, 0.05));
      expect(parsed.calories, closeTo(7.42, 0.05));
      final entry =
          parsed.toEntries(timestamp: 0, rawTranscript: '20 dips').single;
      expect(entry.calories, closeTo(7.42, 0.05));
      expect(entry.sets, 1);
      expect(entry.reps, 20);
    });

    test('chat returns the assistant reply', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/chat/completions');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect((body['messages'] as List).first['role'], 'system');
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'Drink more water.'}}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = OpenAIService(client: client, apiKey: 'sk-test');
      final reply = await service.chat(
        systemPrompt: 'You are a coach.',
        history: const [ChatTurn(role: 'user', content: 'Hi')],
      );
      expect(reply, 'Drink more water.');
    });

    test('chat surfaces HTTP errors as OpenAIServiceException', () async {
      final client = MockClient(
        (request) async =>
            http.Response('{"error":{"message":"nope"}}', 401),
      );
      final service = OpenAIService(client: client, apiKey: 'sk-test');
      expect(
        () => service.chat(systemPrompt: 'x', history: const []),
        throwsA(isA<OpenAIServiceException>()),
      );
    });
  });
}
