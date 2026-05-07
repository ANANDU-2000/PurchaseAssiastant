# 71 — AI_SCANNER_ARCHITECTURE

## Goals
- **Fast**: UI never blocks on one long request.
- **Reliable**: partial success always shows a review screen.
- **Realtime**: scan stages come from the backend (polling).
- **Trader-friendly**: structured preview, editable, confidence highlights.
- **Offline tolerant**: never lose a captured scan (queue + retry).

## Current implementation (v3)

### Backend
- **Start**: `POST /v1/me/scan-purchase-v3/start`
- **Status**: `GET /v1/me/scan-purchase-v3/status?scan_token=...`
- Pipeline + job cache:
  - `backend/app/services/scanner_v3/pipeline.py`
- Wire types (stable for UI):
  - `backend/app/services/scanner_v2/types.py` (`ScanResult`, `ScanMeta`, `ItemRow`, `Match`)

### Flutter
- Scanner page (start + poll, shows real stages + review table):
  - `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`
- API calls:
  - `flutter_app/lib/core/api/hexa_api.dart` (`scanPurchaseBillV3StartMultipart`, `scanPurchaseBillV3Status`)

## Stage model
Backend publishes `scan_meta.stage`:
- `preparing_image`
- `uploading`
- `extracting_text`
- `parsing_items`
- `matching`
- `validating`
- `ready`
- `error`

Flutter maps this to user-facing labels and never shows fake “No internet”.

## Parse resilience (v3)
- LLM output is merged with a **deterministic fallback** (`_fallback_parse_text` in `scanner_v3/pipeline.py`) when the model returns empty `items` or missing supplier/charges.
- Fallback understands trader shorthand: `57 58`, `P 57 S 58`, `Supplier: …`, `Payment days: 7`, `Sugar 50kg`, `100 bags`.

## OCR
- Multi-variant preprocessing + Vision/Gemini in `purchase_scan_service.image_bytes_to_text` (Vision HTTP timeout 120s).

