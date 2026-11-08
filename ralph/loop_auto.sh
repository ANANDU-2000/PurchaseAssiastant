#!/usr/bin/env bash
# Autonomous Ralph: runs until STOP file, max rounds, or 3 consecutive failed rounds.
# Usage: set -a; source ralph/qa/.env; set +a; MODEL=sonnet bash ralph/loop_auto.sh 100
set -uo pipefail
cd "$(dirname "$0")/.."
MAX="${1:-100}"; MODEL="${MODEL:-sonnet}"; FAILS=0
touch ralph/progress.md
for i in $(seq 1 "$MAX"); do
  [ -f ralph/STOP ] && { echo "STOP file"; break; }
  [ "$FAILS" -ge 3 ] && { echo "3 failed rounds in a row — stopping"; break; }
  git pull -q --rebase origin main || true
  BEFORE=$(git rev-parse HEAD)
  echo "=== Round $i $(date '+%F %T')"
  claude -p "$(cat ralph/PROMPT_AUTO.md)" --model "$MODEL" \
    --dangerously-skip-permissions --max-turns 100 --output-format text 2>&1 \
    | tail -20 | tee -a ralph/loop.log
  AFTER=$(git rev-parse HEAD)
  if [ "$BEFORE" = "$AFTER" ]; then FAILS=$((FAILS+1)); else FAILS=0; fi
  sleep 10
done
