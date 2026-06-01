# Reports Navigation Fix

## Primary tabs (only)

| Tab | Query | Widget |
|-----|-------|--------|
| Overview | `overview` | `ReportsOverviewTab` |
| Items | `items` | `ReportsItemsTab` |
| Purchases | `purchase` | `ReportsPurchasesTab` |
| Stock | `stock` | `ReportsStockTab` |

## Legacy redirects

| Old `?tab=` | Resolves to |
|-------------|-------------|
| `movement`, `activity` | `stock` |
| `dead`, `slow` | `stock` + `?section=` |
| `categories`, `subcategories` | `items` |
| `suppliers`, `brokers` | `purchases` |
| `usage` | `items` (usage filter preset) |

## Router

- `/analytics` → `/reports`
- `/stock/dead` → `/reports?tab=stock&section=dead`
- `/stock/slow-moving` → `/reports?tab=stock&section=slow`
- `/stock/fast-moving` → `/reports?tab=stock&section=fast`

## Removed

- Activity tab
- More bottom sheet
- Desktop left nav tab duplicate (filter drawer only on desktop)
