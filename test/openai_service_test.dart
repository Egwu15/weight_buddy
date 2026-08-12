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
      expect(parsed.calories, 700);
      expect(parsed.items, hasLength(1));
      expect(parsed.items.first.name, 'Jollof Rice');
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
