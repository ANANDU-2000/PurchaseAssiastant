# 102 — IMAGE_PREPROCESSING

## Goal

Improve OCR for:

- shadows
- low light
- tilted paper
- blur
- partial paper

## Pipeline (required)

Generate multiple JPEG variants:

- **orig**: original (resized)
- **contrast**: brightness/contrast normalization
- **sharpen**: handwriting stroke emphasis
- **denoise**: remove grain while preserving edges
- **adaptive threshold**: for high-contrast ink
- **CLAHE**: improve local contrast
- **(optional)** perspective correction when paper boundary is detected

## Implementation

- Variants are produced in:
  - `backend/app/services/scanner_v2/preprocess.py::preprocess_variants`
- Scanner v3 uses OCR multipass across these variants.

## Output

The OCR layer must merge lines across variants (see `docs/91_MULTIPASS_OCR_ARCHITECTURE.md`).

