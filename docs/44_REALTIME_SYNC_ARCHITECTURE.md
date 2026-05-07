# 44 — REALTIME_SYNC_ARCHITECTURE

## Goal
After create/edit/delete, Home/Reports/History/Detail pages refresh without manual reload.

## Flutter invalidation helper
- `invalidatePurchaseWorkspace(ref)` in:
  - `flutter_app/lib/core/providers/business_aggregates_invalidation.dart`

## Typical usage sites
- Purchase wizard save / edit flows:
  - `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`
- Purchase detail delete/edit:
  - `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`

## Expected behavior
- Mutation triggers invalidation of dashboard KPIs + reports providers + ledgers.

