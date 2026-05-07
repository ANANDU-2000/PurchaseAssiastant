# 43 — REPORT_AGGREGATION

## Goal
Reports and dashboards must use the **same package semantics** as purchase entry:
- kg totals are **bag-only**
- box/tin are **count-only**

## Flutter aggregation SSOT
- `buildTradeReportAgg(...)` in `flutter_app/lib/core/reporting/trade_report_aggregate.dart`
  - `reportLineKg(...)` computes kg for BAG lines (from `kgPerUnit` or defaults)
  - BOX/TIN return 0 kg

## Display SSOT
- `formatPackagedQty(...)` in `flutter_app/lib/core/utils/line_display.dart`
  - BAG: `5000 KG • 100 BAGS`
  - BOX: `100 BOXES`
  - TIN: `50 TINS`

## Where used
- Reports list / tiles:
  - `flutter_app/lib/features/reports/presentation/reports_full_list_page.dart`
  - `flutter_app/lib/features/reports/presentation/reports_item_tile.dart`
  - `flutter_app/lib/features/reports/reporting/reports_item_metrics.dart`

