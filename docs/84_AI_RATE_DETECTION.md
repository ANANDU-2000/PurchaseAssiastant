# 84 — AI_RATE_DETECTION

## Goal
Infer rate semantics from shorthand while keeping ambiguity reviewable:
- `57 58` → purchase_rate=57, selling_rate=58
- `P57 S58` → purchase_rate=57, selling_rate=58

## Current implementation
- LLM prompt rule:
  - `backend/app/services/scanner_v2/prompt.py` (first rate or `P` → purchase, second or `S` → selling)
- Deterministic fallback (v3):
  - `backend/app/services/scanner_v3/pipeline.py` (`_fallback_parse_text`)

## Next improvements
- Rate mode inference for BAG (₹/kg vs ₹/bag) using:
  - presence of `weight_per_unit_kg`
  - typical price ranges for the matched catalog item (future)

