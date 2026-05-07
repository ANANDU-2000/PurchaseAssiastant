# 78 — CONFIDENCE_SYSTEM

## Goal
Every extracted field should carry a confidence so the UI can:
- highlight low-confidence values
- guide review without blocking flow

## Current signals
- Match confidence (supplier/broker/item):
  - `Match.confidence` in `backend/app/services/scanner_v2/types.py`
- Overall scan confidence:
  - `ScanResult.confidence_score`

## UI mapping
- Flutter uses 3 levels:
  - High: \( \ge 0.92 \)
  - Medium: \( \ge 0.70 \)
  - Needs review: below

File:
- `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`

## Next improvements
- Add per-field parse confidence (rates/qty/charges/payment_days) from the LLM and/or deterministic heuristics.

