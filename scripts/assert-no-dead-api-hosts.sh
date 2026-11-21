#!/usr/bin/env bash
# Fail CI if a retired API host appears in shipped code/config.
# The Cloudflare-tunnel host api.harisreeagency.online is the TARGET API after the cut-over, so it is no longer listed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEAD2="harisree-api$(printf '%s' '.onrender.com')"
PATTERN="${DEAD2}"
hits="$(
  git grep -nE "$PATTERN" -- '*.dart' '*.yml' '*.yaml' '*.json' '*.py' \
    ':(exclude)**/archive/**' \
    ':(exclude)scripts/assert-no-dead-api-hosts.sh' \
    ':(exclude)scripts/vercel-flutter-build.sh' \
  || true
)"
if [[ -n "${hits}" ]]; then
  echo "ERROR: Dead API hosts found:" >&2; echo "${hits}" >&2
  echo "Use https://my-purchases-api.onrender.com" >&2
  exit 1
fi
echo "OK: no dead API hosts"
