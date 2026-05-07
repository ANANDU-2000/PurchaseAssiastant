# 41 — RATE_MODE_SYSTEM

## Goal
Make BAG pricing unambiguous between:
- ₹/kg (weight-priced)
- ₹/bag (pack-priced)

## Flutter
- Line math: `lineMoney(...)` / `lineMoneyDecimal(...)` in `flutter_app/lib/core/calc_engine.dart`
  - Weight-priced path uses `kgPerUnit` + `landingCostPerKg`.
- Line UI / draft behavior (rate mode selection and payload):
  - `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart`
  - `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`

## Backend
- Schema pairing rule: `TradePurchaseLineIn._normalize_decimal_precision` enforces:
  - `kg_per_unit` and `landing_cost_per_kg` must be both set or both omitted
  - File: `backend/app/schemas/trade_purchases.py`

## Expected outcomes
- Same line total when the two modes are consistent:
  - \(bags \times kgPerBag \times ₹/kg = bags \times ₹/bag\)

