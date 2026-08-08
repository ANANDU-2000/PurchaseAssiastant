#!/usr/bin/env bash
# Fail CI if dead Render API hosts appear outside archive/.
# Canonical production API: https://api.harisreeagency.online
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Build patterns without embedding the full host literals as searchable text.
DEAD1="my-purchases-api$(printf '%s' '.onrender.com')"
DEAD2="harisree-api$(printf '%s' '.onrender.com')"
PATTERN="${DEAD1}|${DEAD2}"

# Allowlist: historical scripts only (paths containing /archive/), plus this guard.
hits="$(
  git grep -nE "$PATTERN" -- . \
    ':(exclude)**/archive/**' \
    ':(exclude)**/scripts/archive/**' \
    ':(exclude)**/backend/scripts/archive/**' \
    ':(exclude)scripts/assert-no-dead-api-hosts.sh' \
  || true
)"

if [[ -n "${hits}" ]]; then
  echo "ERROR: Dead Render API hosts found outside archive/:" >&2
  echo "${hits}" >&2
  echo >&2
  echo "Use https://api.harisreeagency.online (see scripts/canonical-urls.ps1)." >&2
  echo "Historical references belong under **/archive/** only." >&2
  exit 1
fi

echo "OK: no dead Render API hosts outside archive/"
