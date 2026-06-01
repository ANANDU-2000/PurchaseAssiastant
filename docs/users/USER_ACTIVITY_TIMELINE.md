# User Activity Timeline

**Date:** 2026-06-01

## Pattern

Day-grouped vertical timeline (Notion/Linear style):

```
Today
  ● Stock updated        10:25 AM
  ● Purchase created      9:10 AM

Yesterday
  ● Item created          4:30 PM
```

## Data sources

| Section | Provider | API |
|---------|----------|-----|
| All activity | `userActivityFeedProvider` | `listUserActivity` (30d) |
| Stock | `userStockHistoryProvider` | `listUserStockAdjustments` |
| Purchases | `userPurchasesProvider` | `listUserPurchases` |
| Items | `userCreatedItemsProvider` | `listUserCreatedItems` |
| Ledger | `userLedgerGroupedProvider` | `listUserLedgerGrouped` |

Stock/Purchase/Item/Ledger sections map rows into timeline shape for consistent UI.

## Component

`UserActivityTimeline` — groups by Today / Yesterday / weekday / date.

`UserActivityTab` — horizontal subsection chips + timeline body.

## Empty states

- All: "No activity in the last 30 days."
- Stock: "No stock activity yet."
- etc.

## vs Staff activity page

`/staff/activity` remains self-service with Today/Week/Month period — separate from owner user profile drill-down.
