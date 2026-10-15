import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weight_buddy/data/backend_auth.dart';

const _base = 'http://backend.test';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('signIn stores a session and restore reads it back', () async {
    final auth = BackendAuth(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/auth/anonymous');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect((body['install_id'] as String).length, greaterThanOrEqualTo(8));
        return http.Response(
          jsonEncode({'token': 'jwt-abc', 'user_id': 'user-1'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: _base,
    );

    expect(await auth.restore(), isNull);

    final session = await auth.signIn();
    expect(session.token, 'jwt-abc');
    expect(session.userId, 'user-1');

    final restored = await auth.restore();
    expect(restored, isNotNull);
    expect(restored!.token, 'jwt-abc');
    expect(restored.userId, 'user-1');
    expect(restored.installId, session.installId);
  });

  test('signIn reuses the stored install id across calls', () async {
    final installIds = <String>[];
    final auth = BackendAuth(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        installIds.add(body['install_id'] as String);
        return http.Response(
          jsonEncode({'token': 'jwt', 'user_id': 'user-1'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: _base,
    );

    await auth.signIn();
    await auth.signIn();
    expect(installIds, hasLength(2));
    expect(installIds.first, installIds.last);
  });

  test('signIn surfaces the backend error message', () async {
    final auth = BackendAuth(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'device_limit', 'message': 'Too many accounts.'},
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: _base,
    );

    expect(
      () => auth.signIn(),
      throwsA(isA<BackendAuthException>()
          .having((e) => e.message, 'message', 'Too many accounts.')),
    );
  });

  test('signIn reports a friendly message when offline', () async {
    final auth = BackendAuth(
      client: MockClient((request) async {
        throw Exception('socket closed');
      }),
      baseUrl: _base,
    );

    expect(
      () => auth.signIn(),
      throwsA(isA<BackendAuthException>().having(
        (e) => e.message,
        'message',
        contains('Could not reach'),
      )),
    );
  });
}
