# Keyboard and safe-area audit

## Principles (trader / mobile ERP)

1. **`MediaQuery.viewInsetsOf(context).bottom`** — pad fixed bottom actions and modal content so primary buttons stay above the IME. Prefer short animations (`AnimatedPadding` / `AnimatedContainer`) to match keyboard motion.
2. **`resizeToAvoidBottomInset`** — Scaffolds that host forms should set `true` unless a deliberate full-screen custom keyboard strategy exists.
3. **Sheets over dialogs** — Multi-field edits on small phones should use **`showModalBottomSheet`** with `isScrollControlled: true`, safe area, and bottom inset padding instead of `AlertDialog` + scroll-only mitigation.
4. **SafeArea** — Top filter/chip rows on notched devices need `SafeArea(bottom: false)` (or equivalent padding) so KPI strips and chips do not sit under the status bar / Dynamic Island.

## Audited implementations (reference paths)

| Area | File | Mechanism |
|------|------|-----------|
| Purchase wizard footer vs keyboard | [`purchase_entry_wizard_v2.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart) | `resizeToAvoidBottomInset: true`; `MediaQuery.viewInsetsOf(ctx).bottom` for bottom bar padding |
| Catalog edit item | [`catalog_item_detail_page.dart`](../../flutter_app/lib/features/catalog/presentation/catalog_item_detail_page.dart) | `_editItemDefaults` → `showModalBottomSheet` + keyboard padding |
| Purchase home top metrics / chips | [`purchase_home_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart) | SafeArea / padding for top strip (notch class devices) |
| App shell builder | [`app.dart`](../../flutter_app/lib/app.dart) | `apiDegradedProvider` banner: `SafeArea(bottom: false)` on top `Material` |

## Supplier / party field

[`party_inline_suggest_field.dart`](../../flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart) — `autocorrect: false`, `enableSuggestions: false` to reduce iOS IME fighting the inline panel; see [SUPPLIER_SUGGESTION_ENGINE_FIX.md](SUPPLIER_SUGGESTION_ENGINE_FIX.md).

## Regression checks

- Wizard: open supplier step, focus text field, scroll content; **Continue** must remain tappable or one scroll away.  
- Catalog item: open **Edit item** sheet, focus lowest field; **Save** reachable.  
- Rotate device (if supported): insets update without leaving a permanent gap.

## Phase 2

Bottom-nav-wide keyboard policy and FAB + keyboard (item 17) remain roadmap-only; see [FINAL_PRODUCTION_UX_READINESS.md](FINAL_PRODUCTION_UX_READINESS.md).
