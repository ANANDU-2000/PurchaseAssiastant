# 74 — SUPPLIER_MATCHING

## Goal
Fuzzy match scanned supplier/broker/item names to existing business data and offer “Did you mean?” candidates.

## Backend
- Matcher module: `backend/app/services/scanner_v2/matcher.py`
- Used by:
  - v2: `backend/app/services/scanner_v2/pipeline.py` (`_match_supplier_broker`, `_match_items`)
  - v3: `backend/app/services/scanner_v3/pipeline.py` (same matching helpers)

## Wire format
- `ScanResult.supplier` and `.broker` are `Match` objects:
  - `raw_text`, `matched_id`, `matched_name`, `confidence`, `match_state`, `candidates[]`
  - `backend/app/services/scanner_v2/types.py`

## UX rules
- If `match_state != "auto"`, highlight the field and require review, but **never block** purchase creation after manual correction.

