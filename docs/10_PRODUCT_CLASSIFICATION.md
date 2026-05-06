# 10 — Product Classification (Auto Package Type)

## Classification sources (priority)

1. Catalog item metadata (`catalog_items.default_unit`)
2. Name token detection
3. Fallback default (`KG`)

## Token rules

- `TIN` or `LTR` in name → `TIN`
- `BOX`/`CARTON`/`PKT` → `BOX`
- `PCS`/`PC`/`PIECE` → `PCS`
- `NN KG` and bag-style product → `BAG`

## Bag weight extraction

Extract `weight_per_bag_kg` from name when it contains:
- 5kg, 10kg, 15kg, 25kg, 26kg, 30kg, 50kg

## Output requirements

Classification must never silently flip user-entered units at save time; if a mismatch is detected, it becomes a validation blocker requiring explicit confirmation.

