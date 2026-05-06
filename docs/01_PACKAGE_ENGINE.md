# 01 — Package Engine (Unit System + Packaging Rules)

## Allowed package types (hard rule)

Only these package types exist in the system:

- `KG` (loose kg products)
- `BAG` (named bag products like `SUGAR 50KG`, `RICE 26KG`, `ATTA 30KG`)
- `BOX` (counted boxes/cartons)
- `TIN` (counted tins)
- `PCS` (counted pieces)

Everything else is **forbidden** (e.g. `SACK`, `LTR`, arbitrary unit dropdowns).

## Product-type semantics

### KG products
- **Track**: `total_kg`
- **Pricing**: `₹/kg` only

### BAG products
- **Track**: `bag_count`, `weight_per_bag_kg`, derived `total_kg`
- **Pricing mode**: `₹/kg` OR `₹/bag` (auto-convert)

### BOX products (default wholesale mode)
- **Track**: `box_count`
- **Pricing**: `₹/box`
- **DO NOT track**: kg, items/box, kg/item (unless advanced inventory enabled)

### TIN products (default wholesale mode)
- **Track**: `tin_count`
- **Pricing**: `₹/tin`
- **DO NOT track**: kg, weight/tin, items/tin (unless advanced inventory enabled)

### PCS products
- **Track**: `pcs_count`
- **Pricing**: `₹/pc`

## Auto package detection from names

Detection rules (case-insensitive):

- Contains `BOX` or `CARTON` or `PKT` → `BOX`
- Contains `TIN` or `LTR` (e.g. `15LTR`) → `TIN`
- Contains `KG` token **and** catalog indicates bag-style product → `BAG`
- Otherwise → `KG` (fallback) or catalog default

### Weight-per-bag extraction (BAG only)

Recognize bag weights inside item names:

`5kg`, `10kg`, `15kg`, `25kg`, `26kg`, `30kg`, `50kg` (expandable list).

## Normalization invariants

- A `BOX` or `TIN` line must have `total_kg = null` in default mode.
- A `BAG` line must satisfy:
  - `total_kg = bag_count × weight_per_bag_kg` (within tolerance)
- A `KG` line must satisfy:
  - `total_kg == qty`

