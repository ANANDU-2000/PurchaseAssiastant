# Form focus flow rebuild

## Goals

- One predictable rule: **focus follows trader intent** (Next / Done), not random `unfocus()` calls.
- After **validation errors**, scroll + focus the first blocking control (already partially implemented in purchase flows).

## Purchase wizard (`purchase_entry_wizard_v2.dart`)

| Step | Primary inputs | Focus policy |
|------|------------------|--------------|
| 0 Party | Supplier `PartyInlineSuggestField`, Broker `PartyInlineSuggestField` | Supplier **Next** → broker (`onSubmitted`). Broker **Next** → `_partyAdvanceIfValid` → step 1 + **focus payment days** (post-frame). |
| 1 Terms | Payment days, commission, discount %, narration | `FocusTraversalGroup` + `OrderedTraversalPolicy` + `FocusTraversalOrder` on text fields; commission branch uses non-overlapping `NumericFocusOrder` values. |
| 2 Items | List + “+ Add Item” | List scroll controller owned by step; **no** outer `SingleChildScrollView` (see scroll architecture doc). |
| 3 Review | Read-only / save | Continue hidden; Save unfocuses via `_wizNext` path. |

## Pop / step back

- `PopScope` / back: `FocusScope.of(context).unfocus()` before step decrement (existing) — **keep** to avoid stale overlays.

## Anti-patterns removed

- Avoid `unfocus()` immediately after advancing to a step that contains editable text **unless** intentionally dismissing keyboard; Terms step now receives focus on payment days after Party advance.

## Files

- [purchase_entry_wizard_v2.dart](../../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart)
- [purchase_party_step.dart](../../flutter_app/lib/features/purchase/presentation/wizard/purchase_party_step.dart)
- [purchase_terms_only_step.dart](../../flutter_app/lib/features/purchase/presentation/wizard/purchase_terms_only_step.dart)
- [party_inline_suggest_field.dart](../../flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart)
