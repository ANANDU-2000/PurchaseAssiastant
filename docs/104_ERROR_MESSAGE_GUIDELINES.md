# 104 — ERROR_MESSAGE_GUIDELINES

## Rule

No generic errors:

- ❌ “Scan failed”
- ❌ “Something went wrong”
- ❌ “No internet” (unless confirmed offline)

## Use typed error hints

Backend sends:

- `scan_meta.error_stage`: `ocr|parse|match|validate|scan`
- `scan_meta.error_code`: stable code for UX copy

Suggested codes:

- `LOW_LIGHT_DETECTED`
- `OCR_EMPTY`
- `OCR_FAILED`
- `PARSE_EMPTY`
- `SUPPLIER_UNRESOLVED`
- `BROKER_UNRESOLVED`
- `ITEMS_NEED_CONFIRMATION`
- `RATES_NEED_CONFIRMATION`

## UX copy style

- Explain what happened in trader language
- Give a next step

Examples:

- “Low light detected — retake in brighter light or continue and edit fields.”
- “Items need confirmation — tap the row to correct qty/unit.”

