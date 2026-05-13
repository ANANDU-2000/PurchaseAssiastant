# Dropdown overlay fixes

## Related prior work

- [SUPPLIER_BROKER_DROPDOWN_FIXES.md](../SUPPLIER_BROKER_DROPDOWN_FIXES.md) — gesture / scroll / tap propagation for supplier and broker inline suggest.

## Inline catalog / typeahead

[InlineSearchField](../../flutter_app/lib/shared/widgets/inline_search_field.dart):

- Uses `RawAutocomplete` + `TapRegion` with shared `groupId` so suggestion taps are not treated as “outside”.
- `_optionsMaxHeight` caps overlay height using viewport minus `viewInsets` and safe padding.
- **Update:** subtract iOS accessory allowance from usable height (see [IOS_KEYBOARD_OVERLAY_AUDIT.md](./IOS_KEYBOARD_OVERLAY_AUDIT.md)) so the panel stays shorter when the keyboard is open.

## Party supplier / broker

[PartyInlineSuggestField](../../flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart):

- Overlay sync + `Scrollable.ensureVisible` for keyboard-safe reveal (existing).
- Keep policy: **close suggestions on selection or explicit dismiss**, not on benign parent scroll if avoidable (see linked doc).

## Picker sheets

[search_picker_sheet.dart](../../flutter_app/lib/shared/widgets/search_picker_sheet.dart) — ensure `isScrollControlled` + max height respects keyboard on small devices when extended.

## Acceptance criteria

1. Suggestions remain scrollable while finger scrolls the list (no accidental close).
2. Selecting a row commits once (debounce / duplicate-pick guard stays).
3. Overlay never draws under the home indicator.
