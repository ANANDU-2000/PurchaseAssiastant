# Unit Sync Repair Report

## Code Repairs
- Added `flutter_app/lib/core/units/resolved_item_unit_context.dart`.
- Updated `purchase_item_entry_sheet.dart` to consume `ResolvedItemUnitContext` for unit dropdown choices, selected value normalization, quantity labels, and purchase/selling rate labels.
- Updated backend `unit_resolution_service.py` so unverified legacy `PCS` rows can be overridden by strong text/package rules.
- Fixed backend token matching so `425 GM` matches rules written as `425GM`.

## Architectural Direction
- Backend catalog metadata remains the canonical item metadata source.
- Flutter consumes `unit_resolution` first.
- Local classifier is now fallback, not primary truth.
- Rate labels come from resolved rate dimension where available.

## Remaining Follow-up
- Extend `PurchaseLineDraft` to persist a draft-level `rateContext` field to eliminate remaining adapter call-site maps.
- Route scanner draft item edits through the same resolved context before preview display.
