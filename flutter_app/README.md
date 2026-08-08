# HEXA — Flutter app

Web/PWA client for Purchase Assistant. Product overview and stack: root [README.md](../README.md). Rules: [AGENTS.md](../AGENTS.md). Deploy: [DEPLOYMENT.md](../DEPLOYMENT.md).

## Prerequisite

Install [Flutter](https://docs.flutter.dev/get-started/install). This folder is a **source scaffold**; after installing Flutter:

```bash
cd flutter_app
flutter create . --project-name harisree_warehouse
flutter pub get
```

`flutter create .` adds platform folders without overwriting `lib/` (confirm when prompted). Native platform folders are **not** shipped for production — production is web/PWA.

## API base URL (`API_BASE_URL`)

Client reads the backend URL from `--dart-define` (see `lib/core/config/app_config.dart`). Default: `http://localhost:8000`.

| Target | Example |
|--------|---------|
| Chrome / desktop | `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000` |
| Android emulator | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000` |
| Physical device | LAN IP, e.g. `--dart-define=API_BASE_URL=http://192.168.1.10:8000` |

### Vercel (Flutter web)

Root [`vercel.json`](../vercel.json) builds and publishes `flutter_app/build/web`.

- **Root Directory** = repository root (`.`)
- **Production env:** `API_BASE_URL=https://api.harisreeagency.online`, `GOOGLE_OAUTH_CLIENT_ID=<Web client ID>`
- Canonical host: [https://purchase-assiastant.vercel.app](https://purchase-assiastant.vercel.app) (spelling **assiastant**)

## Google Sign-In

1. Google Cloud: Web OAuth client ID (also iOS/Android clients as needed).
2. Backend `.env`: `GOOGLE_OAUTH_CLIENT_IDS=<web-client-id>`
3. Flutter: `--dart-define=GOOGLE_OAUTH_CLIENT_ID=<same-web-client-id>`
4. iOS: reversed client ID URL scheme in `Info.plist` when building native.

## Testing

```bash
flutter analyze
flutter test
```

If `flutter test` fails deleting `build\` (OneDrive locks), remove `flutter_app/build` manually and retry.
