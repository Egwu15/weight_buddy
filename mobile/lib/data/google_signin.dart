import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import 'backend_auth.dart';

/// Thrown when the user dismisses the Google sign-in dialog. Callers show
/// nothing — an explicit cancel is not an error.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// The source of a Google ID token. Abstract so tests can substitute a fake
/// instead of driving the platform sign-in UI.
abstract class GoogleIdTokenProvider {
  /// Runs the interactive Google sign-in and returns an ID token. Throws
  /// [GoogleSignInCancelled] when the user cancels and [BackendAuthException]
  /// with a user-safe message for any other failure.
  Future<String> idToken();

  /// Clears the Google session on this device. Best effort.
  Future<void> signOut();
}

/// Google Sign-In backed by the `google_sign_in` plugin. The OAuth *Web* client
/// id is passed as the `serverClientId`, so the returned ID token is audienced
/// for our backend (which verifies the same id).
class GoogleSignInService implements GoogleIdTokenProvider {
  GoogleSignInService({String? webClientId})
      : _webClientId = (webClientId ?? kGoogleWebClientId).trim();

  final String _webClientId;
  bool _initialized = false;

  /// `GoogleSignIn.instance` must be initialized exactly once before any other
  /// call; this guards that and fails clearly when the build has no client id.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (_webClientId.isEmpty) {
      throw const BackendAuthException(
          'Google sign-in is not configured for this build.');
    }
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _initialized = true;
  }

  @override
  Future<String> idToken() async {
    await _ensureInitialized();
    final signIn = GoogleSignIn.instance;
    if (!signIn.supportsAuthenticate()) {
      throw const BackendAuthException(
          'Google sign-in is not available on this device.');
    }

    final GoogleSignInAccount account;
    try {
      account = await signIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleSignInCancelled();
      }
      throw BackendAuthException(_messageFor(e));
    } catch (_) {
      throw const BackendAuthException(
          'Could not reach Google. Check your connection and try again.');
    }

    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw const BackendAuthException(
          'Google did not return a sign-in token. Try again.');
    }
    return token;
  }

  @override
  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Best effort: a failed Google sign-out must not trap the user.
    }
  }

  static String _messageFor(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Google sign-in was cancelled.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is not set up correctly for this build.';
      default:
        return 'Google sign-in failed. Try again.';
    }
  }
}
