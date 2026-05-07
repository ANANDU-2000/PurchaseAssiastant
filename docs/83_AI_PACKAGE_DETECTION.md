# 83 — AI_PACKAGE_DETECTION

## Goal
Detect package kind from text and apply wholesale rules:
- Sugar 50kg → `BAG`, weight_per_unit_kg=50
- Ruchi Tin → `TIN`
- Sunrich 400gm box → `BOX`

## Backend SSOT
- Prompt rules (LLM):
  - `backend/app/services/scanner_v2/prompt.py`
- Deterministic unit detection + normalization:
  - `backend/app/services/scanner_v2/bag_logic.py`

## Display + totals
- BAG contributes to total kg (bags × kg-per-bag).
- BOX/TIN are count-only.

