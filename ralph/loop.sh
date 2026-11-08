#!/usr/bin/env bash
# Ralph loop: fresh Claude Code context per task until fix_plan is done.
# Usage: QA_EMAIL=... QA_PASSWORD=... MODEL=sonnet bash ralph/loop.sh [max_iterations]
set -uo pipefail
cd "$(dirname "$0")/.."
MAX="${1:-60}"
MODEL="${MODEL:-sonnet}"          # sonnet for the loop; set MODEL=opus for hard phases
touch ralph/progress.md
for i in $(seq 1 "$MAX"); do
  if [ -f ralph/STOP ]; then echo "STOP file found"; break; fi
  if tail -1 ralph/progress.md | grep -q "ALL DONE"; then echo "All tasks done"; break; fi
  if ! grep -q '^- \[ \]' ralph/fix_plan.md; then echo "No open tasks"; break; fi
  echo "=== Iteration $i ($(date '+%F %T')) — next: $(grep -m1 '^- \[ \]' ralph/fix_plan.md | cut -c1-100)"
  git pull -q --rebase origin main || true
  claude -p "$(cat ralph/PROMPT.md)" \
    --model "$MODEL" \
    --dangerously-skip-permissions \
    --max-turns 80 \
    --output-format text 2>&1 | tail -25 | tee -a ralph/loop.log
  sleep 5
done
