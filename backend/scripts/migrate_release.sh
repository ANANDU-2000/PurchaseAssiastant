#!/usr/bin/env bash
# Run against the same DATABASE_URL / DATABASE_POOLER_* as production (e.g. Render shell).
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONPATH="${PYTHONPATH:-.}"
exec alembic upgrade head
