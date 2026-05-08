# PROJECT STATUS — Purchase Assistant

High-level snapshot. Detailed priorities: `TRACK.md`. Task checklist: `TASKS.md`.

## Completed (recent)

- Purchase scan → **draft wizard** route (`/purchase/scan-draft`); no instant confirm from scan-only screen.
- Docs: `docs/AI_PURCHASE_DRAFT_ENGINE.md`, validation/safety, Scan Guide UX spec (see `docs/`).
- **Cursor policies:** full verbatim `context/rules/MASTER_CURSOR_RULES.md` + `AUTONOMOUS_CURSOR_EXECUTION_RULES.md` (not summaries). `TASKS.md` uses Critical / In progress / Pending / Completed / Blocked.

## In progress / current focus

- Match engine: **pack gate** + **draft item edit autocomplete** (unified search); next supplier-scoped queries.
- Item edit autocomplete wired to catalog/history APIs.
- Report/dashboard aggregation: **month `GET /dashboard`** aligned with trade reports; Flutter **`invalidateBusinessAggregates`** clears Hive + inflight dedupe maps and discards stale home-overview fetches (bust generation).

## Pending / backlog

- Multi-image bill merge; Malayalam/Manglish normalization dictionary service.
- Field-level confidence + forced review on unit mismatch.
- Shell/report `FutureProvider` paths: optional generation guard (Hive + inflight clear already on aggregate invalidation).

## Blockers

- _(none filed — add here when work stops on external dependency.)_

## Architecture (short)

- Flutter → FastAPI → Postgres; scan JSON cached by `scan_token` until confirm creates `trade_purchase` (see backend routers/services).
