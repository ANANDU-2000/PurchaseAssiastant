#!/usr/bin/env bash
# Vercel build (Linux). Produces flutter_app/build/web for static hosting.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/flutter_app"

FLUTTER_ROOT="${HOME}/flutter"
if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${PATH}:${FLUTTER_ROOT}/bin"
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter stable (one-time per build)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${FLUTTER_ROOT}"
  export PATH="${PATH}:${FLUTTER_ROOT}/bin"
fi

# dart2js can OOM on Vercel when many workers run in parallel (exit 1 / SIGKILL).
export BUILD_MAX_WORKERS_PER_TASK="${BUILD_MAX_WORKERS_PER_TASK:-1}"
# 3072 MB fits Vercel's 8 GB container better than 4096 alongside the Flutter tool VM.
export DART_VM_OPTIONS="${DART_VM_OPTIONS:---max-old-space-size=3072}"

flutter config --no-analytics
flutter --version
flutter precache --web
flutter pub get

# REQUIRED for production: set API_BASE_URL in Vercel → Environment Variables (Production)
# to your live API origin (e.g. https://your-service.onrender.com). If unset, this default is used.
API_URL="${API_BASE_URL:-https://my-purchases-api.onrender.com}"
GOOGLE_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"

echo "Building web (API=${API_URL})..."
flutter build web --release \
  --no-web-resources-cdn \
  --no-source-maps \
  --no-wasm-dry-run \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID="$GOOGLE_ID"

echo "Built: $ROOT/flutter_app/build/web"
