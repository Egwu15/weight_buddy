import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weight_buddy/data/ai_service.dart';
import 'package:weight_buddy/models/memory.dart';

const _base = 'http://backend.test';

void main() {
  group('coach artifacts', () {
    test('distillMemories parses create drafts with categories', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/ai/distill-memories');
        expect(request.headers['Authorization'], 'Bearer sk-test');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['exchange'], isA<List>());
        return http.Response(
          jsonEncode({
            'memories': [
              {
                'topic': 'training_goal',
                'content': 'Marathon in May',
                'category': 'goal',
                'action': 'create',
              },
              {
                'topic': 'breakfast',
                'content': 'Hates breakfast',
                'category': 'preference',
                'action': 'create',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AiService(client: client, baseUrl: _base, token: 'sk-test');
      final drafts = await service.distillMemories(
        exchange: const [ChatTurn(role: 'user', content: 'I hate breakfast')],
      );
      expect(drafts, hasLength(2));
      expect(drafts.first.topic, 'training_goal');
      expect(drafts.first.category, MemoryCategory.goal);
      expect(drafts.last.category, MemoryCategory.preference);
      expect(drafts.last.action, 'create');
    });

    test('extractExercises parses concrete recommendations', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/ai/extract-exercises');
        return http.Response(
          jsonEncode({
            'has_exercise_advice': true,
            'recommendations': [
              {
                'name': 'Bodyweight Squat',
                'description': 'Keep heels down',
                'muscle_groups': ['quads', 'glutes'],
                'difficulty': 'beginner',
                'plan_name': 'Leg Day A',
                'sets': 3,
                'reps': 10,
                'rest_seconds': 60,
                'duration_minutes': null,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AiService(client: client, baseUrl: _base, token: 'sk-test');
      final result = await service.extractExercises(
        exchange:
            const [ChatTurn(role: 'user', content: 'give me leg exercises')],
      );
      expect(result.hasAdvice, isTrue);
      expect(result.drafts, hasLength(1));
      expect(result.drafts.first.name, 'Bodyweight Squat');
      expect(result.drafts.first.sets, 3);
      expect(result.drafts.first.reps, 10);
      expect(result.drafts.first.durationMinutes, isNull);
      expect(result.drafts.first.muscleGroups, contains('quads'));
    });

    test('extractExercises tolerates has_exercise_advice=false', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'has_exercise_advice': false,
            'recommendations': <Object>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AiService(client: client, baseUrl: _base, token: 'sk-test');
      final result = await service.extractExercises(
        exchange: const [ChatTurn(role: 'user', content: 'hi')],
      );
      expect(result.hasAdvice, isFalse);
      expect(result.drafts, isEmpty);
    });
  });
}
