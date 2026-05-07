# Package summary rules (History + month strip)

## Source of truth

Per-line classification uses **`reportEffectivePack`** / **`reportLineKg`** from `trade_report_aggregate.dart` (same family as Reports).

- **Bag** — show **count + kg** when kg &gt; 0 (`formatLineQtyWeight` for natural “100 bags • 5,000 kg” style).
- **Box / tin** — **count only**; never append kg from geometry.
- **Loose kg** lines (unit kg/quintal, no pack inference) — append as kg segment.
- **Mixed invoice** — join segments with ` • ` (e.g. bags+kg then boxes).

## Month KPI kg

`computePurchaseHistoryMonthStats`: **kg = bag kg + loose kg**; box/tin never contribute.

## Helpers (`line_display.dart`)

- `purchaseHistoryPackSummary(TradePurchase)`
- `purchaseHistoryItemHeadline(TradePurchase)`
- `purchaseHistoryPackKinds` / `purchaseHistoryMatchesPackKindFilter`
