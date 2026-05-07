# 58 — VIEW_MORE_STANDARDIZATION

## Goal
Every “view more / list / history” surface shows the same packaged quantity string.

## SSOT helpers
- `formatPackagedQty(...)` in `flutter_app/lib/core/utils/line_display.dart`
- `formatLineQtyWeightFromTradeLine(...)` in `flutter_app/lib/core/utils/line_display.dart`
  - Uses `reportLineKg(...)` from `flutter_app/lib/core/reporting/trade_report_aggregate.dart` for bag kg.

## Wired pages (examples)
- Home: `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`
- Detail cards: `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`
- Ledger/history cards:
  - `flutter_app/lib/shared/widgets/trade_purchase_ledger_cards.dart`
  - `flutter_app/lib/features/item/presentation/item_history_page.dart`
  - `flutter_app/lib/features/broker/presentation/broker_history_page.dart`
- Intel cards:
  - `flutter_app/lib/shared/widgets/trade_intel_cards.dart`

