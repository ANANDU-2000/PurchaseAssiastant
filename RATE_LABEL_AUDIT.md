# Rate Label Audit

## Central Helpers
- Flutter: `dynamic_unit_label_engine.dart`
- Flutter: `trade_purchase_rate_display.dart`
- Backend: `rate_display_context.py`

## Fixed In This Pass
- Item entry purchase/selling labels now use `ResolvedItemUnitContext.rateDimension` for non-weight-bag rows.
- Box rows display `?/box`.
- Tin rows display `?/tin`.
- Bag rows display `?/bag` unless explicit per-kg rate mode is selected.

## Remaining Hardcoded/Contextual Mentions
- `reports_item_metrics.dart` intentionally has kg-weighted averages (`/kg wtd`), not a line-rate label.
- `purchase_invoice_pdf_layout.dart` contains broker commission wording for `flat_kg`.
- Scanner preview/table files still need a follow-up pass to ensure every displayed rate label uses preview `rate_context` or resolved item context.
