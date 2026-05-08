# REPORT ENGINE — notes for agents

## Principle

**Single source of truth** for money and quantities: backend aggregates from persisted purchase lines (`purchase_items` / trade tables — confirm exact models in `backend/app/models/`).

Flutter/admin must **not** re-implement divergent sum logic for the same KPIs shown on dashboard vs detail vs analytics.

## Known risk areas

- Stale cache after create/update/delete (invalidate Riverpod providers / HTTP caches narrowly).
- Date-range boundaries (timezone, inclusive/exclusive).
- Deleted or voided purchases still included in aggregates — verify query filters.

## Code map

- Home/dashboard routers and services under `backend/app/routers/` and `backend/app/services/` (search `overview`, `dashboard`, `reports`).
- Flutter: home and reports feature folders — ensure they call the same endpoints as purchase detail.

## When changing aggregates

1. Identify all consumers (home, reports, exports).  
2. Change backend once; update clients to display returned fields only.  
3. Add regression test or parity check if possible.
