# 45 — FORM_VALIDATION_ENGINE

## Goal
Continue is **never silently disabled**. Clicking Continue with errors:
1. Shows an error reason
2. Moves user to the first missing/invalid field

## Flutter
- Step gating computed (reasons are shown, not disabling the CTA):
  - `PurchaseStepBlockReasons` + `purchaseStepBlockReasonsProvider` in
    `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`
- Wizard navigation uses the reasons to guide the user:
  - `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

## Backend parity
- Header/line validators enforce:
  - Decimal-only wire inputs
  - Weight field pairing for bag ₹/kg mode
  - Allowed commission modes
  - File: `backend/app/schemas/trade_purchases.py`

