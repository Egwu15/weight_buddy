import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'secure_settings.dart';

/// A signed-in backend session. The token is the app's session JWT; the
/// install id is the device's stable, random identifier.
class BackendSession {
  const BackendSession({
    required this.userId,
    required this.installId,
    required this.token,
  });

  final String userId;
  final String installId;
  final String token;
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

  /// Returns the stored session, or null when this device has never signed in.
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
    return BackendSession(userId: userId, installId: installId, token: token);
  }

  /// Signs the device in, reusing the stored install id when there is one so a
  /// returning device keeps the same account.
  Future<BackendSession> signIn() async {
    final installId = await _ensureInstallId();
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl/v1/auth/anonymous'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'install_id': installId}),
      );
    } catch (_) {
      throw const BackendAuthException(
          'Could not reach Weight Buddy. Check your connection and try again.');
    }
    if (response.statusCode != 200) {
      throw BackendAuthException(_errorMessage(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    final userId = body['user_id'] as String?;
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      throw const BackendAuthException(
          'Weight Buddy returned an unexpected reply. Try again.');
    }

    await _store.writeToken(token);
    await _store.writeUserId(userId);
    return BackendSession(userId: userId, installId: installId, token: token);
  }

  /// Clears the stored session, so the next sign-in creates a fresh identity.
  Future<void> signOut() => _store.clear();

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
