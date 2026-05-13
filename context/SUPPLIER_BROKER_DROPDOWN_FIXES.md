# Supplier / broker dropdown — interaction fixes

## Symptoms

- Suggestions close while scrolling
- Tap conflicts between overlay and parent scroll
- Keyboard covers last options

## Root widgets

| Context | Widget | File |
|---------|--------|------|
| Party step (inline list) | `PartyInlineSuggestField` | [`party_inline_suggest_field.dart`](../flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart) |
| Catalog / overlay mode | `InlineSearchField` (`RawAutocomplete`) | [`inline_search_field.dart`](../flutter_app/lib/shared/widgets/inline_search_field.dart) |

## Engineering rules

1. **One scroll owner**: inline party list intentionally avoids nested `ListView`; keep it. For overlay autocomplete, use `ClampingScrollPhysics` (already) and ensure `TapRegion` group matches field + overlay (`_suggestionTapGroup`).
2. **Do not close on scroll start**: avoid `onTapOutside` that unfocuses while pointer is over the options `Material`; rely on `TapRegion` + explicit close button.
3. **Max height**: `_optionsMaxHeight` caps overlay; re-tune to `min(usable*0.55, 320)` on short phones if clipping reported.
4. **Debounce**: party field debounces; catalog `PartyInlineSuggestField` should use same pattern where typing is heavy.

## Verification

- Flutter web + Android: scroll suggestions with finger down on list — list scrolls, field stays focused until selection or close.
- iOS: keyboard up → suggestions remain reachable (scroll + inset).

## Applied (implementation)

- [`inline_search_field.dart`](../flutter_app/lib/shared/widgets/inline_search_field.dart): each autocomplete row is wrapped with `ConstrainedBox(minHeight: 44)` so touch targets meet the 44px minimum on small screens.
