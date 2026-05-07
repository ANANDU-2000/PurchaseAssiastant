# 93 — AI_SEMANTIC_PARSE

## Goal

Do not depend on OCR text alone. Use an AI semantic pass to interpret trader language and produce a structured preview.

## Requirements

- Understand wholesale trader shorthand:
  - `Sugar 50kg` → item “Sugar”, package 50kg, likely unit bag
  - `100 bag` → qty 100, unit bag
  - `57 58` → purchase/selling rates
  - `Delivered rate 56` → delivered/landed rate
  - `Payment days 7` → payment_days=7
- Handle Malayalam / Manglish (see `docs/108_MALAYALAM_HANDLING.md`)

## Backend implementation

- LLM parse entrypoint (shared with v2):
  - `backend/app/services/scanner_v2/pipeline.py::_openai_parse_scanner_payload`
- v3 merges LLM dict with deterministic fallback:
  - `backend/app/services/scanner_v3/pipeline.py`

## Merge policy (LLM + fallback)

- If LLM returns `None` → use fallback output
- If LLM returns empty items → merge fallback items
- If LLM misses supplier/broker/payment/charges → fill from fallback
- Never discard partial structured output

