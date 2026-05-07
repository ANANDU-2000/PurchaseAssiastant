# 96 — PACKAGE_DETECTION_ENGINE

## Goal

Infer unit + package size from trader item text.

Examples:

- `Sugar 50kg` → `unit=BAG`, `weight_per_unit_kg=50`
- `Ruchi Oil Tin` → `unit=TIN`
- `Sunrich 400gm Box` → `unit=BOX`, `weight_per_unit_kg=0.4` (when supported)

## Backend logic (today)

- Unit detection + normalization:
  - `backend/app/services/scanner_v2/bag_logic.py`
- Totals:
  - bag × kg-per-bag → kg

## Requirements

- If weight-per-unit is present and qty is present, auto-compute totals.
- If only one is present, keep partial success and highlight missing input.

