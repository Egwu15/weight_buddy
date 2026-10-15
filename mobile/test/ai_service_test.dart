import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weight_buddy/data/ai_service.dart';
import 'package:weight_buddy/models/log_entry.dart';

const _base = 'http://backend.test';

void main() {
  group('ai service (backend client)', () {
    test('parseTranscript parses a meal from the backend reply', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/ai/parse');
        expect(request.headers['Authorization'], 'Bearer test-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['transcript'], 'I had jollof rice');
        expect(body['local_time'], matches(RegExp(r'^\d{2}:\d{2}$')));
        return http.Response(
          jsonEncode({
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
            'exercises': <Object>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service =
          AiService(client: client, baseUrl: _base, token: 'test-token');
      final parsed = await service.parseTranscript('I had jollof rice');
      expect(parsed.type, EntryType.meal);
      expect(parsed.mealType, MealType.lunch);
      expect(parsed.calories, 700);
      expect(parsed.items, hasLength(1));
      expect(parsed.items.first.name, 'Jollof Rice');
    });

    test('parseTranscript parses a multi-exercise workout', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'entry_type': 'exercise',
            'summary': 'Press-ups and dips',
            'meal_type': null,
            'items': <Object>[],
            'total_calories': 0,
            'total_protein_g': 0,
            'total_carbs_g': 0,
            'total_fat_g': 0,
            'activity': null,
            'duration_minutes': null,
            'estimated_calories_burned': null,
            'exercises': [
              {'name': 'Press-ups', 'sets': null, 'reps': 5, 'duration_minutes': null, 'estimated_calories_burned': null},
              {'name': 'Dips', 'sets': null, 'reps': 5, 'duration_minutes': null, 'estimated_calories_burned': null},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service =
          AiService(client: client, baseUrl: _base, token: 'test-token');
      final parsed = await service.parseTranscript('5 press-ups and 5 dips');
      expect(parsed.type, EntryType.exercise);
      expect(parsed.exercises, hasLength(2));
      expect(parsed.exercises.first.reps, 5);
    });

    test('transcribe uploads audio and returns the text', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/ai/transcribe');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.headers['content-type'], contains('multipart/form-data'));
        return http.Response(
          jsonEncode({'text': 'two plates of jollof'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service =
          AiService(client: client, baseUrl: _base, token: 'test-token');
      final text = await service.transcribe(
        audioBytes: Uint8List.fromList([1, 2, 3]),
        filename: 'note.m4a',
        prompt: 'Jollof',
      );
      expect(text, 'two plates of jollof');
    });

    test('chat returns the coach reply', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/ai/chat');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['system_prompt'], 'be a coach');
        return http.Response(
          jsonEncode({'reply': '  drink water  '}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service =
          AiService(client: client, baseUrl: _base, token: 'test-token');
      final reply = await service.chat(
        systemPrompt: 'be a coach',
        history: const [ChatTurn(role: 'user', content: 'hi')],
      );
      expect(reply, 'drink water');
    });

    test('me parses tier and remaining limits', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/me');
        return http.Response(
          jsonEncode({
            'user_id': 'u1',
            'tier': 'paid',
            'entitlement': {
              'entitlement': 'pro',
              'status': 'active',
              'is_active': true,
            },
            'limits': [
              {'kind': 'transcribe', 'limit': 300, 'used': 12, 'remaining': 288},
            ],
            'spend_remaining_usd': 24.5,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service =
          AiService(client: client, baseUrl: _base, token: 'test-token');
      final info = await service.me();
      expect(info.tier, 'paid');
      expect(info.isActive, isTrue);
      expect(info.limits.single.remaining, 288);
      expect(info.spendRemainingUsd, 24.5);
    });

    test('surfaces the backend error message verbatim', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'limit_reached',
              'message': 'You have used today\'s allowance for this feature.',
            }
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });
      final service =
          AiService(client: client, baseUrl: _base, token: 'test-token');
      expect(
        () => service.parseTranscript('jollof'),
        throwsA(isA<AiServiceException>().having(
          (e) => e.message,
          'message',
          contains('allowance'),
        )),
      );
    });

    test('maps a 401 to a sign-in message', () async {
      final client = MockClient((request) async => http.Response('', 401));
      final service =
          AiService(client: client, baseUrl: _base, token: 'test-token');
      expect(
        () => service.me(),
        throwsA(isA<AiServiceException>().having(
          (e) => e.message,
          'message',
          contains('session'),
        )),
      );
    });
  });
}
