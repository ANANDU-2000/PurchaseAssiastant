# Purchase entry — minimal rebuild

## Goal

Replace trader-confusing GST copy, tall stacked rates, and finance jargon with a **short primary path**: Item → Qty/Unit → Purchase | Selling rates → **Tax OFF / ON** → compact preview → Save.

## Non-negotiables

- **Money truth** stays in [`calc_engine.dart`](../flutter_app/lib/core/calc_engine.dart) and server validation; UI only reflects the same `TradeCalcLine` math.
- **Tax OFF** → persisted line `tax_percent = 0`.
- **Tax ON** → rates are **excluding GST** (`RateTaxBasis.taxExtra`); tax from item/catalog `%` (editable under Advanced if needed).

## Primary surface (always visible)

| Block | Behaviour |
|-------|-----------|
| Item | Catalog / party inline suggest; keep quick-add row |
| Qty \| Unit | Single row; bag/kg mode as **one-line** toggles |
| Purchase \| Selling | **Same row** on typical phone widths (≥~320dp) |
| Tax OFF / ON | Single control; no “GST Extra / Included” on primary |
| Preview | 4–5 short lines only (see `purchase_line_preview_trader.dart`) |
| Actions | Save & add more / Save pinned with safe area + IME padding |

## Advanced (collapsed default)

Tax % override, freight, billty, delivered, discount, notes, HSN, **legacy GST inclusive/exclusive** controls for old lines only.

## Files

- [`purchase_item_entry_sheet.dart`](../flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart) — layout + state
- [`item_entry/item_entry_decorations.dart`](../flutter_app/lib/features/purchase/presentation/widgets/item_entry/item_entry_decorations.dart) — high-contrast fields
- [`purchase_line_preview_trader.dart`](../flutter_app/lib/features/purchase/presentation/widgets/item_entry/purchase_line_preview_trader.dart) — preview copy

## Acceptance (manual)

- New bag line: select item, bags qty, rates on one row, Tax ON, preview matches saved total on review step.
- Tax OFF: preview shows no tax; saved line has `tax_percent: 0`.
- Edit legacy inclusive line: open Advanced → legacy controls visible; optional one-tap convert (future).
