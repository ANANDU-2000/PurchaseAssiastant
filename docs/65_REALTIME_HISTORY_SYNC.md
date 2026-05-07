# Realtime history sync

## Rule

After any purchase workspace mutation, lists and KPIs refresh without requiring pull-to-refresh.

## Mechanism

`invalidatePurchaseWorkspace(ref)` → `invalidateBusinessAggregates` → `invalidateTradePurchaseCaches` (invalidates `tradePurchasesListProvider`, `tradePurchasesForAlertsProvider`, catalog intel) plus dashboards and reports providers.

## Call sites (non-exhaustive)

- Purchase wizard save (`purchase_entry_wizard_v2.dart`)
- Detail edit / delete / mark paid (`purchase_detail_page.dart`)
- History delete / mark paid / **PDF share** (`purchase_home_page.dart`)
- Ledgers and catalog flows as already wired

## Loading UX

`tradePurchasesParsedProvider` uses **`skipLoadingOnReload` / `skipLoadingOnRefresh`** with `ListSkeleton` on cold load; stale rows can remain visible while refetch completes.
