# PROGRESS LOG (append-only)

Add a new entry **after significant merges or agent sessions**.

```text
## YYYY-MM-DD — <short title>
- Modules:
- Change summary:
- Validation: (e.g. flutter analyze, pytest, manual flows)
- Links: (PR, commit)
```

---

## 2026-05-08 — Flutter: bust trade purchase detail cache on every delete path

- Modules: `trade_purchase_detail_provider.dart`, `purchase_detail_page.dart`, `purchase_home_page.dart`, `trade_ledger_page.dart`, `broker_history_page.dart`, `item_history_page.dart`, `supplier_ledger_page.dart`, `BUGS.md`
- Change summary: Moved detail fetch to shared `tradePurchaseDetailProvider` (keepAlive); after successful API delete, `ref.invalidate(tradePurchaseDetailProvider(id))` from all screens that delete purchases so stale detail cannot reopen from cache.
- Validation: `dart analyze` on touched files — no issues.

---

## 2026-05-08 — Analytics trade insights exclude deleted (report status filter)

- Modules: `backend/app/routers/analytics.py`, `backend/tests/test_reports_trade_breakdowns.py`, `REPORT_ENGINE.md`
- Change summary: `GET /analytics/insights/trade` now uses `trade_purchase_status_in_reports()` instead of `status != cancelled`, matching trade aggregates (soft-deleted rows no longer affect best/worst item ranking).
- Validation: `pytest tests/test_reports_trade_breakdowns.py::test_analytics_trade_insights_excludes_deleted` — passed.

---

## 2026-05-08 — Dashboard month aggregates exclude deleted (parity with trade reports)

- Modules: `backend/app/routers/dashboard.py`, `backend/tests/test_reports_trade_breakdowns.py`, `REPORT_ENGINE.md`, `BUGS.md`, `PROJECT_STATUS.md`, `CURRENT_CONTEXT.md`
- Change summary: Replaced `status != "cancelled"` with `trade_purchase_status_in_reports()` so soft-deleted (`deleted`) and non-report statuses do not affect `GET /dashboard?month=` totals; aligns with trade-summary aggregation contract.
- Validation: `pytest tests/test_reports_trade_breakdowns.py::test_month_dashboard_excludes_deleted_matches_trade_summary tests/test_reports_trade_breakdowns.py::test_month_dashboard_uses_line_total_source_of_truth` — passed.

---

## 2026-05-08 — Flutter scan draft item autocomplete (unified search)

- Modules: `scan_draft_edit_item_sheet.dart`, `scan_purchase_v2_page.dart`, `purchase_scan_draft_wizard_page.dart`, `MATCH_ENGINE.md`, `BUGS.md`, `TASKS.md`
- Change summary: Debounced `GET .../search` → `catalog_items` in draft item sheet; tap applies `matched_catalog_item_id`, optional last P/S from API row.
- Validation: `dart analyze lib/features/purchase/presentation/scan_draft_edit_item_sheet.dart` — no issues.

---

## 2026-05-08 — Scanner pack gate (kg hint + unit channel)

- Modules: `scanner_v2/pack_gate.py`, `scanner_v2/pipeline.py`, `tests/test_scan_pack_gate.py`, `MATCH_ENGINE.md`, `BUGS.md`, `TASKS.md`
- Change summary: After fuzzy catalog match, demote `auto` → `needs_confirmation` when line vs catalog pack kg diverge or BAG↔piece channel conflicts; batch-fetch catalog rows.
- Validation: `pytest tests/test_scan_pack_gate.py` (5 passed).

---

## 2026-05-08 — TASKS.md section order = Pending / In Progress / Completed / Blocked / Critical

- Modules: `TASKS.md`, `CURRENT_CONTEXT.md`
- Change summary: Align task file headings with `AUTONOMOUS_CURSOR_EXECUTION_RULES.md`; document why multi-hour ERP chains span sessions.
- Validation: markdown-only.

---

## 2026-05-08 — Verbatim MASTER + AUTONOMOUS policies + TASKS structure

- Modules: `context/rules/MASTER_CURSOR_RULES.md`, `context/rules/AUTONOMOUS_CURSOR_EXECUTION_RULES.md`, `TASKS.md`, `context/rules/TASKS.md` (pointer), `CURRENT_CONTEXT.md`
- Change summary: Replaced condensed policy text with user-provided full rule documents; TASKS.md now uses Pending/In Progress/Completed/Blocked/Critical structure.
- Validation: policy docs only (no code change).

---

## 2026-05-08 — Cursor ERP rules + draft wizard baseline

- Modules: `.cursor/rules/purchase-assistant-master.mdc`, `context/rules/MASTER_CURSOR_RULES.md`, `context/rules/AUTONOMOUS_CURSOR_EXECUTION_RULES.md`, repo trackers (`PROJECT_STATUS.md`, etc.), purchase draft wizard (prior commit on `main`).
- Change summary: Documented strict ERP/AI policies and mandatory trackers; wizard flow separates scan from final purchase create.
- Validation: Run `flutter analyze` / targeted tests when touching Dart; `pytest` when touching backend.
