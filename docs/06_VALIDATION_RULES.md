# 06 — Validation Rules (Prevent Financial + Qty Corruption)

## Hard blockers (cannot save)

- Missing supplier
- Any unresolved item match (below threshold) without explicit user pick
- Negative rate / negative total
- BAG math mismatch:
  - `bag_count × weight_per_bag_kg != total_kg` (within tolerance)
- KG confusion guard:
  - If item is BAG product and user enters `5000 bags` but derived kg is impossible → show: **“Did you mean 5000kg instead of 5000 bags?”**
- BOX/TIN must not carry `total_kg` in default mode
- Duplicate save detected (unless `force_duplicate=true`)

## Smart warnings (user can proceed after explicit confirm)

- Supplier fuzzy match 70–91% (ask “Did you mean …?”)
- Broker unresolved (broker is optional)
- Delivered/bilty/freight parsed but out-of-range (sanity band)

## Range sanity bands

- `payment_days`: 0..365
- rates: 0 < rate < 1,000,000
- bag weights: 1..100 kg typical (allow up to 200 kg)

## Validation surface rules

- Inline field errors (no snackbars for validation).
- Save button disabled when blockers exist.

