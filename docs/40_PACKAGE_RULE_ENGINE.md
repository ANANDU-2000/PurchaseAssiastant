# 40 — PACKAGE_RULE_ENGINE

## Goal
Enforce the **only allowed package units** for new entries: `kg`, `bag`, `box`, `tin`, and make the bag/box/tin behaviors deterministic.

## Canonical classification
- Flutter: `UnitClassifier.classify(...)` in `flutter_app/lib/core/utils/unit_classifier.dart`
  - Parses `NN KG` tokens for bag items and returns `UnitType.weightBag`.
- Backend: `classify_unit_type(...)` + `parse_kg_per_bag_from_name(...)` in `backend/app/services/trade_unit_type.py`

## Rules (production rebuild)
- **BAG**: weight-carrying, supports \(qty \times kgPerBag\) for kg totals.
- **BOX/TIN**: **count-only** (no kg totals, no kg display).
- **KG**: loose weight line; qty itself is kg.

## Single source of truth (totals)
- Flutter totals: `computeTradeTotals(...)` in `flutter_app/lib/core/calc_engine.dart`
- Backend totals: `compute_totals(...)` in `backend/app/services/trade_purchase_service.py`

