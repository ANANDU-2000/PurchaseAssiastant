# 80 — SCAN_LOADING_STATES

## Goal
Replace frozen/fake loading with a realtime staged flow.

## Backend stages (scanner v3)
Published as `scan_meta.stage`:
- `preparing_image`
- `uploading`
- `extracting_text`
- `parsing_items`
- `matching`
- `validating`
- `ready`
- `error`

Source:
- `backend/app/services/scanner_v3/pipeline.py`
- `backend/app/services/scanner_v2/types.py` (`ScanMeta.stage`, `stage_progress`, `stage_log`)

## Flutter
- Uses `start` + `status` polling and maps stage → UI copy:
  - `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`

