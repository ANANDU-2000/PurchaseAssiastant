# 108 — MALAYALAM_HANDLING

## Goal

Support Malayalam handwriting and Manglish trader notes.

## Requirements

- OCR must not discard Malayalam Unicode text.
- Semantic parse prompt must mention:
  - Malayalam words may appear
  - mixed-language lines are normal
  - numbers/rates still must be extracted reliably

## Parsing rules

- Supplier/broker may be Malayalam:
  - treat any non-empty alphabetic line (Latin or Malayalam) as a name candidate
- Item may be Malayalam or mixed:
  - still detect pack size tokens like `50kg`, `25 kg`
- Units may be English abbreviations even inside Malayalam lines:
  - `bag`, `box`, `tin`, `kg`, `ltr`

## UX rule

- If Malayalam text is present but not confidently mapped:
  - show it in review as raw text and ask for confirmation

