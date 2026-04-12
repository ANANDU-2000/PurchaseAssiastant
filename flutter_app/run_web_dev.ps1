# Customer app (Flutter web). You MUST pass --no-web-resources-cdn so CanvasKit is served from
# this machine (/canvaskit/). Without it, the page often stays WHITE after DDC loads (CDN blocked).
# web/flutter_bootstrap.js sets canvasKitBaseUrl and canvasKitVariant: full — keep in sync with Flutter docs.
# Use full Chrome to verify UI; Cursor's embedded Simple Browser often cannot composite the Flutter canvas.
#
# 1) API:  http://127.0.0.1:8000/health
# 2) Run:
Set-Location $PSScriptRoot
flutter run -d chrome `
  --web-port 8080 `
  --no-web-resources-cdn `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
