# API Audit — Phase 11: Utilities / Public

**Date:** 2026-07-28  
**Routers:** `public_items.py`, `search.py`, `media.py`, health

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| PUB-C1 | Critical | Unauth `/public/items` JSON/lookup exposed purchase rates + supplier | **Fixed** — stock/location only |
| UTIL-M1 | Medium | Health DB error `str(e)` to client | Track |
| UTIL-M2 | Medium | Search still returns supplier/broker phones to staff | Track |

## Cleared

Public rate limit 60/min/IP; search/media membership-scoped; no gather isce; no public seed route.

## Open Critical

**None** for Utilities/Public after this pass.

## Audit queue

Phases Auth → … → Public Critical/High closed (AUTH-H2/H3 still blocked on approval).
