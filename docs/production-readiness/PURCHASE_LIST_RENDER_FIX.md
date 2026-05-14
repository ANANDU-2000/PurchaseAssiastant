# Purchase list render fix

## Problem

KPI chips showed purchases and money while the card list area looked empty, or filters hid every row without explanation.

## Root causes

1. `purchaseHistoryMonthStatsProvider` read `tradePurchasesForAlertsParsedProvider` (up to 50 rows) while cards used `tradePurchasesParsedProvider` gated on `shellCurrentBranchProvider == ShellBranch.history` (`trade_purchases_provider.dart`). Mismatched sources produced “stats without cards.”
2. When client filters removed all rows from a non-empty loaded list, the UI fell through to `_HistoryEmpty` (“No purchases yet”) which was misleading.

## Fixes

- `purchaseHistoryMonthStatsProvider` now prefers `tradePurchasesParsedProvider` whenever list data is available; while the list is `loading`/`error`, it temporarily falls back to the alerts snapshot so the strip is not blank on first paint.
- `PurchaseHomePage` post-frame sets `shellCurrentBranchProvider` to `ShellBranch.history` if it ever lags while the `/purchase` route is mounted (`purchase_home_page.dart`).
- New `_HistoryFiltersHideAll` state when `items.isNotEmpty` but `visible.isEmpty`, with **Clear search & filters** action.

## Verification

- Cold start → History: KPI “Purch” count should track the same loaded rows as cards (within the selected analytics date window).
- Apply search text that matches nothing: see filter-specific empty state, not generic “No purchases yet.”
