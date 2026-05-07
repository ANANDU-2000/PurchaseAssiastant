# 52 — PACKAGE_CLASSIFICATION

## Goal
Given an item name and selected unit, consistently determine the pack kind.

## Flutter
- `UnitClassifier.classify(...)`:
  - `flutter_app/lib/core/utils/unit_classifier.dart`
- Bag kg auto-seed in item entry:
  - `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart`

## Backend
- `classify_unit_type(...)`:
  - `backend/app/services/trade_unit_type.py`

## Special cases
- `SUGAR 50 KG` + unit bag → bag with `per_bag_kg=50`
- Any `BOX` / `TIN` → count-only

