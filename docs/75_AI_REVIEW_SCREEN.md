# 75 — AI_REVIEW_SCREEN

## Goal
Provide a professional trader-grade review UI even with partial scans:
- image preview at top
- supplier + broker match blocks
- structured items table
- charges + terms
- edit + confirm + create purchase

## Flutter
- Review screen: `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`
- Confidence chips + “Needs review” styling: driven by `ScanResult.confidence_score` and per-field confidence.

## Data contract
- Backend returns `ScanResult` (wire stable):
  - `backend/app/services/scanner_v2/types.py`

## Non-blocking rule
Even if scan is partial (`needs_review=true`), the UI must allow:
- manual edits
- confirm + create purchase

