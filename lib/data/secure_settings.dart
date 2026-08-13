import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the user's own OpenAI API key and custom vocabulary in the
/// platform secure store (Keychain / Encrypted SharedPreferences).
class SecureSettings {
  SecureSettings({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyApiKey = 'openai_api_key';
  static const _keyVocabulary = 'custom_vocabulary';

  Future<String?> readApiKey() => _storage.read(key: _keyApiKey);

  Future<void> writeApiKey(String value) =>
      _storage.write(key: _keyApiKey, value: value);

  /// The custom vocabulary as a comma-separated hint string, e.g.
  /// "Jollof, Egusi, Amala, Suya, Akara, Dodo".
  Future<String?> readVocabulary() => _storage.read(key: _keyVocabulary);

  Future<void> writeVocabulary(String value) =>
      _storage.write(key: _keyVocabulary, value: value);

  /// Removes both secrets, returning the app to the unconfigured state it
  /// starts in on a fresh install.
  Future<void> clear() async {
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyVocabulary);
  }
}
