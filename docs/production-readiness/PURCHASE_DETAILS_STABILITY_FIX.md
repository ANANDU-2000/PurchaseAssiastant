# Purchase details stability

## Problem

After creating or opening a purchase, the detail route sometimes showed an endless skeleton, or operators saw the global fatal screen instead of an inline retry.

## Root cause

- `tradePurchaseDetailProvider` awaited `getTradePurchase` with no upper bound, so a hung socket left the UI in `loading` forever (`flutter_app/lib/features/purchase/providers/trade_purchase_detail_provider.dart`).
- Navigation to `/purchase/detail/:id` did not pass a list-row seed, so there was nothing to render while the first GET was in flight (`PurchaseDetailPage` in `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`).

## Fix

- Wrapped the API future with `.timeout(kTradePurchaseDetailFetchTimeout)` (15s) and mapped `TimeoutException` to a user-facing `Exception` string.
- Extended `PurchaseDetailPage` with optional `seedPurchase` (same id as route). While the provider is `loading`, the page renders `_LoadedPurchaseScaffold` with `showRefreshBanner: true` when a valid seed is present.
- `GoRouter` `pageBuilder` reads `state.extra` when it is a `TradePurchase` and forwards it to `PurchaseDetailPage` (`flutter_app/lib/core/router/app_router.dart`).
- High-trust navigations now pass `extra: p` on `context.push` / `context.go` where a `TradePurchase` exists (history list, ledgers, catalog purchase history, post-save flows).

## Verification

- Save a new purchase, tap **View details**: body should appear immediately from seed; banner clears when GET completes.
- Airplane mode on detail: within ~15s see inline `FriendlyLoadError` with message from the thrown `Exception`, not a blank skeleton.
- Pull-to-refresh on detail still invalidates `tradePurchaseDetailProvider`.
