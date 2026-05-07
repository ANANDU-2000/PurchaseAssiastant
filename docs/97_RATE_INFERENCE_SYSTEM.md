# 97 — RATE_INFERENCE_SYSTEM

## Goal

Infer purchase/selling/delivered rates even from shorthand.

Examples:

- `57 58` → purchase=57, selling=58
- `P57 S58` → purchase=57, selling=58
- `del 56` / `delivered 56` → delivered_rate=56

## Backend sources

- LLM semantic parse (primary)
- Deterministic fallback parse (secondary):
  - `backend/app/services/scanner_v3/pipeline.py::_fallback_parse_text`

## Validation rules

- Rates are **optional** but should be inferred when present.
- If only one rate is found, do not fail; surface “rate needs confirmation”.

