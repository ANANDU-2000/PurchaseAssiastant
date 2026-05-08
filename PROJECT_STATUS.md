# PROJECT STATUS — Purchase Assistant

High-level snapshot. Detailed priorities: `TRACK.md`. Task checklist: `TASKS.md`.

## Completed (recent)

- Purchase scan → **draft wizard** route (`/purchase/scan-draft`); no instant confirm from scan-only screen.
- Docs: `docs/AI_PURCHASE_DRAFT_ENGINE.md`, validation/safety, Scan Guide UX spec (see `docs/`).
- **Cursor policies:** full verbatim `context/rules/MASTER_CURSOR_RULES.md` + `AUTONOMOUS_CURSOR_EXECUTION_RULES.md` (not summaries). `TASKS.md` uses Critical / In progress / Pending / Completed / Blocked.

## In progress / current focus

- Match engine hardening (unit/pack-size guards, alias + fuzzy + supplier history).
- Item edit autocomplete wired to catalog/history APIs.
- Report/dashboard single-source aggregation parity (see `REPORT_ENGINE.md`).

## Pending / backlog

- Multi-image bill merge; Malayalam/Manglish normalization dictionary service.
- Field-level confidence + forced review on unit mismatch.
- Delete flow audit (server soft-delete vs cache vs list refetch) — see `BUGS.md`.

## Blockers

- _(none filed — add here when work stops on external dependency.)_

## Architecture (short)

- Flutter → FastAPI → Postgres; scan JSON cached by `scan_token` until confirm creates `trade_purchase` (see backend routers/services).
