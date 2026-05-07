# 107 — WHOLESALE_TRADE_PARSE_RULES

## Trader shorthand rules (minimum viable)

### Supplier / Broker

- If labeled (`Supplier:` / `Broker:`) → use directly
- Else:
  - first clean non-numeric line → supplier
  - short alpha token near the top → broker

### Item lines

- Prefer lines containing:
  - item keyword + pack size (`50kg`, `25 kg`)
  - common unit words (`bag`, `box`, `tin`, `kg`, `ltr`)

### Quantity

- `100 bags` / `100 bag` / `100 bg` → qty=100, unit=bag
- If pack size exists and qty exists, compute kg:
  - \(bags \times kg\_per\_bag\)

### Rates

- `57 58` → purchase=57, selling=58 (if no other clue)
- `P57 S58` / `P 57 S 58` → purchase/selling
- `del 56` / `delivered 56` → delivered_rate

### Payment days

- `7 days` / `payment 7` / `payment days 7` / `pd 7`

## Deterministic fallback

These rules must exist outside the LLM so the scan never “feels fake”.

Implementation:

- `backend/app/services/scanner_v3/pipeline.py::_fallback_parse_text`

