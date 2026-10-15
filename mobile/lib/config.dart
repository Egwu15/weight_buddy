/// Build-time configuration.
library;

/// Base URL of the Weight Buddy backend. Override for real devices with:
///
///   flutter run --dart-define=BACKEND_BASE_URL=https://api.example.com
const String kBackendBaseUrl = String.fromEnvironment(
  'BACKEND_BASE_URL',
  defaultValue: 'http://localhost:8080',
);
