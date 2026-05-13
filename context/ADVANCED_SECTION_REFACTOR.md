# Advanced section refactor

## Container

Use existing `_moreSectionExpanded` inkwell; rename label to **“Advanced”** with subtitle “Discount, freight, tax %, notes”.

## Order inside Advanced

1. Optional banner: “This line uses old GST Included pricing — adjust in section below.” (only if legacy basis detected)
2. Discount
3. Tax % (hidden entirely when Tax OFF)
4. Freight / delivered / billty (respect `omitLineFreightDeliveredBilltyDiscount`)
5. Notes
6. **Legacy GST basis** (purchase + selling segmented) — collapsed sub-expander if needed

## Persistence

- Stop auto-writing `GstRateBasisPrefs` from primary path; only write when user edits **legacy** basis controls.
