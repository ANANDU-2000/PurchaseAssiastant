# iOS keyboard overlay audit

## Related

- Historical fixes: [IOS_KEYBOARD_OVERLAY_FIXES.md](../IOS_KEYBOARD_OVERLAY_FIXES.md)
- CTA policy: [CTA_AND_KEYBOARD_BEHAVIOR.md](./CTA_AND_KEYBOARD_BEHAVIOR.md)

## Problem class

On iOS, `MediaQuery.viewInsets.bottom` reflects the **software keyboard** height. It does **not** always fully account for the **input accessory view** (the “Prev / Next / Done” bar) as a separate layer in every layout configuration. Traders then see:

- The focused `TextField` sitting under the accessory bar
- Floating labels clipped at the top edge of the visible area
- `RawAutocomplete` / overlay panels sizing against `viewInsets` but still colliding with the accessory visually

## Code touchpoints (Purchase Assistant)

| Surface | IME handling | Risk |
|--------|--------------|------|
| [purchase_item_entry_sheet.dart](../../flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart) (`fullPage`) | `resizeToAvoidBottomInset: true` + `KeyboardSafeFormViewport` + pinned preview/footer padding | Low–medium: pinned stack height + IME |
| [purchase_entry_wizard_v2.dart](../../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart) | **Migrated** to `resizeToAvoidBottomInset: true`; footer uses safe padding without double-counting `viewInsets` in scroll padding | Medium (was `false` + manual `kb`) |
| [inline_search_field.dart](../../flutter_app/lib/shared/widgets/inline_search_field.dart) | `_optionsMaxHeight` uses `size.height - viewInsets.bottom - padding` | Medium: overlay vs accessory |
| Modals using `Padding(..., bottom: viewInsets.bottom)` | Various | Double-count if parent also resizes |

## Provisional allowance constant

Shared constant **`kMobileFormKeyboardAccessoryAllowance`** (see [form_field_scroll.dart](../../flutter_app/lib/core/widgets/form_field_scroll.dart)) documents a **provisional** extra gap (currently **36 logical px**) applied on **iOS** to:

- `TextField.scrollPadding` in dense purchase fields and item entry
- Conservative overlay max-height math in `InlineSearchField`

Re-measure on **iPhone 16 Pro** and **SE**; adjust constant in one place if hardware or iOS changes behavior.

## Verification

1. Focus lowest field on each full-screen form; field label + cursor must clear accessory bar.
2. Open supplier/broker suggestions; list must remain scrollable and not clipped by home indicator.
3. Rotate to landscape on notched devices; repeat.
