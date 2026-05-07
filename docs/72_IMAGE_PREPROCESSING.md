# 72 — IMAGE_PREPROCESSING

## Goal
Make handwriting and faint ink OCR-friendly before running OCR.

## Backend preprocessing
- Module: `backend/app/services/scanner_v2/preprocess.py`
- Entry point: `preprocess_variants(image_bytes) -> list[PreprocessVariant]`

## Current variants
- `orig_norm`: EXIF orientation + size cap + JPEG normalize
- `gray_norm`: grayscale + min/max normalization
- `clahe`: contrast-limited adaptive histogram equalization (faint pencil / uneven lighting)
- `denoise_sharp`: denoise + sharpen kernel
- `adaptive_thr`: adaptive threshold for handwriting separation

## Failure policy
Preprocessing is **best-effort** and must never crash scanning:
- If anything fails, OCR falls back to original bytes.

