# 57 — REALTIME_REPORT_UPDATES

## Goal
After saving a purchase, reports/ledgers reflect the updated totals.

## Mechanism
- Mutations call `invalidatePurchaseWorkspace(ref)`:
  - `flutter_app/lib/core/providers/business_aggregates_invalidation.dart`
- Screens watch providers that recompute from API snapshots.

## Validation
- Manual: save purchase → open Reports/History without pull-to-refresh.

