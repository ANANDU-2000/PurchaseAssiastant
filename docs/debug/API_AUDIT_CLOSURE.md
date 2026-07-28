# API Audit — Closure Board

**Date:** 2026-07-28  
**Status:** Critical/High closed; AUTH-H2/H3 closed via **safe product paths** (email/S3 still future work).

## Deferred (not bugs — need indexes / product later)

| ID | Note |
|----|------|
| PURCHASE-M1 / REPORTS-M1 / HOME-M1 / NOTIF-M1 | Cold latency — needs DB indexes / deeper profiling |
| AUTH-M1 | Refresh token rotation — larger auth redesign |
| STOCK-M2 | Unit mismatch data quality |
| EXP-M2 | Staff + export_access intentionally sees totals |
| AUTH-L* | Bootstrap polish / unused profile patch |

## Mitigated in app already

| ID | Mitigation |
|----|------------|
| STOCK-M1 | `stockShellBundleProvider` shared FutureProvider |
| PURCHASE-L1 | `fetchTradePurchasesPageDeduped` inflight map |
| HOME-L1 | Home overview ETag + memory snap |
| SUPPLIER-L1 | analytics suppliers/brokers still used by Reports UI |

## AUTH-H2 / AUTH-H3 product resolution

- **H2:** Prod forgot-password copy → owner Settings reset; `email_delivery: false`; tokens still stored for future email.
- **H3:** Prod logo upload without `S3_BUCKET` → `501` + use branding URL instead.
