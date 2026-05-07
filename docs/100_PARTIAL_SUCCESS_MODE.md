# 100 — PARTIAL_SUCCESS_MODE

## Goal

If 40% is parsed, open review with 40% — never discard the scan.

## Definition

“Partial success” means:

- OCR produced *some* text OR
- deterministic parsing found *any* meaningful field OR
- semantic parse found at least one item/field

## Rules

- **Never show empty review** if any signal exists.
- If OCR is empty, still open review with:
  - image preview
  - empty editable fields
  - actionable message: “Couldn’t read text — please type supplier/items”

## Backend behavior

- Scanner v3 always maintains a `ScanResult` object during processing.
- Error codes (`scan_meta.error_code`) inform UX copy but must not block review unless the upload is corrupted.

