# 98 — PROGRESSIVE_VALIDATION_UI

## Goal

Replace dead spinners with a live, trader-trustworthy progress flow.

## Progress checklist (UI)

Displayed as a vertical list with checkmarks:

- Image uploaded
- Paper detected
- OCR extracting
- Supplier matched
- Broker matched
- Items identified
- Units identified
- Rates validated
- Quantity calculated
- Final review ready

## Backend source of truth

Scanner v3 publishes:

- `scan_meta.stage`
- `scan_meta.stage_progress`
- `scan_meta.stage_log`

Flutter must render from these fields (no fake timers).

## UX rules

- Always show the last successful step even when later steps fail.
- If an error occurs, show the specific step + a corrective suggestion.

