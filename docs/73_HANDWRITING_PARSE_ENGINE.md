# 73 — HANDWRITING_PARSE_ENGINE

## Goal
Parse common trader shorthand reliably even when the LLM parse fails.

## Supported patterns (baseline)
- `57 58` → purchase_rate=57, selling_rate=58
- `P56 S57` → purchase_rate=56, selling_rate=57
- `del 56` / `delivered 56` → delivered_rate=56
- `7 days` / `payment 7` → payment_days=7
- `Sugar 50kg` → bag item with `weight_per_unit_kg=50`
- `100 bag` / `100 bags` → bags=100

## Backend fallback parser (v3)
- Location: `backend/app/services/scanner_v3/pipeline.py`
- Function: `_fallback_parse_text(text)`
- Trigger: runs on **every** scan to fill gaps — if the LLM returns `{}` / empty `items`, fallback rows and missing `supplier_name` / `charges` / `payment_days` are merged in.
- Also understands lines like `Supplier: Surag`, `Broker: kkk`, `Purchase rate: 57`, `Payment days: 7`.

## LLM prompt constraints (v2 parser)
- Prompt SSOT: `backend/app/services/scanner_v2/prompt.py`
- Hard rule: **never invent values**; unknowns must be `null`.

