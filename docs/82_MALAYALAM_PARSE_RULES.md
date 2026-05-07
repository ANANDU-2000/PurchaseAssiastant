# 82 — MALAYALAM_PARSE_RULES

## Goal
Support Malayalam + Manglish mixed notes without corrupting names.

## Normalization strategy
- Preserve Malayalam Unicode when present.
- Apply conservative Manglish keyword normalization for common items.

## Current mapping
- `MALAYALAM_TO_ENGLISH` + `normalize_item_name(...)`:
  - `backend/app/services/ocr_parser.py`

## Future improvements
- Add Malayalam OCR-specific cleanup (common OCR confusions).
- Add supplier/broker name normalization without destructive transliteration.

