# fix_plan — Harisree Purchase Assistant (Ralph loop source of truth)

Legend: `[ ]` todo · `[x]` done · `[!]` blocked (see progress.md)
Order = priority. Loop always takes the first `[ ]`.

## P0 — Production up (Vercel → Render → Render Postgres)
- [x] Build script defaults/forces API to https://my-purchases-api.onrender.com; CI dead-host guard flipped (commit "fix(deploy): point web build at Render API")
- [ ] Verify prod login works on desktop/tablet/mobile with QA account (Playwright `ralph/qa`), zero console errors on /login → /home
- [ ] Verify `/health/ready` shows `schema_ok: true` and alembic head = latest file in `backend/alembic/versions`. If not, add BLOCKED note "set AUTO_MIGRATE=1 on Render and redeploy latest main"
- [ ] Remove `render-keepalive.yml` pings if the Render plan is paid Starter (no sleep); keep `db-backup.yml`, verify it targets Render DB via GitHub secret only
- [ ] Grep repo + git history for leaked secrets (`sk-proj`, `ghp_`, `postgresql://`, `JWT_`). Remove from tree; BLOCKED note listing what to rotate

## P1 — Stock correctness (the #1 client complaint)
- [ ] Write backend integration tests (Postgres or sqlite runtime) for the full stock lifecycle: create confirmed purchase → mark arrived → verify → commit → stock +qty; edit committed purchase → diff applied; cancel/delete → reverted; physical count with same idempotency key twice → applied once; box/kg/piece unit conversion via `line_qty_in_stock_unit`
- [ ] ROOT CAUSE: `create_trade_purchase` returns `stock_updates=[]`; stock moves only after `commit_trade_purchase_delivery`. Add business setting `auto_commit_stock_on_confirm` (migration, default TRUE for this client). When TRUE, confirmed purchase create/update commits stock in the same transaction and returns real `stock_updates`. When FALSE, keep pipeline but show a clear "Pending stock: N purchases" banner on Stock + Purchase pages with one-tap "Add to stock"
- [ ] Frontend: every stock write (purchase save, quick stock sheet, physical count, damage report, delete/cancel purchase) goes through ONE path: optimistic patch → API → apply server `stock_updates` → single invalidation via `StockWriteCoordinator`. Remove the 5s deferred `stockListProvider` invalidation and duplicate invalidations in `quick_stock_action_sheet.dart`, `business_aggregates_invalidation.dart`, `stock_page.dart` listener
- [ ] Prod QA test: create `QA-RALPH-` purchase for a QA item → stock row updates within 2s without reload on all three viewports → cancel purchase → stock reverts → cleanup
- [ ] Partial delivery / partial edit: edit qty on one line of committed purchase, delete one line, add one line — stock diff correct (test + UI)
- [ ] Data audit (read-only SQL via backend script): list purchases `confirmed` but not `stock_committed` older than 1 day and stock rows whose on-hand ≠ sum of movements. Write findings to progress.md; do NOT auto-fix data — add a `[ ]` task with exact repair SQL for human review

## P2 — Performance & lag
- [ ] Measure: Render request logs p50/p95 per route for 24h; Playwright trace of login→home, stock list, purchase entry on mobile viewport. Record numbers in progress.md
- [ ] Backend: find N+1 queries in `routers/stock/stock_list.py`, `routers/catalog.py`, `reports_trade.py` (enable SQL echo in a test); fix with joins/selectinload; add missing indexes via migration; ensure list endpoints are paginated (limit/cursor)
- [ ] DB pool: Render Starter Postgres connection limit vs `DATABASE_POOL_SIZE=10 + MAX_OVERFLOW=15` — set to fit, avoid connection exhaustion
- [ ] Flutter web: check `main.dart.js` size; use deferred imports for barcode PDF, bulk print, reports, settings/backup pages; remove unused packages from pubspec
- [ ] Remove polling storms: `shell_tab_auto_refresh_listener` + realtime listener must not both refetch the same provider; one source of truth for refresh
- [ ] Re-measure; target: stock list < 1.5s p95 API, first interactive on mobile < 4s on cached load

