# iPhone 16 Pro / Dynamic Island layout fixes

## Device-specific stress factors

- Taller safe-area **top** inset (Dynamic Island).  
- Large software keyboard + home indicator inset.  
- Chip rows and horizontal scrollers easily clipped if laid out flush to `padding: EdgeInsets.zero` under the status bar.

## Implemented mitigations (code references)

1. **Top chip / metric strips**  
   [`purchase_home_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart) — wrap filter/metric UI in `SafeArea` (or equivalent) so tabs and chips clear the notch / island. Verify after any refactor of the header `Column` / `Sliver` structure.

2. **Wizard bottom actions**  
   [`purchase_entry_wizard_v2.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart) — combine `SafeArea` with `viewInsets.bottom` so the primary button is not behind the keyboard.

3. **Modal edit flows**  
   [`catalog_item_detail_page.dart`](../../flutter_app/lib/features/catalog/presentation/catalog_item_detail_page.dart) — bottom sheet + `useSafeArea` + inset padding for IME.

4. **Global degraded API banner**  
   [`app.dart`](../../flutter_app/lib/app.dart) — top banner uses `SafeArea(bottom: false)` so the warning does not draw under the island.

## Manual QA checklist (physical or Simulator)

- [ ] Dynamic Island device: open **Purchase** list — top KPI/chips fully visible; no horizontal clip at leading edge.  
- [ ] Purchase wizard: supplier field focused — Continue visible; dismiss keyboard — no double gap.  
- [ ] Catalog → item → **Edit item defaults** — all fields scroll; Save never under keyboard.  
- [ ] Reports: period chips and overview — no overlap with status bar.  
- [ ] Landscape (if supported): critical actions still reachable.

## Phase 2

Home dashboard hierarchy (item 16) may add more top-of-screen modules; each must repeat SafeArea / padding discipline.
