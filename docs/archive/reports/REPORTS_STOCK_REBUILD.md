# Reports → Stock Tab Rebuild Plan

**Date:** 2026-06-01  
**Scope:** Full UX/UI rebuild of Reports → Stock (not incremental patches).

## Business goal

Warehouse owner answers within **3 seconds**:

- Which items need attention?
- Which are dead / slow / fast / high stock / zero movement?
- Which need reorder action?

## Problems addressed

| # | Problem | Solution |
|---|---------|----------|
| 1 | Hard-to-scan rows | Compact business cards with left border accent |
| 2 | Weak stock qty | Level-2 **bold 26px** qty + uppercase unit |
| 3 | Poor typography | HexaDsType hierarchy (name → qty → movement → badge) |
| 4 | Item names dominate | Stock number is largest visual element |
| 5 | Hidden warehouse metrics | 7d + 30d usage, last movement, category on every card |
| 6 | Disconnected badges | Standardized 6-status color system |
| 7 | Empty space | Dense card padding, vertical list only |
| 8 | No prioritization | Summary KPI bar + filter chips with counts |
| 9 | Detached slow/dead filters | Unified `[All][Active][Slow][Dead][Fast]` row |
| 10 | Can't spot problems | Red/orange/yellow left borders + status badges |
| 11 | Poor mobile | Wrap chips, no ellipsis on names, 320–414px safe |
| 12 | Slow decisions | Sort + search + tap-through to stock intelligence |

## Architecture

### Backend (`GET /reports/summary`)

Extended response:

```json
{
  "summary": { "all", "active", "slow", "dead", "fast", "no_activity" },
  "items": [ { …, "used_30d", "movement_status" } ],
  "dead_stock": [],
  "fast_moving": [],
  "slow_moving": []
}
```

Legacy keys retained for Overview KPIs and older clients.

### Flutter

| Layer | Files |
|-------|--------|
| Models | `stock/reports_stock_models.dart` |
| Status / filters | `stock/reports_stock_status.dart` |
| Providers | `stock/reports_stock_providers.dart` |
| Card | `widgets/reports_stock_intel_card.dart` |
| KPI bar | `widgets/reports_stock_summary_bar.dart` |
| Filter + sort | `widgets/reports_stock_filter_sort_bar.dart` |
| Tab shell | `tabs/reports_stock_tab.dart` |

Search uses existing `reportsFilterProvider` from Reports top bar (placeholder: **Search item name…**).

## Removed

- Vertical section cards (Current / Low / Out / Dead / Fast / Slow blocks)
- `SlowMovingRow` layout in Stock tab (`Current stock: …` micro-copy)
- Horizontal sub-tabs within Stock

## Validation checklist

- [x] Font hierarchy (name semi-bold → qty bold large → movement medium → badge small)
- [x] Status logic aligned with backend `_movement_status`
- [x] `used_30d` from `DailyUsageLog` (30-day window)
- [x] Filter counts from API `summary`
- [x] Sort: stock, usage, movement age, A–Z
- [x] Empty states per filter
- [x] Widget + unit tests
- [x] `flutter analyze` on reports feature

## Deploy notes

1. Deploy backend first (new `items` + `summary` fields).
2. Flutter reads new fields; falls back to client-side summary if absent.
3. No Supabase migration required (computed from existing tables).
