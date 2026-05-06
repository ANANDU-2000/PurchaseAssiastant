# 21 — Release Checklist

Before release:

- Backend:
  - `pytest backend/tests -q` green
  - No schema drift between SQLite tests and Postgres prod
  - Duplicate prevention verified (409 + force flow)
- Flutter:
  - `flutter analyze` 0 errors/warnings
  - `flutter test` green
  - No overflow on iPhone 16 Pro (portrait) and text scale 1.15
- Functional:
  - BAG: shows `kg • bags`
  - BOX: shows boxes only (no kg)
  - TIN: shows tins only (no kg)
  - Reports totals match saved purchases
  - PDF table includes Purchase + Selling rate columns
  - Scanner: preview-confirm-save; no auto-save
- Ops:
  - API keys configured (OpenAI / OCR)
  - Rate limits enabled

