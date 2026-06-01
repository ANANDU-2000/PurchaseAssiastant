# Reports Stock Validation

**Date:** 2026-06-01

## Automated checks

| Check | Command | Expected |
|-------|---------|----------|
| Flutter analyze | `flutter analyze lib/features/reports/` | No issues |
| Status unit tests | `flutter test test/reports_stock_status_test.dart` | Pass |
| Card widget test | `flutter test test/reports_stock_card_test.dart` | Pass |
| Reports smoke | `flutter test test/reports_page_smoke_test.dart` | Pass |

## Status logic (backend)

Verified in `operations.py`:

```
out_of_stock  → current_stock <= 0
dead          → is_dead OR idle_days >= 60
fast          → used_7d > 0
very_slow     → idle_days >= 30 (and not fast/dead)
slow          → idle_days >= 7
no_activity   → idle_days >= 999 AND zero 7d/30d usage
active        → default on-hand healthy
```

Dead rule: `cur > 0`, `used_7d <= 0`, last purchase absent or ≥ `stale_days` (default 30).

## Movement age

`_idle_days_for_item`:

- If `used_7d > 0` → 0 (moved this week)
- Else max(`last_adjustment`, `last_purchase`) vs now
- No candidates → 999

## Usage windows

| Field | Source | Window |
|-------|--------|--------|
| `used_7d` | `DailyUsageLog` sum | Rolling 7 days |
| `used_30d` | `DailyUsageLog` sum | Rolling 30 days |

## Summary counts

Incremented per item with `current_stock > 0` for `all`; status buckets mutually exclusive via `_movement_status`.

## UI verification matrix

| Scenario | Expected UI |
|----------|-------------|
| Dead filter, zero items | "No dead stock found." |
| Search "sugar" | Only matching names/categories |
| Sort Highest stock | Descending `current_stock` |
| Tap KPI Slow | Filter = Slow, list filtered |
| Tap KPI Slow again | Filter = All |
| Card tap | Navigate to stock intelligence |
| API error | `FriendlyLoadError` + retry |

## Mobile spot-check (manual)

- [ ] 320px: KPI wraps, filters scroll, no page overflow
- [ ] 375px: Card qty readable without zoom
- [ ] Long item name wraps, no ellipsis
- [ ] Badge readable on yellow/orange backgrounds

## Database / Supabase

- **No new migration** for Stock Reports UI
- Reads: `catalog_items`, `daily_usage_log`, `stock_adjustment_log`
- Migrations 048–050 (ledger repair) already applied; unrelated to reports layout

## Backward compatibility

- `dead_stock`, `fast_moving`, `slow_moving` arrays still returned (capped)
- Overview KPIs continue using array lengths if `summary` absent
- Flutter summary fallback computes from `items[]` if needed

## Sign-off

| Area | Status |
|------|--------|
| Backend API extension | Done |
| Card UI | Done |
| KPI + filters + sort | Done |
| Search integration | Done |
| Empty states | Done |
| Documentation (6 files) | Done |
| Unit / widget tests | Done |
