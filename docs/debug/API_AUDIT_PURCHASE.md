# API Audit — Phase 4: Purchase (trade-purchases)

**Date:** 2026-07-28

## Prod evidence

- `GET …/trade-purchases` → **200** (often `SLOW_HTTP` ~1.7s)
- No `trade-purchases` HTTP 500 in sampled window (stock bundle 500s were the noise in the same log query)
- No `asyncio.gather` in `trade_purchases.py`

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| PURCHASE-M1 | Medium | Slow list (~1.7s) | Track (perf / indexes) |
| PURCHASE-L1 | Low | Duplicate parallel list fetches from client | Track |

## Open Critical

**None** found in this pass for Purchase list/read path.

## Next

Supplier/Contacts domain.
