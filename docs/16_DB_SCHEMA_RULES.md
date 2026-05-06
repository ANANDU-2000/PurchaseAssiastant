# 16 — DB Schema Rules (Stability + Correctness)

## Multi-tenant

All business data is scoped by `business_id`. Never cross-tenant query without super-admin authorization.

## Canonical purchase tables

- `trade_purchases` (header: supplier, broker, charges, totals)
- `trade_purchase_lines` (lines: catalog_item_id, qty, unit_type, rates)

## Unit/package fields

Unit system must converge to:
- `unit_type` ∈ `KG|BAG|BOX|TIN|PCS`

Default-mode constraints:
- BOX/TIN lines should not store kg totals.

## Learning table

- `catalog_aliases` stores scanner corrections and must be scoped to `business_id`.

