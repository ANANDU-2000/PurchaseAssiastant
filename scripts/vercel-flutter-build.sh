#!/usr/bin/env bash
# Vercel build (Linux). Produces flutter_app/build/web for static hosting.
set -euo pipefail
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/flutter_app"
BUILD_LOG="/tmp/flutter-web-build.log"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.6}"
FLUTTER_ROOT="${HOME}/flutter-${FLUTTER_VERSION}"

on_fail() {
  echo "=== Vercel Flutter web build FAILED ==="
  if [ -f "$BUILD_LOG" ]; then
    echo "--- Last 100 lines of build log ---"
    tail -100 "$BUILD_LOG"
    echo "--- dart2js / compile errors (grep) ---"
    grep -E "Error:|error:|isn't defined|Compilation failed|SIGKILL|Killed" "$BUILD_LOG" || true
  fi
}
trap on_fail ERR

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${PATH}:${FLUTTER_ROOT}/bin"
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter ${FLUTTER_VERSION}..."
  git clone https://github.com/flutter/flutter.git -b "${FLUTTER_VERSION}" --depth 1 "${FLUTTER_ROOT}" \
    || git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${FLUTTER_ROOT}"
  export PATH="${PATH}:${FLUTTER_ROOT}/bin"
fi

# dart2js OOM on Vercel often exits with code 1 and no clear "Error:" line.
export BUILD_MAX_WORKERS_PER_TASK="${BUILD_MAX_WORKERS_PER_TASK:-1}"
export DART_VM_OPTIONS="${DART_VM_OPTIONS:---max-old-space-size=3072}"

flutter config --no-analytics
flutter --version
flutter precache --web
flutter pub get

echo "Analyzing (fail fast before dart2js)..."
flutter analyze --no-fatal-infos --no-fatal-warnings

echo "Clean + build web (-O2 lowers dart2js memory vs default -O4)..."
flutter clean
flutter pub get

API_URL="${API_BASE_URL:-https://my-purchases-api.onrender.com}"
GOOGLE_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"

echo "Building web (API=${API_URL})..."
flutter build web --release \
  -O2 \
  --pwa-strategy=none \
  --no-web-resources-cdn \
  --no-source-maps \
  --no-wasm-dry-run \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID="$GOOGLE_ID" \
  2>&1 | tee "$BUILD_LOG"

echo "Built: $ROOT/flutter_app/build/web"
