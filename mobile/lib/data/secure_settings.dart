import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the backend session (install id, user id, token) and the custom
/// vocabulary in the platform secure store (Keychain / Encrypted
/// SharedPreferences). The AI provider key never reaches the device — it lives
/// on the backend.
class SecureSettings {
  SecureSettings({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyInstallId = 'backend_install_id';
  static const _keyUserId = 'backend_user_id';
  static const _keyToken = 'backend_token';
  static const _keyVocabulary = 'custom_vocabulary';

  Future<String?> readInstallId() => _storage.read(key: _keyInstallId);
  Future<void> writeInstallId(String value) =>
      _storage.write(key: _keyInstallId, value: value);

  Future<String?> readUserId() => _storage.read(key: _keyUserId);
  Future<void> writeUserId(String value) =>
      _storage.write(key: _keyUserId, value: value);

  Future<String?> readToken() => _storage.read(key: _keyToken);
  Future<void> writeToken(String value) =>
      _storage.write(key: _keyToken, value: value);

  /// The custom vocabulary as a comma-separated hint string, e.g.
  /// "Jollof, Egusi, Amala, Suya, Akara, Dodo".
  Future<String?> readVocabulary() => _storage.read(key: _keyVocabulary);
  Future<void> writeVocabulary(String value) =>
      _storage.write(key: _keyVocabulary, value: value);

  /// Removes only the session (install id, user id, token), keeping the user's
  /// vocabulary. Used when a stored session is no longer valid.
  Future<void> clearSession() async {
    await _storage.delete(key: _keyInstallId);
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyToken);
  }

  /// Removes the session and vocabulary, returning the app to the state it
  /// starts in on a fresh install.
  Future<void> clear() async {
    await clearSession();
    await _storage.delete(key: _keyVocabulary);
  }
}
