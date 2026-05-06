# AI Scan Flow (v2)

## Goal
Photo → AI understands wholesale purchase automatically.

## User flow (mobile)
- **Empty**: Hero scan card with `Camera` + `Gallery`
- **After image selected**: Full-width image preview
- **Processing**: staged progress
  - Reading image → Detecting rows → Matching suppliers → Validating → Building draft
- **Success**: table-first review (supplier/broker + items table + charges)
- **Error**: clear retry guidance (lighting/crop/retake)

## Backend flow
Image → OCR → extracted text → OpenAI structured parse → DB fuzzy matching → validation → `ScanResult` preview → user confirms → create purchase.

## Non-goals
- No raw OCR dump in the main UI.
- No manual empty forms before AI result.

