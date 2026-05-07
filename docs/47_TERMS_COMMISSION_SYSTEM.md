# 47 — TERMS_COMMISSION_SYSTEM

## Goal
Broker commission must be explicit and consistent across Flutter + backend totals.

## Supported modes
- `percent` — % of line total after header discount
- `flat_invoice` — fixed ₹ once per bill
- `flat_kg` — ₹ × total kg (bag-only kg aggregation)
- `flat_bag` — ₹ × total bag qty (bag/sack only)
- `flat_box` — ₹ × total box qty (box only)
- `flat_tin` — ₹ × total tin qty (tin only)

## Flutter SSOT
- `headerCommissionAddOnDecimal(...)` in `flutter_app/lib/core/calc_engine.dart`
- Terms UI:
  - `brokerFigureUiOptions(...)` in `flutter_app/lib/features/purchase/domain/purchase_draft.dart`
  - `flutter_app/lib/features/purchase/presentation/wizard/purchase_terms_only_step.dart`

## Backend SSOT
- `_header_commission_rupees(...)` in `backend/app/services/trade_purchase_service.py`
- Schema allowlist:
  - `commission_mode` pattern in `backend/app/schemas/trade_purchases.py`

## PDF display
- Broker block and label strings:
  - `flutter_app/lib/core/services/purchase_invoice_pdf_layout.dart`

