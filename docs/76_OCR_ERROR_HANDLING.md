# 76 — OCR_ERROR_HANDLING

## Goal
Never show generic “No internet” / “Scan failed” when the real cause is OCR/parse.

## Typed errors
Backend emits typed error hints in `scan_meta`:
- `error_stage`: `ocr|parse|match|validate|scan`
- `error_code`: stable string (`OCR_EMPTY`, `OCR_FAILED`, `PARSE_EMPTY`, …)
- `error_message`: safe short message (no stack traces)

Source of truth:
- `backend/app/services/scanner_v2/types.py` (`ScanMeta`)

## UI mapping
Flutter maps `error_code` to trader-friendly copy:
- `OCR_EMPTY`: “Could not fully read handwriting…”
- `PARSE_EMPTY`: “Could not fully parse… you can still edit…”
- `OCR_FAILED`: “Text extraction failed… retake or enter manually.”

UI file:
- `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`

## Network vs timeout vs offline
- Scan uploads use **extended Dio timeouts** (`send`/`receive` 120s) in `hexa_api.dart` so large photos are not cut off at the default 20s receive window.
- **`shouldQueueScanOffline`** (`auth_error_messages.dart`): only true transport failures queue an offline job — **not** `receiveTimeout` / `sendTimeout` (those are surfaced as “timed out”, not “no internet”).
- **`friendlyApiError`**: receive/send timeouts return explicit timeout copy instead of generic “check your network”.

