# Handwriting Parse Rules

## Inputs

- Malayalam / English / Manglish
- Mixed shorthand (broker notes)
- Noisy OCR, partial lines, missing separators

## Normalization

- Normalize whitespace, punctuation, common OCR confusions (0/O, 1/I, ₹, ., ,)
- Unit normalization to: `KG | BAG | BOX | TIN | PCS`

## Parsing heuristics

- Prefer explicit numeric patterns: qty, rate, kg/bag hints (e.g. `50KG`, `26 KG`)
- Detect package by keywords:
  - `BOX/CARTON` → BOX
  - `TIN/LTR` → TIN
  - `KG` + category rice/sugar/flour → BAG

## Output constraints

- Never invent rates/qty if missing; mark `needs_review` and provide candidates.