# Production readiness audit (automated + manual)

This document is the deliverable for the “strict audit” to-do. **Do not infer readiness from code alone**; run manual checks in staging and record scores.

## Readiness scale

| Score   | Meaning                          |
|--------|-----------------------------------|
| 0–40%  | Broken / unusable                 |
| 40–70% | Demo-quality                      |
| 70–85% | Soft production (single user)     |
| 85–100%| Stable product                    |

**Ready (soft+):** same numbers for the same `from` / `to` and report-status rules across home snapshot, `trade-summary`, and breakdowns; core flows work; errors visible.

---

## What was fixed / added in this pass (verification)

| Item | Where | Notes |
|------|--------|--------|
| `trade-summary` line-aligned | [reports_trade.py](../backend/app/routers/reports_trade.py) `trade_purchase_summary` | Totals = sum of `trade_line_amount_expr()` over lines + `TRADE_STATUS_IN_REPORTS` + date/supplier filter. Matches [trade-dashboard-snapshot] summary. |
| AI context includes trade MTD | [assistant_business_context.py](../backend/app/services/assistant_business_context.py) | Appends trade MTD (same line rules as reports) after legacy Entry block. |
| Automated E2E (API) | [test_production_readiness_e2e.py](../backend/tests/test_production_readiness_e2e.py) | Create → summary vs snapshot → update → delete → zero; separate cancel test. |
| Supplier history hint (UX) | [purchase_entry_wizard_v2.dart](../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart) | Hint moved to **Items** step (with supplier step no longer duplicating). |

---

## Check 1 — User flow (file map)

| Flow | Flutter | Backend |
|------|---------|---------|
| Create item | Catalog routes + `hexa_api` | [catalog.py](../backend/app/routers/catalog.py) |
| Create / edit / delete / cancel purchase | [purchase_entry_wizard_v2.dart](../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart), [purchase_home_page.dart](../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart), [hexa_api.dart](../flutter_app/lib/core/api/hexa_api.dart) | [trade_purchases.py](../backend/app/routers/trade_purchases.py), [trade_purchase_service.py](../backend/app/services/trade_purchase_service.py) |

---

## Check 2 — Data consistency (dashboard vs reports)

- Home: [home_dashboard_provider.dart](../flutter_app/lib/features/home/state/home_dashboard_provider.dart) — `tradeDashboardSnapshot`.
- KPI / PDF headline: [analytics_kpi_provider.dart](../flutter_app/lib/core/providers/analytics_kpi_provider.dart) — `tradePurchaseSummary` → now **line-based**; should match snapshot **summary** for the same `from`/`to`.
- **Manual spot-check:** for one day range, compare `summary.total_purchase` from snapshot response to `GET /reports/trade-summary` (same query params).

---

## Check 3 — UI/UX (manual)

| Area | Look for |
|------|----------|
| [home_page.dart](../flutter_app/lib/features/home/presentation/home_page.dart) | `AsyncValue` loading vs error, refresh invalidates `homeDashboardDataProvider` |
| [full_reports_page.dart](../flutter_app/lib/features/analytics/presentation/full_reports_page.dart) | Preset range vs analytics providers |
| [purchase_entry_wizard_v2.dart](../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart) | Long form: scroll, supplier validation messages |

**Verified in code (not a visual test):** supplier trade-history hint is on the Items step; **all** distinct non-empty `catalogItemId` values on lines are used — top suppliers are ranked by **aggregated `deals`** over matching map rows.

---

## Check 4 — API surface (high level)

- Reports trade routes: [reports_trade.py](../backend/app/routers/reports_trade.py) — membership + DB; `from`/`to` required for most breakdowns; `trade-summary` allows optional dates.
- Grep: no remaining `TradePurchase.status.in_(("saved", "confirmed"))` for analytics in catalog (aligned to [trade_query.py](../backend/app/services/trade_query.py)).

---

## Check 5 — Error handling

- [trade_purchase_service.py](../backend/app/services/trade_purchase_service.py): `ValueError` on create/update (empty lines, bad qty, confirmed without supplier, etc.) — **confirm** router maps to 422/400 in [trade_purchases.py](../backend/app/routers/trade_purchases.py) (covered in existing tests).
- Flutter: [fastapi_error.dart](../flutter_app/lib/core/api/fastapi_error.dart) — used where API calls throw.

---

## Check 6 — Relationships

- Mapping: [trade_mapping.py](../backend/app/services/trade_mapping.py) — groups by `catalog_item_id`, `supplier_id`, `broker_id`.
- Lines must reference `catalog_item_id` where schema requires it (see [test_trade_purchases.py](../backend/tests/test_trade_purchases.py) strict line tests).

---

## Check 7 — Report engine

- Single line value: [trade_query.py](../backend/app/services/trade_query.py) `trade_line_amount_expr`, `TRADE_STATUS_IN_REPORTS`, `trade_purchase_date_filter`.
- `trade_purchase_summary` and snapshot both use line sums (this pass).

---

## Check 8 — Performance (runbook, manual)

- Home: one `FutureProvider` load per visit; `ref.invalidate(homeDashboardDataProvider)` on pull-to-refresh in [home_page.dart](../flutter_app/lib/features/home/presentation/home_page.dart).
- **Device:** connect a real low-end phone (or profile build with DevTools) and:
  1. Open **Home** — note time to first stable frame; in DevTools log **Network** count for `trade-dashboard-snapshot` (should be 1 per cold open).
  2. Enable **throttling** (e.g. Slow 3G) or OS network limiter; repeat open **Reports** and **Purchases** — note cold vs warm navigation; **no** full app reload is acceptable for tab switches.
  3. **Performance** overlay or DevTools: scroll purchase list and reports table; no sustained jank over 100 ms is the bar for a strict gate (record p95 in notes).
