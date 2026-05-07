# 42 — BAG_KG_CONVERSION

## Goal
Never treat **1 bag = 1 kg**. Bag kg must come from a real per-bag kg signal.

## Flutter
- Parse `NN KG` from item label:
  - `parseKgPerBagFromName(...)` in `flutter_app/lib/core/utils/unit_classifier.dart`
- Use derived kg in totals:
  - `ledgerTradeLineWeightKg(...)` in `flutter_app/lib/core/calc_engine.dart`
- Display:
  - Spec string: `formatPackagedQty(...)` in `flutter_app/lib/core/utils/line_display.dart`
  - Trade-line human string (used across pages): `formatLineQtyWeightFromTradeLine(...)` in `flutter_app/lib/core/utils/line_display.dart`

## Backend
- Bag kg fallback (when missing explicit weight):
  - `parse_kg_per_bag_from_name(...)` in `backend/app/services/trade_unit_type.py`
  - `_line_total_weight(...)` in `backend/app/services/trade_purchase_service.py`

## Tests
- Flutter: `flutter_app/test/package_rules_test.dart`
- Backend: `backend/tests/test_package_rules.py`

