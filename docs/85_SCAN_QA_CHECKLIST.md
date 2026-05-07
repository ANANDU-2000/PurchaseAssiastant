# 85 — SCAN_QA_CHECKLIST

## Must-pass (critical success)
The note must parse to:
- Supplier: **Surag**
- Broker: **kkk**
- Item: **Sugar 50kg**
- Qty: **100 bags**
- Purchase rate: **57**
- Selling rate: **58**
- Delivered rate: **56**
- Payment days: **7**

## Test matrix
### Handwriting quality
- clean handwriting
- bad handwriting
- mixed handwriting + printed

### Languages
- English
- Malayalam
- Manglish
- mixed Malayalam+English

### Image conditions
- blurred
- tilted / perspective
- low light
- partial paper crop

### Content complexity
- single item
- multiple items
- mixed pack types (bag+box+tin)
- shorthand rates (`57 58`, `P56 S57`)

### Network + reliability
- slow network (polling should keep UI alive)
- temporary 502/504
- automated: `pytest tests/scanner_v3/test_fallback_parse.py` (deterministic parse from OCR text)
- OCR provider disabled (should return partial review)
- retry parse without reupload (planned)

## UX acceptance
- No fake “No internet” unless truly offline.
- No “Scan failed” dead-end; always show a review screen.
- Low-confidence fields highlighted; user can edit and create purchase.

