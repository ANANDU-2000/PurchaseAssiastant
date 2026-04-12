/// API base URL. Override at run time:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`
/// - Web/desktop: http://localhost:8000
/// - Android emulator: http://10.0.2.2:8000
class AppConfig {
  AppConfig._();

  /// Default product name (store listing / package name are separate).
  static const String appName = 'My Purchases';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Web OAuth 2.0 client ID from Google Cloud Console (used as `serverClientId` on iOS/Android so
  /// the ID token audience matches the backend). For Flutter web, also pass as `clientId`.
  /// Build: `--dart-define=GOOGLE_OAUTH_CLIENT_ID=xxx.apps.googleusercontent.com`
  static const String googleOAuthClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
    defaultValue: '',
  );
}
