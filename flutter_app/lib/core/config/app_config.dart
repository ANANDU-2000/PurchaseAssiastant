/// API base URL. Override at run time:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`
/// - Web/desktop: http://127.0.0.1:8000 (default; override with API_BASE_URL)
/// - Android emulator: http://10.0.2.2:8000
class AppConfig {
  AppConfig._();

  /// Default product name (store listing / package name are separate).
  static const String appName = 'Harisree Purchases';

  /// Vercel web builds: set `API_BASE_URL` in project env (see `scripts/vercel-flutter-build.sh`).
  /// Default uses 127.0.0.1 (not `localhost`) so Windows resolves IPv4 consistently with uvicorn
  /// bound to 127.0.0.1 and avoids ERR_CONNECTION_REFUSED when `localhost` maps to ::1 only.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Web OAuth 2.0 client ID from Google Cloud Console (used as `serverClientId` on iOS/Android so
  /// the ID token audience matches the backend). For Flutter web, also pass as `clientId`.
  /// Build: `--dart-define=GOOGLE_OAUTH_CLIENT_ID=xxx.apps.googleusercontent.com`
  static const String googleOAuthClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
    defaultValue: '',
  );
}
