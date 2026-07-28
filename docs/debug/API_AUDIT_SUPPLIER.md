# API Audit — Phase 5: Supplier / Contacts

**Date:** 2026-07-28  
**Router:** `backend/app/routers/contacts.py`

## Prod evidence

- `GET …/suppliers?compact=true` → **200** (often `SLOW_HTTP` ~1–1.8s)
- No `HTTP 500` on `/suppliers*`, `/brokers*`, or `/contacts/*` in sampled request logs (20 Jul–28 Jul)
- No `asyncio.gather` in contacts router; mutations use `await db.commit()`

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| SUPPLIER-C1 | Critical | `DELETE /suppliers/{id}` / `DELETE /brokers/{id}` did not clear `broker_supplier_m2m` (no ON DELETE CASCADE) → IntegrityError / 500 when links exist | **Fixed** |
| SUPPLIER-H1 | High | `GET …/suppliers/{id}/metrics` used `AVG(landing_cost)` instead of line money ÷ qty | **Fixed** |
| SUPPLIER-H2 | High | `GET …/contacts/search` brokers skipped `_broker_out` (missing `supplier_ids` / `last_purchase_date`) | **Fixed** |
| SUPPLIER-M1 | Medium | Slow suppliers list (~1–1.8s compact) | Track (perf) |
| SUPPLIER-L1 | Low | Dead Flutter `hexa_api.analyticsSuppliers` / `analyticsBrokers` paths (unused; live UI uses trade snapshot) | Track |

Also clears `supplier_item_defaults` on supplier delete (same missing CASCADE class).

## Tests

`backend/tests/test_contacts_delete_links.py`

## Open Critical

**None** for Supplier/Contacts after this pass.

## Next

Reports domain audit.
