# Terms page keyboard fix

## Problem

Broker commission and narration fields could end up behind the keyboard; Continue felt glued to the accessory bar.

## Root cause

Only `paymentDaysFocus` had an explicit `FocusNode` in the wizard; commission / discount / narration fields relied on implicit focus without `bindFocusNodeScrollIntoView`.

## Fix

- Added `_termsCommissionFocus`, `_termsHeaderDiscFocus`, `_termsNarrationFocus` in `purchase_entry_wizard_v2.dart`, disposed with other nodes, and passed into `PurchaseTermsOnlyStep`.
- `PurchaseTermsOnlyStep` wires those nodes into `orderedField` for both commission modes, discount %, and narration.
- All terms-related nodes plus party nodes call `bindFocusNodeScrollIntoView` during wizard `initState`.
- Footer continues to use `MediaQuery.viewInsetsOf` padding on the `SafeArea` wrapper (`_buildWizardBody`).

## Verification

- Broker ON: toggle Commission % ↔ Fixed ₹, focus amount field, then Discount %: each transition should scroll the active field above the keyboard.
- iOS accessory bar visible: Continue remains tappable without overlapping keys.