- If these steps are not run, **performance must stay “unverified”** in the final gate; do not claim production readiness for slow devices.

---

## Check 9 — PDF vs API

- Reports PDF: [full_reports_page.dart](../flutter_app/lib/features/analytics/presentation/full_reports_page.dart) → `analyticsKpiProvider` (trade summary) + item/category/supplier tables from [analytics_breakdown_providers.dart](../flutter_app/lib/core/providers/analytics_breakdown_providers.dart) (trade report endpoints). Headline `totalPurchase` on PDF [reports_pdf.dart](../flutter_app/lib/core/services/reports_pdf.dart) should match `tradePurchaseSummary` after this alignment.
- Purchase PDF: [purchase_pdf.dart](../flutter_app/lib/core/services/purchase_pdf.dart) — uses header `p.totalAmount`; in-app and PDF now include a short **footnote** on how this differs from Reports “Spend” (line-sum over a range). Compare detail screen total to PDF **header**; do not expect it to match line-only `trade-summary` for the same dates without adjustment.

---

## Client / server line validation (UX)

Saves are **confirmed** in the app; [purchase_draft.dart](../flutter_app/lib/features/purchase/domain/purchase_draft.dart) `purchaseLineSaveBlockReason` mirrors the server’s per-line rules ([trade_purchase_service.py](../backend/app/services/trade_purchase_service.py) `create_trade_purchase` / `update_trade_purchase`). [purchase_draft_provider.dart](../flutter_app/lib/features/purchase/state/purchase_draft_provider.dart) `purchaseStepGatesProvider` and `purchaseSaveValidationProvider` block **Next** and save when a line is invalid. Item sheet: keep inline validation aligned when adding new fields.

---

## Issue register (strict audit)

| ID | Issue | Severity | Root cause | Fix (done or follow-up) | How verified |
|----|--------|----------|------------|-------------------------|--------------|
| A1 | AI only saw legacy Entry MTD | Critical | [assistant_business_context.py](../backend/app/services/assistant_business_context.py) | **Fixed:** TRADE block first; legacy block only if Entry MTD has activity; [REPORT_SYSTEM_PROMPT](../backend/app/services/assistant_system_prompt.py) + [llm_intent.py](../backend/app/services/llm_intent.py) tell the model to prefer TRADE for wholesale. | Read files; spot-check in staging. |
| A2 | `trade-summary` used header `total_amount` | High | Historical endpoint design | **Fixed:** line-based aggregation. | [test_production_readiness_e2e.py](../backend/tests/test_production_readiness_e2e.py) |
| A3 | Supplier hint on wrong step | Medium | First step has no lines | **Fixed:** hint on Items step. | Manual wizard pass |
| A4 | `trade-suppliers` used header totals | Medium | [reports_trade.py](../backend/app/routers/reports_trade.py) `trade_suppliers_breakdown` | **Fixed:** line sums + qty from lines. | [test_reports_trade_breakdowns.py](../backend/tests/test_reports_trade_breakdowns.py) (supplier assert still >0) |
| A5 | Full-screen / perf on slow network | Unknown until measured | — | **Checklist:** Check 8 runbook. | Device + throttled network |
| A6 | Purchase PDF total vs line-derived dashboard | Product clarity | PDF uses header total; reports use line sum | In-app + PDF **footnotes** on scope (detail, reports KPI, [purchase_pdf.dart](../flutter_app/lib/core/services/purchase_pdf.dart), [reports_pdf.dart](../flutter_app/lib/core/services/reports_pdf.dart)). | Read labels on screen/PDF |

---

## Manual E2D checklist (staging)

Run after deploying backend + Flutter; fill dates and numbers in a sheet.

- [ ] FLOW 1: create item → purchase → history item dashboard reports match (see automated test + UI).
- [ ] FLOW 2: edit qty → all surfaces update (invalidate lists).
- [ ] FLOW 3: delete → gone from reports; cancel → excluded from line reports.
- [ ] Date chips on home match analytics date math (inclusive end).
- [ ] Mark paid / due — status and filters.
- [ ] PDF export: headline matches KPI row on screen for same range.

**Suggested readiness score:** record here after the above: ___ %

---

## Automated tests to run in CI

```bash
cd backend
pytest -q tests/test_production_readiness_e2e.py tests/test_reports_trade_breakdowns.py
```

---

## API reconciliation (same `from`/`to`)

[test_production_readiness_e2e.py](../backend/tests/test_production_readiness_e2e.py) asserts: `trade-summary` = snapshot `summary`; sum of `trade-items` `total_purchase` = same; sum of `trade-suppliers` `total_purchase` = same. This automates the “manual same dates” cross-check for the **backend**.

## PDF spot check (manual)

- **Reports:** KPI headline comes from [analytics_kpi_provider.dart](../flutter_app/lib/core/providers/analytics_kpi_provider.dart) (`tradePurchaseSummary`) and table rows from `tradeReportItems` for the same [`analyticsDateRangeProvider`](../flutter_app/lib/core/providers/analytics_kpi_provider.dart) window — line totals should match if the table is unfiltered. Export PDF and compare the printed headline to the on-screen “Spend” pill.
- **Purchase PDF:** [purchase_pdf.dart](../flutter_app/lib/core/services/purchase_pdf.dart) uses the purchase’s stored header total; compare to detail screen’s total, not to line-sum dashboard.

---

*Last updated: final audit pass — trade-first AI, supplier+item sum tests, prompt updates, DevTools/PDF checklists.*
