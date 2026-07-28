# API Audit — Phase 2: Home / Dashboard

**Date:** 2026-07-28  
**Mode:** Audit only for Critical; Home isce already fixed (`772bdc0`).

## Endpoints in scope

| Method | Path | Frontend | Prod evidence | Status |
|--------|------|----------|---------------|--------|
| GET | `/v1/businesses/{id}/reports/home-overview` | `home_dashboard_provider` / `HexaApi` (`shell_bundle=true`) | 200/304; SLOW ~600ms | COMPLETED (isce fixed) |
| GET | `/v1/businesses/{id}/reports/trade-dashboard-snapshot` | Reports / shared compute | Covered by same sequential path | COMPLETED |
| GET | `/health` / `/health/ready` | Warmup | ok | COMPLETED |

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| HOME-C1 | Critical | Shared-session gather on snapshot + home_operational | **Fixed** `772bdc0` |
| HOME-M1 | Medium | `SLOW_HTTP` ~500–900ms on shell_bundle | Track; not a 500 |
| HOME-M2 | Medium | shell_bundle cache leaked per-user unread across users | **Fixed** |
| HOME-M3 | Medium | Home unread ignored `target_roles` | **Fixed** |
| HOME-L1 | Low | Frequent refresh / ETag 304 storms | Track (client cache) |

## Critical open

**None** for Home/Dashboard.

## Next domain

Stock — remaining endpoints beyond bundle/shell-bundle/barcode (already COMPLETED for isce).
