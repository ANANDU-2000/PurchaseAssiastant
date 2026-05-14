# Add item form UX rebuild

## Problem

Totals and rate fields could sit under the IME; operators lost context while typing bag counts and rates.

## Root cause

Scroll padding and focus-scroll hooks were not applied uniformly (item name lacked the same listener pattern as qty/landing/selling).

## Fix

- `_itemFocus` now listens with `_onItemFocusScroll` → `_ensureFocusedFieldVisible()` alongside existing qty/landing/selling/kg listeners (`purchase_item_entry_sheet.dart`).
- `scrollPadding` continues to use `formFieldScrollPaddingForContext` with a larger reserve for full-page mode (`_kPinnedPreviewReserve`).

## Verification

- Full-page add item: focus item search, then qty, then purchase rate; each field should scroll so preview + CTAs remain reachable.
- Bottom sheet mode: confirm no regression in `KeyboardSafeFormViewport` layout (`useViewInsetBottom` stays false where scaffold resizes).