## P3 — UI/UX clean-up (desktop 1440, tablet 820, mobile 390)
- [ ] Playwright screenshot every route at 3 viewports into `ralph/qa/shots/`; list layout bugs (overflow, clipped cells, wrong scroll container, sticky bars covering inputs, misplaced buttons) as tasks below
- [ ] Split `purchase_item_entry_sheet.dart` (4.7k lines), `purchase_entry_wizard.dart` (3.3k), `purchase_home_page.dart` (3.2k) into widgets ≤ 400 lines each, no behaviour change, tests green
- [ ] Purchase entry flow: minimum steps (party → items → review → save), keyboard-first on desktop (Tally style), one scroll container per screen on mobile, save button never hidden by keyboard
- [ ] Stock page: table cells/boxes aligned, numbers right-aligned, units consistent, no layout jump on update
- [ ] Remove pages/menus not used by the client workflow (confirm via router + nav usage); put rarely used ones under Settings
- [ ] Consistent design tokens (spacing, type scale, colors) from DESIGN.md; remove decorative gradients/emoji/shadows-on-everything
- [ ] Accessibility pass: tap targets ≥ 44px, contrast AA, focus order on desktop forms

## P4 — Dead code & repo hygiene
- [ ] Flutter: `dart fix --apply`; remove unused files/providers/routes (find files with zero imports)
- [ ] Backend: `vulture backend/app --min-confidence 80`; remove dead routes/services and `sqlite_bootstrap` paths if sqlite runtime unused in prod/tests
- [ ] Move `FINDINGS_*.md`, old `uiux context/` to `docs/archive/`; keep README, AGENTS.md, DESIGN.md, DEPLOYMENT.md, ralph/
- [ ] Add `CLAUDE.md` (≤ 40 lines) pointing to AGENTS.md + ralph/PROMPT.md for token-cheap context

## P5 — AI agent assistant (in-app, text + voice, Malayalam/English)
- [ ] Backend `app/agent/`: tool-calling agent over EXISTING services only (no duplicate business logic). Tools: search_items, get_stock(item), list_low_stock, search_suppliers, create_purchase_draft, add_line_to_draft, get_purchase(s), purchase_summary(period), supplier_ledger, commit_stock(purchase). Provider abstraction (Gemini default, OpenAI/Claude optional) using existing `AI_PROVIDER`/`ENABLE_AI` env; log to `ai_usage_logs`
- [ ] Slot-filling: agent asks follow-up questions for missing required fields (supplier, item, qty, unit, rate), shows the filled draft card, and saves ONLY after explicit user confirm
- [ ] Flutter assistant panel (bottom sheet mobile, side pane desktop): chat + mic button; streaming replies; draft card with Edit/Confirm
- [ ] Voice mode: Gemini Live API (audio in/out) via backend-issued ephemeral token; Malayalam (ml-IN) + English, mixed Manglish input; push-to-talk and hands-free modes; verify Malayalam voice support on the chosen model before building
- [ ] Prod QA: text script "Ravi traders-il ninnu 10 bag sugar 1450 rate" → draft filled correctly → confirm → purchase saved → stock updated → cleanup

## P6 — Remote MCP server (Claude, ChatGPT, Gemini)
- [ ] Mount MCP server (Streamable HTTP) at `/mcp` in FastAPI exposing the same agent tools; per-user auth (OAuth 2.1 or per-user API token from Settings), business scoping enforced server-side, write tools require `confirm=true`
- [ ] Settings page: generate/revoke MCP token, copy connector URL, short setup steps for Claude (custom connector), ChatGPT (connectors / developer mode), Gemini (Gemini CLI / supported Gemini surfaces)
- [ ] Test with MCP Inspector against prod; read-only tools first, then write tools

## P7 — WhatsApp
- [ ] Meta WhatsApp Cloud API webhook → same agent; reports (daily purchase summary, low stock) sent on schedule; use existing `whatsapp_delivery_logs` table; owner opt-in per number
- [ ] Voice notes from WhatsApp → transcribe (Malayalam) → agent → confirm via reply button before save

## P8 — Later: client server migration (only after P0–P3 stable)
- [ ] Runbook to move backend+DB from Render to client Windows Server (Docker or NSSM) + Cloudflare Tunnel; pg_dump/restore; cut over by changing Vercel `API_BASE_URL` only
