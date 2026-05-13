# Next-field navigation system

## Standard

| Key / action | Behavior |
|--------------|----------|
| **Next** (`TextInputAction.next`) | Move to the next control in traversal order; **scroll into view** via `scrollPadding` (includes IME + pinned preview reserve on item entry). |
| **Done** (`TextInputAction.done`) | `FocusManager.instance.primaryFocus?.unfocus()` unless a screen-specific `onSubmitted` commits. |

## Purchase wizard traversal

1. **Party:** Supplier → Broker (explicit `onSubmitted` on `PartyInlineSuggestField`). Broker Next runs `_partyAdvanceIfValid` → **Terms** opens with **Payment days** focused.
2. **Terms:** `FocusTraversalGroup` + `OrderedTraversalPolicy` + `FocusTraversalOrder` with `NumericFocusOrder`:
   - Payment days → Commission (percent **or** fixed amount field visible) → (optional commission unit dropdown receives focus via traversal skip / manual if needed) → Discount % → Narration.
3. **Items:** No text chain; list + Add Item.
4. **Review:** Save.

## Inline search / party fields

- `PartyInlineSuggestField` uses `textInputAction` + `onSubmitted` bridge to move focus or advance wizard.
- `InlineSearchField` defaults to `TextInputAction.search`; callers may pass `next` when embedded in a wizard.

## Hardware keyboard

`FocusTraversalGroup` order applies to Tab navigation on desktop/web builds; verify Tab order matches mobile Next order when testing desktop.

## Code references

- [purchase_party_step.dart](../../flutter_app/lib/features/purchase/presentation/wizard/purchase_party_step.dart)
- [purchase_terms_only_step.dart](../../flutter_app/lib/features/purchase/presentation/wizard/purchase_terms_only_step.dart)
- [purchase_entry_wizard_v2.dart](../../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart)
