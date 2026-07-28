# API Audit — Phase 10: Exports

**Date:** 2026-07-28  
**Router:** `backend/app/routers/exports.py` (+ `export_files.py`)

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| EXP-H1 | High | Backup ZIP built up to 5000 in-memory order PDFs (OOM/DoS) | **Fixed** — count gate + cap **400** → `413` |
| EXP-M1 | Medium | Unbounded catalog rows in stock xlsx / JSON backup | Track |
| EXP-M2 | Medium | Staff with `export_access` override see purchase totals | Track (perm intentional) |

## Cleared

Auth via `export_access`; IDOR scoped; cancelled/draft filtered; stock xlsx has no rates; no shared-session gather.

## Open Critical

**None** for Exports after this pass.
