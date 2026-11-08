# Harisree Purchase Assistant (Flutter web/Android + FastAPI + Postgres)
Prod: web https://purchase-assiastant.vercel.app, API https://my-purchases-api.onrender.com. Test prod only, never local.
Read first: ralph/PROMPT_AUTO.md, ralph/fix_plan.md, last 30 lines of ralph/progress.md. DESIGN.md for UI.

## Hard rules
- Never print or commit secrets; they live in Render/Vercel/GitHub env. QA login is in gitignored ralph/qa/.env.
- Prod test data is named QA-RALPH- and cleaned up in the same test.
- Schema changes: additive Alembic migrations only.
- AI/voice/MCP writes need an explicit confirm step.
- Every bug gets a test. flutter analyze: 0 errors. Backend: pytest -q.
- UI: one button, card, chip, status badge. No gradients, emoji icons, nested cards, filler copy.
- Staff are older, on phones: 16px min text, 48px tap targets, plain labels, pinned Save above keyboard.

## Performance rules (enforce on every change)
- Skeletons, not spinners. Debounce search 250-300ms. Virtualize lists over 50 rows.
- One shared query cache; same request never fires twice. One StockWriteCoordinator for refresh after writes.
- Optimistic UI with rollback for counts and toggles.
- API: paginate every list, select only needed columns, batch (no N+1), run independent calls in parallel, index WHERE/JOIN/ORDER BY columns, gzip on, strict timeouts on external calls.
- Heavy work (PDF, email, OCR) goes to background jobs. Stream AI replies.
- Keep deps lean; remove unused. Self-host fonts, limit weights. Cache static assets.
- Verify with ralph/qa/perf.spec.ts (393px, Fast 4G, 4x CPU). Targets: first data under 3s, at most 4 API calls cold, no duplicates.
