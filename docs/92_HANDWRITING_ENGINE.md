# 92 — HANDWRITING_ENGINE

## Goal

Make handwritten notes parse reliably (including clean notes, messy notes, trader shorthand).

## Inputs to support

- Handwritten paper notes (phone photo)
- Printed bills
- WhatsApp screenshots
- Rotated / tilted / partial paper
- Shadows + low light + blur

## Handwriting-first preprocessing

See `docs/102_IMAGE_PREPROCESSING.md` for the full pipeline. Key emphasis:

- contrast boosting (ink vs paper)
- denoise without destroying strokes
- adaptive threshold variants
- perspective correction when possible

## OCR tactics

- Always run multi-variant OCR (never just “raw”)
- Prefer a merged text that keeps **numbers** + **names**
- Avoid discarding partial lines (they feed deterministic parsing)

## Parsing tactics for handwriting ambiguity

- Treat common confusions as normal:
  - `0/O`, `1/I`, `5/S`, `2/Z`, `8/B`
- Allow loose tokens:
  - `del`, `deliv`, `delivered`
  - `pay`, `payment`, `pd`
  - `bag`, `bags`, `bg`

## UX rules

- Never claim “handwriting unclear” as a blanket error.
- Instead: mark the specific field(s) as needing confirmation.

