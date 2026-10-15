import 'package:flutter_test/flutter_test.dart';

import 'package:weight_buddy/data/backend_auth.dart';
import 'package:weight_buddy/data/google_signin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('idToken fails clearly when no web client id is configured', () async {
    // With an empty client id the service refuses before touching the platform
    // plugin, so this is testable without the sign-in UI.
    final service = GoogleSignInService(webClientId: '');
    expect(
      () => service.idToken(),
      throwsA(isA<BackendAuthException>().having(
        (e) => e.message,
        'message',
        contains('not configured'),
      )),
    );
  });

  test('signOut before initialization is a safe no-op', () async {
    final service = GoogleSignInService(webClientId: '');
    await service.signOut();
  });
}
