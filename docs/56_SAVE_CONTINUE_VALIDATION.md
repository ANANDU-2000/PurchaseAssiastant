# 56 — SAVE_CONTINUE_VALIDATION

## Goal
Saving must be blocked only by explicit reasons, and users must be guided to fix them.

## Flutter
- Reasons provider:
  - `purchaseStepBlockReasonsProvider` in
    `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`
- Wizard behavior:
  - Continue stays enabled; clicking surfaces reasons
  - `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

## Backend
- Schema constraints reject invalid payloads:
  - `backend/app/schemas/trade_purchases.py`

