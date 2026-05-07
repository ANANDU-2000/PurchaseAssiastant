# 59 — ERROR_BORDER_SYSTEM

## Goal

Errors are visible and actionable:

- error copy explains the missing value
- field is highlighted (where supported)
- user is navigated to the right step/field

## Current behavior

- Purchase wizard uses “block reasons” to prevent silent failure:
  - `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`
  - `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`