# Low Stock Operations — Enterprise Rebuild

**Status:** Shipped (May 2026)  
**Routes:** `/stock/low-stock` (owner), `/staff/low-stock` (staff)

## Purpose

Replace the legacy category-grouped low-stock list with a priority-sorted **operations command center**: KPI header, filter chips, compact rows, owner approval for verification, and desktop three-panel layout.

## Backend

| Endpoint | Role |
|----------|------|
| `GET /v1/businesses/{id}/stock/low-stock/summary` | Header KPIs |
| `GET /v1/businesses/{id}/stock/low-stock/operations` | Paginated ops list |

Enrichment (`low_stock_ops_enrichment.py`, `low_stock_priority.py`):

- `priority_score`, `priority_band`
- `lifecycle_stage` (out, ordered, delayed, disputed, verification, reorder_*)
- `reorder_entry_status` from `reorder_list`
- `has_open_dispute` from `stock_dispute_cases` (migration `039`)
- Disputed filter: mismatch, open dispute, rejected audit line, or physical diff

Notifications: `stock_mismatch`, `supplier_delayed` deep-link to `?filter=disputed|delayed`.

## Flutter

- `LowStockOperationsPage` — summary + ops providers, debounced search, deep links `?filter=` / `?q=`
- Widgets: header, filter bar (incl. bulk mode), category groups, `LowStockItemExpanded` + lifecycle strip, desktop shell + context panel
- Owner: approval sheet via `GET stock-audits/pending-lines` + approve line API

## Verification

```bash
cd backend && pytest tests/test_low_stock_priority.py tests/test_low_stock_operations.py -q
cd flutter_app && flutter analyze
cd flutter_app && flutter test test/low_stock_snapshot_row_test.dart
```

## Tracker

See `TASKS.md` → **LOW-STOCK-REBUILD**.
