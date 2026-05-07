# 91 — MULTIPASS_OCR_ARCHITECTURE

## Goal

Handwritten trader notes frequently require **multiple OCR passes** because:

- different preprocess variants recover different lines
- some engines read numbers well but miss names (and vice-versa)
- layout can break on tilted paper / shadows

## Current implementation (baseline)

- Preprocess variants: `backend/app/services/scanner_v2/preprocess.py`
- OCR engines: Google Vision (when enabled) + Gemini fallback
- OCR orchestration: `backend/app/services/purchase_scan_service.py`

## Required multipass strategy

For each input image:

- Generate variants (orig + contrast + CLAHE + threshold)
- Run OCR across variants and engines
- Keep a pool of top candidates
- **Merge lines** (dedupe normalized line keys)
- Score merged text and return it even if no single candidate was “perfect”

## Output contract

Scanner v3 stores OCR in memory cache:

- `job.ocr_text` (merged best-effort)
- `scan_meta.ocr_chars` (signal strength)
- `scan_meta.failover` (which engines/variants contributed)

## Failure policy

- Never “all or nothing”:
  - If OCR returns partial text, proceed to semantic + deterministic parse.
  - Only mark `OCR_EMPTY` when merged text is empty/whitespace.

