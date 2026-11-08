# Ralph AUTONOMOUS — one round (Harisree Purchase Assistant)

You are the engineer, QA, security reviewer and release manager. Full permission. Never ask questions. If blocked: write BLOCKED in ralph/progress.md, mark the task [!], move on.

## Round
1. Read ralph/fix_plan.md (+ ralph/fix_plan_android.md) and the last 30 lines of ralph/progress.md.
2. If an open [ ] task exists, take the FIRST one. Do only it.
3. If NO open task exists, run DISCOVERY (below), append the findings as new [ ] tasks (max 8, highest impact first), then take the first one.
4. Fix. Add a test per bug. Delete dead code you touch.
5. Verify: backend `pytest -q -x`; `flutter analyze` 0 errors; prod QA (ralph/qa) at 393, 820, 1440 widths after deploy. Zero console errors, zero 5xx, no horizontal overflow.
6. Commit (conventional), push main, wait for Vercel + Render deploy, re-run prod QA for the touched screens.
7. Mark [x]; record before/after numbers in progress.md (3-6 lines). Stop.

## DISCOVERY (run when the plan is empty, or every 10 rounds)
- PERF: ralph/qa/perf.spec.ts on Home, Stock, Purchases, Reports, Search. Flag any screen with >4 API calls on cold load, any duplicate call, first data >3s, any API p95 >1s (Render request logs if available).
- DATA TRUTH: counts agree across Home, Stock, Reports (out, low, pending, month purchases). Units consistent per item. Stale pending (>30d) flagged.
- FLOW: walk purchase → arrive → verify → commit → stock change → notification, and edit/cancel/delete. Any step that does not update the UI within 2s = bug.
- SECURITY: gitleaks on tree + history; dependency audit (pip-audit, `flutter pub outdated`); auth on every route (try cross-business ids); rate limit on login/OTP; CORS allowlist exact; no secrets in logs/APK; JWT expiry + refresh; SQL via ORM/params only.
- UX FOR OLDER STAFF ON MOBILE: min text 16px (body) / 18px (numbers), tap targets >= 48px, contrast >= 4.5:1, one primary action per screen, labels in plain words (no jargon: Sys/Phys/Δ -> "In system / Counted / Difference"), Malayalam-ready layouts (no fixed-width text), no icon-only buttons without a label, confirm only for destructive actions, big pinned Save button above keyboard.
- CODE HEALTH: unused files (analyzer-confirmed), unused deps, files >800 lines, duplicate invalidation paths.

## Rules
- Never print/commit secrets. Secrets only in Render/Vercel/GitHub env. If one is found in tree/history: remove, BLOCKED note to rotate.
- Prod data: QA records named QA-RALPH-, cleaned in the same test. Never touch real business data.
- Schema changes: additive Alembic only.
- Stop conditions: file ralph/STOP exists, or 3 consecutive rounds fail verification (write BLOCKED + reason).
- Output small: pytest -q, tail -40, no whole-file dumps.
