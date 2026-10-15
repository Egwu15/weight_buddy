import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weight_buddy/data/backend_auth.dart';
import 'package:weight_buddy/data/secure_settings.dart';

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
      throwsA(
        isA<BackendAuthException>().having(
          (e) => e.message,
          'message',
          'Too many accounts.',
        ),
      ),
    );
  });

  test('restore clears an expired stored token', () async {
    final auth = BackendAuth(
      client: MockClient((_) async => http.Response('{}', 500)),
      baseUrl: _base,
    );
    // Seed a stored session whose JWT is already expired.
    FlutterSecureStorage.setMockInitialValues({
      'backend_install_id': 'install-1',
      'backend_user_id': 'user-1',
      'backend_token': _jwt(exp: 1),
    });

    expect(await auth.restore(), isNull);
    // The stale session must be cleared so the next launch signs in fresh.
    expect(await SecureSettings().readToken(), isNull);
  });

  test('clearSession keeps the vocabulary', () async {
    FlutterSecureStorage.setMockInitialValues({
      'backend_install_id': 'install-1',
      'backend_user_id': 'user-1',
      'backend_token': _jwt(exp: 9999999999),
      'custom_vocabulary': 'Jollof, Egusi',
    });

    await BackendAuth(baseUrl: _base).clearSession();

    final store = SecureSettings();
    expect(await store.readToken(), isNull);
    expect(await store.readInstallId(), isNull);
    expect(await store.readVocabulary(), 'Jollof, Egusi');
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
      throwsA(
        isA<BackendAuthException>().having(
          (e) => e.message,
          'message',
          contains('Could not reach'),
        ),
      ),
    );
  });

  test('signInWithGoogle sends the id token and links the session', () async {
    final existing = _jwt(exp: 9999999999);
    FlutterSecureStorage.setMockInitialValues({
      'backend_install_id': 'install-1',
      'backend_user_id': 'anon-user',
      'backend_token': existing,
    });

    late http.Request captured;
    final auth = BackendAuth(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'token': 'jwt-g', 'user_id': 'user-1', 'linked': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: _base,
    );

    final session = await auth.signInWithGoogle(idToken: 'google-id-token');

    expect(captured.url.path, '/v1/auth/google');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['id_token'], 'google-id-token');
    expect(body['install_id'], 'install-1');
    // The current anonymous session rides along so the backend can link it.
    expect(captured.headers['authorization'], 'Bearer $existing');

    expect(session.userId, 'user-1');
    expect(session.googleLinked, isTrue);
    final store = SecureSettings();
    expect(await store.readToken(), 'jwt-g');
    expect(await store.readGoogleLinked(), isTrue);
  });

  test('signInWithGoogle omits the bearer when there is no session', () async {
    late http.Request captured;
    final auth = BackendAuth(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'token': 'jwt-g', 'user_id': 'user-1'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: _base,
    );

    await auth.signInWithGoogle(idToken: 'token');

    expect(captured.headers.containsKey('authorization'), isFalse);
  });

  test('signInWithGoogle surfaces a rejected token (401)', () async {
    final auth = BackendAuth(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'unauthorized',
              'message': 'We could not verify your Google sign-in. Try again.',
            },
          }),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
      baseUrl: _base,
    );

    expect(
      () => auth.signInWithGoogle(idToken: 'bad'),
      throwsA(
        isA<BackendAuthException>().having(
          (e) => e.message,
          'message',
          contains('could not verify'),
        ),
      ),
    );
  });

  test('restore reports a Google-linked session', () async {
    FlutterSecureStorage.setMockInitialValues({
      'backend_install_id': 'install-1',
      'backend_user_id': 'user-1',
      'backend_token': _jwt(exp: 9999999999),
      'backend_google_linked': 'true',
    });

    final restored = await BackendAuth(baseUrl: _base).restore();
    expect(restored, isNotNull);
    expect(restored!.googleLinked, isTrue);
  });

  test('clearIdentity keeps the install id and vocabulary', () async {
    FlutterSecureStorage.setMockInitialValues({
      'backend_install_id': 'install-1',
      'backend_user_id': 'user-1',
      'backend_token': _jwt(exp: 9999999999),
      'backend_google_linked': 'true',
      'custom_vocabulary': 'Jollof, Egusi',
    });

    await SecureSettings().clearIdentity();

    final store = SecureSettings();
    expect(await store.readToken(), isNull);
    expect(await store.readUserId(), isNull);
    expect(await store.readGoogleLinked(), isFalse);
    // The device keeps its identity so the anonymous trial resumes in place.
    expect(await store.readInstallId(), 'install-1');
    expect(await store.readVocabulary(), 'Jollof, Egusi');
  });

  test('deleteAccount sends the session token and accepts 204', () async {
    final token = _jwt(exp: 9999999999);
    FlutterSecureStorage.setMockInitialValues({
      'backend_install_id': 'install-1',
      'backend_user_id': 'user-1',
      'backend_token': token,
    });

    late http.Request captured;
    final auth = BackendAuth(
      client: MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      }),
      baseUrl: _base,
    );

    await auth.deleteAccount();

    expect(captured.method, 'DELETE');
    expect(captured.url.path, '/v1/me');
    expect(captured.headers['authorization'], 'Bearer $token');
  });

  test('deleteAccount surfaces a backend error', () async {
    FlutterSecureStorage.setMockInitialValues({
      'backend_token': _jwt(exp: 9999999999),
    });
    final auth = BackendAuth(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'unauthorized', 'message': 'Sign in first.'},
          }),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
      baseUrl: _base,
    );

    expect(
      () => auth.deleteAccount(),
      throwsA(
        isA<BackendAuthException>().having(
          (e) => e.message,
          'message',
          'Sign in first.',
        ),
      ),
    );
  });

  test('deleteAccount fails without a stored session', () async {
    final auth = BackendAuth(
      client: MockClient((_) async => http.Response('', 204)),
      baseUrl: _base,
    );

    expect(() => auth.deleteAccount(), throwsA(isA<BackendAuthException>()));
  });
}

/// Builds a minimal (unverifiable) JWT with the given expiry for restore tests.
String _jwt({required int exp}) {
  String enc(Map<String, dynamic> map) =>
      base64Url.encode(utf8.encode(jsonEncode(map))).replaceAll('=', '');
  return '${enc({'alg': 'HS256', 'typ': 'JWT'})}.${enc({'exp': exp})}.sig';
}
