# 05 — AI Scanner (OCR → Parse → Match → Validate → Preview → Confirm)

This doc supersedes earlier scanner drafts for unit semantics. The scanner must output package-aware drafts aligned with:
- `01_PACKAGE_ENGINE.md`
- `03_DYNAMIC_FORM_RULES.md`
- `06_VALIDATION_RULES.md`
- `07_DUPLICATE_PREVENTION.md`

## Supported inputs

- Handwritten notes (Malayalam / English / Manglish / mixed)
- WhatsApp screenshots
- Scanned printed bills

## Pipeline

1. Image upload from Flutter
2. OCR extraction (Google Vision preferred; fallback OpenAI vision)
3. OpenAI structured parse (JSON only)
4. DB fuzzy matching (supplier, broker, catalog)
5. Validation + conflict detection
6. Editable preview **table** (full viewport, no cards)
7. User confirms
8. Save as `trade_purchases` + `trade_purchase_lines`

## Output JSON (scanner draft)

Minimum required fields:

```json
{
  "supplier_name": "SURAJ",
  "broker_name": "RIYAS",
  "payment_days": 7,
  "items": [
    {
      "item_name": "SUGAR 50KG",
      "package_type": "bag",
      "qty": 100,
      "weight_per_bag": 50,
      "total_kg": 5000,
      "purchase_rate": 56,
      "selling_rate": 57,
      "pricing_mode": "kg"
    }
  ],
  "delivered_rate": 36,
  "bilty_rate": 25,
  "freight": 1000
}
```

Notes:
- For `BOX` and `TIN` items, **do not output** `total_kg` unless advanced inventory mode is on.
- Confidence thresholds:
  - ≥92% auto-select
  - 70–91% ask user confirmation
  - <70% unresolved (must pick)

## Learning from corrections

On user correction (e.g. `suger` → `SUGAR 50KG`), upsert an alias in `catalog_aliases` scoped by `business_id`.

