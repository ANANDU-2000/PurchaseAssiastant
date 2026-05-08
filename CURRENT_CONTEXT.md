# CURRENT CONTEXT

_Update this file after each meaningful agent session._

## Last updated

- Date: 2026-05-08  
- Branch: `main` (verify with `git branch`)

## Active task

- **Reports parity:** `GET /dashboard?month=` and **`GET /analytics/insights/trade`** use `trade_purchase_status_in_reports()` — soft-deleted purchases excluded from month KPIs and insight rankings.
- **Next:** supplier-scoped search params, any remaining chart/home consumers audit (`TASKS.md`).

## Why assistants pause between messages

- Cursor turns are **bounded**; your AUTONOMOUS doc’s **full checklist** is implemented as **successive commits** (this session added autocomplete). Remaining items are **explicit backlog rows**, not ignored.

## Important business rules (short)

- Scan → **draft** only; final purchase after wizard confirm + backend totals.
- No guessing matches; unit mismatch → force review.
- Reports must share one backend aggregation contract.

## Current screens / flows

- **Scan:** `ScanPurchaseV2Page` → **Draft wizard:** `PurchaseScanDraftWizardPage` (`/purchase/scan-draft`) → confirm → `scanPurchaseBillV2Update` + `scanPurchaseBillV2Confirm`.

## Latest code touchpoints

- `backend/app/routers/dashboard.py` — month KPI status filter
- `backend/app/routers/analytics.py` — `/insights/trade` status filter
- `flutter_app/lib/features/purchase/providers/trade_purchase_detail_provider.dart` — shared detail cache; invalidated on all delete paths
- `backend/tests/test_reports_trade_breakdowns.py` — dashboard + analytics delete regressions
- `flutter_app/lib/features/purchase/presentation/scan_draft_edit_item_sheet.dart` (unified search autocomplete)
- `backend/app/services/scanner_v2/pack_gate.py`, `backend/app/services/scanner_v2/pipeline.py`
- `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`
- `flutter_app/lib/features/purchase/presentation/purchase_scan_draft_wizard_page.dart`

## Blockers

- None recorded.

## Pending validation

- `pytest tests/test_reports_trade_breakdowns.py::test_month_dashboard_*` + `::test_analytics_trade_insights_excludes_deleted`
- Full `pytest` / `flutter test` before release.

