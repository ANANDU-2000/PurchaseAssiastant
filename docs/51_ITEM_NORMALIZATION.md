# 51 — ITEM_NORMALIZATION

## Goal
Legacy rows may contain removed units, but UI should normalize for display and rules:
- `sack` behaves like `bag` for count + kg display

## Flutter
- Display normalization in multiple places uses:
  - `formatPackagedQty(...)` and `formatLineQtyWeightFromTradeLine(...)` in
    `flutter_app/lib/core/utils/line_display.dart`
- Detail aggregation normalizes `sack → bag` for totals:
  - `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`

## Backend
- Commission basis and unit checks normalize by `.strip().lower()`
  - `backend/app/services/trade_purchase_service.py`

