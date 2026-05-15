#!/usr/bin/env bash
# Vercel build (Linux). Produces flutter_app/build/web for static hosting.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/flutter_app"

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${PATH}:${HOME}/flutter/bin"
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter stable (one-time per build)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${HOME}/flutter"
  export PATH="${PATH}:${HOME}/flutter/bin"
fi

# Increase memory for dart2js
export DART_VM_OPTIONS="--max-old-space-size=4096"

flutter config --no-analytics
flutter pub get

# REQUIRED for production: set API_BASE_URL in Vercel → Environment Variables (Production)
# to your live API origin (e.g. https://your-service.onrender.com). If unset, this default is used.
API_URL="${API_BASE_URL:-https://my-purchases-api.onrender.com}"
GOOGLE_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"

# Using --web-renderer html to save memory and improve stability on Vercel.
flutter build web --release --verbose \
  --web-renderer html \
  --no-web-resources-cdn \
  --no-source-maps \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID="$GOOGLE_ID"


echo "Built: $ROOT/flutter_app/build/web"
