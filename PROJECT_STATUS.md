# PROJECT STATUS — Purchase Assistant

High-level snapshot. Detailed priorities: `TRACK.md`. Task checklist: `TASKS.md`.

## Completed (recent)

- Purchase scan → **`PurchaseEntryWizardV2`** at `/purchase/new` (mapper from scan JSON + `scan_token` in route extra); `/purchase/scan-draft` is a legacy redirect only.
- Wizard-embedded **`PurchaseBillScanPanel`** (legacy multipart scan): item lines use the **same** debounced **`GET /search`** suggestions + optional `supplier_id` when supplier is directory-linked; picks persist **`catalog_item_id`** on `PurchaseDraft` lines (aligned with AI scan v2 preview sheet).
- Docs: `docs/AI_PURCHASE_DRAFT_ENGINE.md`, validation/safety, Scan Guide UX spec (see `docs/`).
- **Cursor policies:** full verbatim `context/rules/MASTER_CURSOR_RULES.md` + `AUTONOMOUS_CURSOR_EXECUTION_RULES.md` (not summaries). `TASKS.md` uses Critical / In progress / Pending / Completed / Blocked. Tracker maintenance: `CURRENT_CONTEXT.md`, `BUGS.md`, `SCAN_ENGINE.md`, `MATCH_ENGINE.md`, `REPORT_ENGINE.md` updated with scan→wizard reality.

## In progress / current focus

- Match engine: **pack gate** + ranking follow-ups (aliases, pg_trgm — see `TASKS.md`).
- Report/dashboard aggregation: **month `GET /dashboard`** aligned with trade reports; Flutter **`invalidateBusinessAggregates`** clears Hive + inflight dedupe maps and discards stale home-overview fetches (bust generation).

## Pending / backlog

- Multi-image bill merge; Malayalam/Manglish normalization dictionary service.
- Field-level confidence + forced review on unit mismatch.
- Shell/report `FutureProvider` paths: optional generation guard (Hive + inflight clear already on aggregate invalidation).

## Blockers

- _(none filed — add here when work stops on external dependency.)_

## Architecture (short)

- Flutter → FastAPI → Postgres; scan JSON cached by `scan_token` until confirm creates `trade_purchase` (see backend routers/services).
