# 77 — PARTIAL_PARSE_MODE

## Goal
If the scan is only partially successful (e.g. 60%), still show the preview and allow manual correction.

## Backend behavior (v2/v3)
- v2: `backend/app/services/scanner_v2/pipeline.py` returns `ScanResult` with typed `scan_meta.error_*` on failures.
- v3: `backend/app/services/scanner_v3/pipeline.py`
  - OCR empty → `OCR_EMPTY` but still returns a reviewable `ScanResult`
  - LLM parse empty → `PARSE_EMPTY` and uses deterministic fallback when possible

## UI rules
- Never discard the scan result.
- Highlight low-confidence fields, but **do not block** “Create Purchase”.

