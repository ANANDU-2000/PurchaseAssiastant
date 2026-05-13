# Purchase history — delivery tracking

## User goals

- See **how long** goods have been undelivered at a glance.
- **Sort** longest-waiting first when reviewing open shipments.
- Quick filters: **Awaiting**, **Stuck**, **Done (received)**.

## Implementation (this pass)

| Feature | Where |
|---------|--------|
| Age since purchase (local calendar days) | `flutter_app/lib/core/purchase/delivery_aging.dart` → `undeliveredDaysSincePurchase` |
| Colour bands for undelivered chip | `undeliveredAgingBandFromDays` + `undeliveredAgingColors` |
| Chip styling in list | `purchase_home_page.dart` → `_purchaseHistoryDaysChip` |
| Primary filters `received`, `delivery_stuck` | `purchaseHistoryVisibleSortedForRef` |
| Sort longest-first | `_purchaseHistorySortPurchases` when primary is `pending_delivery` or `delivery_stuck` |
| Horizontal chips | same file — added **Stuck** and **Done** |

## Band rules (undelivered, by days since bill date)

| Days | Band |
|------|------|
| 0–2 | Neutral (slate) |
| 3–5 | Warning (orange) |
| 6–9 | Strong (deep orange) |
| 10+ | Critical (red) |

Payment/due-date overdue continues to use existing red “overdue” branches in `_purchaseHistoryDaysChip`.

## API / SSOT

- `delivery_stuck` / `received` / `pending_delivery` are **client-side** filters on the trade list (`_tradeListApiStatus` returns `null` — full list, filtered locally). Same pattern as existing `pending_delivery`.

## Cross-links

- `DELIVERY_AGING_PRIORITY_ENGINE.md`
- `MOBILE_NAVIGATION_REDESIGN.md` (history tab)
