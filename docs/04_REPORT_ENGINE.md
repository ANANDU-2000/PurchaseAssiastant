# 04 — Report Engine (Canonical Aggregations)

## Ground rules

- Reports must use **real saved data only** (`trade_purchases`, `trade_purchase_lines`).
- Never invent averages or rates.
- Aggregations must respect package type semantics:
  - BAG: show `total_kg` and `bags`
  - KG: show `total_kg`
  - BOX: show `boxes` only (no kg)
  - TIN: show `tins` only (no kg)
  - PCS: show `pcs` only

## Row formats (mobile)

- BAG: `SUGAR 50KG — 5000kg • 100 bags — ₹56/kg → ₹57/kg`
- BOX: `SUNRICH BOX — 100 boxes — ₹2300/box → ₹2400/box`
- TIN: `RBD 15LTR — 50 tins — ₹2200/tin → ₹2300/tin`

## Totals

- Overall spend: `Σ(line_total)` (post-discount rules from `02_CALCULATION_ENGINE.md`)
- Qty totals are package-type aware (do not sum kg for box/tin unless advanced mode enabled).

## Correctness tests

All report endpoints must be validated by:
- `docs/17_TEST_CASES.md`
- backend tests ensuring parity between Home and Reports for same date range

