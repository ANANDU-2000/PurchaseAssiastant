# OCR Pipeline (v2)

## Correct pipeline

1. **Image** uploaded from client (jpeg/png/webp)
2. **OCR engine** extracts text (never decode bytes to UI)
3. **LLM parse** converts text → strict JSON (`ScanResult`)
4. **Matching** supplier/broker/items with confidence + candidates
5. **Validation** flags impossible qty/rates/unit mismatches + duplicates
6. **Preview** returned to client (table-first)
7. **Confirm** creates the purchase (confirm-only save guarantee)

## Failure handling

- OCR empty → retry guidance + optional fallback extraction
- LLM malformed → retry / failover model
- Matching unresolved → candidates list for user confirmation