# 13 — Error Handling (UX + API Codes)

## Principles

- Friendly error copy
- Clear recovery path (Retry / Edit / Open existing)
- No raw stack traces or `DioException` dumps

## Key error classes

- OCR fail / blurry / empty image
- AI parse fail (malformed JSON)
- DB mismatch / unresolved match
- Validation blockers
- Duplicate purchase (409)
- Timeout / provider outage

## Recovery

- Always offer “Type manually” when scan fails.
- On duplicate, offer “Open existing”.

