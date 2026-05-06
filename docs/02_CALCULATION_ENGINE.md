# 02 — Calculation Engine (Deterministic Money + Qty)

## Principles

- Server is the source of truth for totals.
- Use strict `Decimal` math (see `backend/app/services/decimal_precision.py`).
- Never compute with floats for persisted financial values.

## Line total rules (by package type)

### KG
- `line_total = total_kg × purchase_rate_per_kg`

### BAG
Pricing mode:
- `₹/kg`: `line_total = total_kg × purchase_rate_per_kg`
- `₹/bag`: `line_total = bag_count × purchase_rate_per_bag`

### BOX
- `line_total = box_count × purchase_rate_per_box`

### TIN
- `line_total = tin_count × purchase_rate_per_tin`

### PCS
- `line_total = pcs_count × purchase_rate_per_pc`

## Header totals

- `total_amount = Σ(line_total) - header_discount + freight + billty + …`
- Charges are explicit fields; never inferred.

## Selling rate

- Stored per line.
- Never affects purchase total math; used in profit/decision reports and PDF.

## Commission

Supports:
- percent of invoice (or of kg total where configured)
- fixed per unit (`kg|bag|box|tin`)
- fixed total (once)

Commission calculation rules are defined in `06_VALIDATION_RULES.md` to prevent negative totals.

