# Supplier / broker inline suggestion engine

## Problem (historical)

Typing in the party field while interacting with the suggestion panel could: lose focus, collapse suggestions mid-scroll, or resolve gestures in favor of a **parent** scroll view—felt like “typing sur closes suggestions.”

## Implementation

**File:** [`flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart`](../../flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart)

### Class-level behavior

- **`PartyInlineSuggestField`** is documented as avoiding a nested scroll arena: the inline list grows with the parent scroll so parent vertical drags are not stolen by an inner `ListView` scrollable.

### Text field

- **`autocorrect: false`** and **`enableSuggestions: false`** on the `TextField` to reduce iOS QuickType / autocorrect fighting the custom suggestion UI.

### Inline suggestion list physics

- Suggestion `ListView` uses **`physics: const NeverScrollableScrollPhysics()`** so the inner list does not compete for vertical gestures; user scrolls the wizard body.

### Grace timer

- **`Timer(const Duration(milliseconds: 800), …)`** for `_suggestPanelGrace` — longer window when focus/pointer transitions could otherwise collapse the panel prematurely.

### State flags

- `_suggestPanelGrace` / `_suggestPanelGraceTimer` coordinate blur and panel visibility; other guards (`_suppressPanelAfterPick`, etc.) avoid picking during in-flight operations.

## Verification

1. Purchase wizard → supplier step: type a partial name, scroll the **page** vertically—panel should remain stable for typical gestures.  
2. Slow drag from field toward suggestions: no wrong auto-pick from a short blur.  
3. iOS: confirm autocorrect bar does not steal taps intended for suggestion rows.

## Related

- [KEYBOARD_AND_SAFEAREA_AUDIT.md](KEYBOARD_AND_SAFEAREA_AUDIT.md)
