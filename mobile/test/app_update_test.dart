import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weight_buddy/data/app_update.dart';

void main() {
  test('parses the version response', () async {
    final service = AppUpdateService(
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/app/version');
        return http.Response(
          jsonEncode({
            'minimum_version': '1.2.0',
            'store_url':
                'https://play.google.com/store/apps/details?id=com.tedif.weight_buddy',
            'message': 'Please update to continue.',
          }),
          200,
        );
      }),
    );

    final update = await service.fetch();
    expect(update, isNotNull);
    expect(update!.minimumVersion, '1.2.0');
    expect(update.message, 'Please update to continue.');
  });

  test('returns null on a server error', () async {
    final service = AppUpdateService(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(await service.fetch(), isNull);
  });

  test('returns null on malformed JSON', () async {
    final service = AppUpdateService(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => http.Response('not json', 200)),
    );
    expect(await service.fetch(), isNull);
  });

  test('returns null when a required field is missing', () async {
    final service = AppUpdateService(
      baseUrl: 'https://api.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'minimum_version': '1.2.0',
            'store_url': 'https://play.google.com/store',
          }),
          200,
        ),
      ),
    );
    expect(await service.fetch(), isNull);
  });

  test('rejects a non-https store URL', () {
    final update = AppUpdate.fromJson({
      'minimum_version': '1.2.0',
      'store_url': 'http://play.google.com/store',
      'message': 'Please update.',
    });
    expect(update, isNull);
  });
}
