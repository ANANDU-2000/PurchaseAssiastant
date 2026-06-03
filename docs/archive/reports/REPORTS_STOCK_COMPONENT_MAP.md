# Reports Stock Component Map

**Date:** 2026-06-01

## Tree

```
ReportsShellPage
└── ReportsStockTab
    ├── ReportsStockSummaryBar      (KPI chips)
    ├── ReportsStockFilterSortBar   (filter chips + sort)
    └── ReportsStockIntelCard × N   (list)
```

## File reference

| Component | Path | Responsibility |
|-----------|------|----------------|
| `ReportsStockTab` | `tabs/reports_stock_tab.dart` | Async load, empty states, sliver list |
| `ReportsStockSummaryBar` | `widgets/reports_stock_summary_bar.dart` | Active/Slow/Dead/Fast KPI toggles |
| `ReportsStockFilterSortBar` | `widgets/reports_stock_filter_sort_bar.dart` | All/Active/Slow/Dead/Fast + sort sheet |
| `ReportsStockIntelCard` | `widgets/reports_stock_intel_card.dart` | Single item business card |
| `ReportsStockIntelItem` | `stock/reports_stock_models.dart` | Parsed API row + chip matching |
| `ReportsStockSummary` | `stock/reports_stock_models.dart` | Summary count DTO |
| `ReportsStockMovementStatus` | `stock/reports_stock_status.dart` | Enum, colors, labels |
| `reportsStockChipFilterProvider` | `stock/reports_stock_providers.dart` | Selected filter chip |
| `reportsStockSortProvider` | `stock/reports_stock_providers.dart` | Selected sort |
| `filteredReportsStockItemsProvider` | `stock/reports_stock_providers.dart` | Search + filter + sort pipeline |

## Data flow

```
GET /reports/summary
        │
        ▼
operationalReportsProvider
        │
        ├── reportsStockIntelItemsProvider  (parse items[])
        ├── reportsStockSummaryProvider     (parse summary{})
        │
        ▼
filteredReportsStockItemsProvider
   ← reportsFilterProvider.searchQuery
   ← reportsStockChipFilterProvider
   ← reportsStockSortProvider
        │
        ▼
ReportsStockIntelCard
```

## Backend helpers

| Function | File | Role |
|----------|------|------|
| `operational_reports_summary` | `routers/operations.py` | Endpoint |
| `_movement_status` | `routers/operations.py` | Classify item |
| `_is_dead_stock_item` | `routers/operations.py` | Dead stock rule |
| `_idle_days_for_item` | `routers/operations.py` | Movement age |
| `_aging_bucket` | `routers/operations.py` | Legacy bucket + insight |

## Deprecated (Stock tab)

| File | Status |
|------|--------|
| `slow_moving_row.dart` | Unused by Stock tab; kept for reference until deleted |
| `reports_stock_intel_tab.dart` | Replaced by card list |

## Navigation

Card tap → `/stock/intelligence/:id` (existing stock intelligence route).

## Tests

| File | Covers |
|------|--------|
| `test/reports_stock_status_test.dart` | Parsing, filters, summary |
| `test/reports_stock_card_test.dart` | Card renders qty + badge |
