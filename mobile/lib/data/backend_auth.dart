import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'secure_settings.dart';

/// A signed-in backend session. The token is the app's session JWT; the
/// install id is the device's stable, random identifier. [googleLinked] records
/// whether the session came from Google Sign-In.
class BackendSession {
  const BackendSession({
    required this.userId,
    required this.installId,
    required this.token,
    this.googleLinked = false,
  });

  final String userId;
  final String installId;
  final String token;
  final bool googleLinked;
}

class BackendAuthException implements Exception {
  const BackendAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Signs the device into the backend anonymously: the client sends a random
/// install id and receives a user id plus a session token, stored securely for
/// next launch. This is the seam a future Google sign-in would plug into.
class BackendAuth {
  BackendAuth({http.Client? client, String? baseUrl, SecureSettings? store})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? kBackendBaseUrl,
        _store = store ?? SecureSettings();

  final http.Client _client;
  final String _baseUrl;
  final SecureSettings _store;

  static const _timeout = Duration(seconds: 15);

  /// Returns the stored session, or null when this device has never signed in
  /// or the stored token has already expired (in which case the stale session
  /// is cleared so the caller re-signs in rather than repeatedly getting 401s).
  Future<BackendSession?> restore() async {
    final token = await _store.readToken();
    final userId = await _store.readUserId();
    final installId = await _store.readInstallId();
    if (token == null ||
        token.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        installId == null ||
        installId.isEmpty) {
      return null;
    }
    if (_isExpired(token)) {
      await _store.clearSession();
      return null;
    }
    return BackendSession(
      userId: userId,
      installId: installId,
      token: token,
      googleLinked: await _store.readGoogleLinked(),
    );
  }

  /// Signs the device in, reusing the stored install id when there is one so a
  /// returning device keeps the same account.
  Future<BackendSession> signIn() async {
    final installId = await _ensureInstallId();
    final body = await _post('/v1/auth/anonymous', {'install_id': installId});
    return _persist(body, installId: installId, googleLinked: false);
  }

  /// Signs in with a Google ID token. The install id, and the current anonymous
  /// session token when there is one, are sent so the backend links the Google
  /// account to this device's existing account instead of creating a new one.
  Future<BackendSession> signInWithGoogle({required String idToken}) async {
    final installId = await _ensureInstallId();
    final existing = await _store.readToken();
    final body = await _post(
      '/v1/auth/google',
      {'id_token': idToken, 'install_id': installId},
      bearer: (existing != null && existing.isNotEmpty) ? existing : null,
    );
    return _persist(body, installId: installId, googleLinked: true);
  }

  /// POSTs a JSON body to the backend and decodes the reply, mapping transport
  /// and error responses to a [BackendAuthException] with a message safe to
  /// show. The token is never logged.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload, {
    String? bearer,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (bearer != null) headers['Authorization'] = 'Bearer $bearer';

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const BackendAuthException(
          'Weight Buddy took too long to respond. Try again.');
    } catch (_) {
      throw const BackendAuthException(
          'Could not reach Weight Buddy. Check your connection and try again.');
    }
    if (response.statusCode != 200) {
      // Includes the 401 a rejected Google token returns: the backend's error
      // message is already user-safe.
      throw BackendAuthException(_errorMessage(response));
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const BackendAuthException(
          'Weight Buddy returned an unexpected reply. Try again.');
    }
  }

  Future<BackendSession> _persist(
    Map<String, dynamic> body, {
    required String installId,
    required bool googleLinked,
  }) async {
    final token = body['token'] as String?;
    final userId = body['user_id'] as String?;
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      throw const BackendAuthException(
          'Weight Buddy returned an unexpected reply. Try again.');
    }
    await _store.writeToken(token);
    await _store.writeUserId(userId);
    await _store.writeGoogleLinked(googleLinked);
    return BackendSession(
      userId: userId,
      installId: installId,
      token: token,
      googleLinked: googleLinked,
    );
  }

  /// Clears the stored session (keeping the vocabulary) so the next sign-in
  /// creates a fresh identity. Used to recover from a rejected token.
  Future<void> clearSession() => _store.clearSession();

  /// Decodes a JWT's expiry without verifying it. A token we cannot parse is
  /// treated as usable, so this is only a fast path to avoid a known-401 call.
  static bool _isExpired(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      return expiry.isBefore(DateTime.now().toUtc());
    } catch (_) {
      return false;
    }
  }

  Future<String> _ensureInstallId() async {
    final existing = await _store.readInstallId();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomInstallId();
    await _store.writeInstallId(id);
    return id;
  }

  static String _randomInstallId() {
    final rnd = Random.secure();
    return List<int>.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {}
    return 'Could not sign in to Weight Buddy (${response.statusCode}).';
  }
}
