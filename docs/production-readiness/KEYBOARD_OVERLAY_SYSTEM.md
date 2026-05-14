# Keyboard overlay system

## Problem

Numeric keyboards hid rate fields, summary strips, and primary actions on wizard and catalog flows.

## Root causes

- Some parents use `resizeToAvoidBottomInset: true` (Scaffold shrinks body). Adding `MediaQuery.viewInsets` again in descendants **double-counts** padding unless `KeyboardSafeFormViewport.useViewInsetBottom` is set correctly (`flutter_app/lib/shared/widgets/keyboard_safe_form_viewport.dart`).
- Not every field had a focus listener to scroll the focused field into the nearest `Scrollable`.

## Fixes

- **Shared helper** `bindFocusNodeScrollIntoView` in `flutter_app/lib/core/widgets/form_field_scroll.dart` registers a `FocusNode` listener and calls `Scrollable.ensureVisible` on the next frame.
- **Purchase wizard** (`purchase_entry_wizard_v2.dart`): binds party + all terms `FocusNode`s including new commission / header / narration nodes passed into `PurchaseTermsOnlyStep`.
- **Terms step** (`purchase_terms_only_step.dart`): optional `FocusNode`s wired to commission, discount, and narration fields.
- **Add item sheet** (`purchase_item_entry_sheet.dart`): `_itemFocus` now mirrors qty/landing/selling with `_ensureFocusedFieldVisible`.
- **Supplier quick create** (`supplier_create_simple.dart`): `_nameFocus` + `scrollPadding` from `formFieldScrollPaddingForContext`.
- **Reusable widget** `KeyboardLiftedFooter` (`flutter_app/lib/shared/widgets/keyboard_lifted_footer.dart`) for optional `AnimatedPadding` + `SafeArea` footers where a route does not resize for IME.

## Verification

- iPhone with numeric keyboard: stepping Party → Terms → focus commission % then narration; field should scroll so the **Continue** row remains reachable.
- Add item full-page: focus item name then qty; list scrolls without hiding pinned preview.
