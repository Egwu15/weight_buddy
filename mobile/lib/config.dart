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

/// Base URL of the public website (privacy policy, terms of service and the
/// account-deletion page). The same Go binary serves the API and the site, so
/// this defaults to the backend host. Override when the site lives on its own
/// domain:
///
///   flutter run --dart-define=SITE_BASE_URL=https://weightbuddy.app
const String kSiteBaseUrl = String.fromEnvironment(
  'SITE_BASE_URL',
  defaultValue: kBackendBaseUrl,
);

/// Version identifier of the legal documents the app links to and records
/// acceptance for. It must match the site's "last updated" date
/// (`backend/web/src/config.ts` -> `lastUpdated`) and is bumped whenever the
/// privacy policy or terms change. Freeze the outgoing version first with
/// `make legal-snapshot` so the accepted wording stays available.
const String kLegalVersion = '2026-10-17';

/// Public legal pages, linked from Settings and required by the Play listing.
const String kPrivacyUrl = '$kSiteBaseUrl/privacy';
const String kTermsUrl = '$kSiteBaseUrl/terms';
const String kDeleteAccountUrl = '$kSiteBaseUrl/delete-account';
