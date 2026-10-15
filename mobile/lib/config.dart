/// Build-time configuration.
library;

/// Base URL of the Weight Buddy backend. Override for real devices with:
///
///   flutter run --dart-define=BACKEND_BASE_URL=https://api.example.com
const String kBackendBaseUrl = String.fromEnvironment(
  'BACKEND_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// The Google OAuth *Web* client id, passed to Google Sign-In as the
/// `serverClientId` so the app requests an ID token our backend can verify
/// (the backend checks the same value as the token audience). It must match
/// `GOOGLE_WEB_CLIENT_ID` on the backend. Set it at build time with:
///
///   flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
const String kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
);
