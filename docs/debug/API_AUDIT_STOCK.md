# API Audit — Phase 3: Stock

**Date:** 2026-07-28

## Critical / High from production

| ID | Severity | Endpoint | Status |
|----|----------|----------|--------|
| STOCK-C1 | Critical | `GET …/stock/{id}/bundle` shared-session gather | **Fixed** `a52dd46` |
| STOCK-C2 | Critical | shell-bundle / barcode / warehouse alerts gather | **Fixed** `a52dd46` |
| STOCK-H1 | High | Slow `GET …/stock/{id}` (~1.8s+) | **Improved** (drop duplicate delivered scan) |
| STOCK-M1 | Medium | Parallel identical shell-bundle client calls | Track (client) |
| STOCK-M2 | Medium | Unit mismatch warnings pcs/box | Track (data quality) |
| STOCK-M3 | Medium | Recent purchases included deleted/cancelled | **Fixed** |

## Prod check (post-fix)

- No new `/stock/*` HTTP 500 in logs after `a52dd46` deploy window.
- Pre-fix 500s were exclusively `/bundle` isce.

## Flutter

- Desktop selection `ref.watch` fixed earlier (`fa23422`).
- Item detail depends on bundle (now sequential).

## Open Critical

**None** for Stock backend after isce pass.

## Next

Purchase (`trade-purchases`) domain audit.
