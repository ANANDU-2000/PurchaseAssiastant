# API Audit — Phase 6: Reports

**Date:** 2026-07-28  
**Router:** `backend/app/routers/reports_trade.py` (+ `report_views.py`)

## Prod evidence

- No `HTTP 5xx` on `/reports/*` request logs in sampled window (20–28 Jul)
- `home-overview` often `SLOW_HTTP` / `VERY_SLOW_HTTP` (~3s cold) — **200** after isce fix
- `report_views` mutations already `commit()`

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| REPORTS-C1 | Critical | `GET …/reports/item/{id}` used `StockPhysicalCount.qty` (missing) → AttributeError → 500 `REPORTS_ITEM_FAILED` | **Fixed** → `counted_qty` |
| REPORTS-H1 | High | `trade-suppliers` / snapshot suppliers `avg_landing` always `0.0` | **Fixed** → money÷qty |
| REPORTS-H2 | High | `trade-items` `supplier_id` / `category_id` / `subcategory_id` ignored or post-filtered on missing field | **Fixed** → SQL filters |
| REPORTS-H3 | High | Item bundle `rate_avg` used `AVG(landing_cost)` | **Fixed** → money÷qty |
| REPORTS-M1 | Medium | `home-overview` ~3s cold | Track (perf) |
| REPORTS-M2 | Medium | Legacy tests hit `GET …/dashboard` → 404 (route removed) | **Fixed** |
| REPORTS-L1 | Low | Categories/types hardcode `total_profit: 0` | **Fixed** (line profit expr) |

## Tests

- Extended `backend/tests/test_reports_trade_breakdowns.py` (filters, rate_avg, supplier avg_landing)

## Open Critical

**None** for Reports after this pass.

## Next

Notifications → Users → Warehouse/Ops → Exports → rest.
