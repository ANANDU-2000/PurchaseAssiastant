# iOS keyboard & bottom overlay fixes

## Targets

- Full-screen add item [`PurchaseItemEntrySheet`](../flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart) `fullPage: true` uses `Scaffold` + pinned preview/footer **below** `KeyboardSafeFormViewport`.

## Rules

1. **Scaffold** `resizeToAvoidBottomInset: true` (already) — body height shrinks when IME opens.
2. **Pinned footer block** must add `MediaQuery.viewInsetsOf(context).bottom` to its padding so **Save** moves fully above the keyboard when the preview stack is tall.
3. **`KeyboardSafeFormViewport`**: with `resizeToAvoidBottomInset: true`, **do not** set `useViewInsetBottom: true` (would double-count per widget docstring).
4. **Safe area**: use `SafeArea` on footer row; respect home indicator.

## Files

- [`purchase_item_entry_sheet.dart`](../flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart) — `previewPinned` padding
- [`keyboard_safe_form_viewport.dart`](../flutter_app/lib/shared/widgets/keyboard_safe_form_viewport.dart) — only if a non-resizing parent appears

## Applied (implementation)

- Full-page `previewPinned` bottom padding uses `MediaQuery.viewInsetsOf(context).bottom` when the IME is open (`+12`), otherwise safe-area / default padding, so the preview + Save row clears the keyboard.

## Test matrix

- iPhone SE, iPhone 14, small Android (360×780): open numeric fields sequentially; ensure Save never sits under keyboard.
