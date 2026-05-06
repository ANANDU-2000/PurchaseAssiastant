# Supplier Matching (v2)

## Inputs
- OCR raw supplier string (Malayalam/English/Manglish)

## Engine
- Normalization → fuzzy rank → confidence bucket → candidates list

## UI contract
- Show matched supplier when confidence high
- If not, show `Possible match` candidates and mark `needs_review`

## Learning
- When user corrects a match, store alias so future scans improve.

