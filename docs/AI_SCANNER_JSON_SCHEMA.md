# AI Purchase Scanner V2 — JSON Schema

This is the **canonical** wire format for both scan response and confirm request body.

---

## Top-level

```jsonc
{
  "supplier": SupplierMatch,
  "broker":   BrokerMatch | null,
  "items":    [ItemRow, …],
  "charges":  Charges,
  "broker_commission": BrokerCommission | null,
  "payment_days": number | null,

  "totals": {
    "total_bags": number,
    "total_kg":   number,
    "total_amount": number
  },

  "confidence_score": number,        // 0..1
  "needs_review":     boolean,
  "warnings":         [Warning, …],

  "scan_token":       string,        // HMAC; required for /confirm
  "scan_meta": {
    "provider_used":  string | null,
    "failover":       [{provider:string, ok:boolean, reason?:string}, …],
    "parse_warnings": [string, …],
    "ocr_chars":      number,
    "image_bytes_in": number
  }
}
```

## SupplierMatch & BrokerMatch

```jsonc
{
  "raw_text":     string,            // exactly what the OCR/LLM saw
  "matched_id":   uuid | null,
  "matched_name": string | null,
  "confidence":   number,            // 0..1, derived from rapidfuzz score / 100
  "match_state":  "auto" | "needs_confirmation" | "unresolved",
  "candidates":   [                  // top-3 alternatives (for "Did you mean?")
    {"id": uuid, "name": string, "confidence": number}, …
  ]
}
```

## ItemRow

```jsonc
{
  "raw_name":                  string,
  "matched_catalog_item_id":   uuid | null,
  "matched_name":              string | null,
  "confidence":                number,            // 0..1
  "match_state":               "auto" | "needs_confirmation" | "unresolved",
  "candidates":                [{id, name, confidence}, …],

  "unit_type":                 "BAG"|"BOX"|"TIN"|"KG"|"PCS"|"LTR"|"SACK",
  "weight_per_unit_kg":        number | null,    // e.g. 50 for sugar 50 kg bag
  "bags":                      number | null,    // count of bags/boxes/tins
  "total_kg":                  number | null,
  "qty":                       number | null,    // canonical qty in unit_type units (= bags when unit_type=BAG)

  "purchase_rate":             number | null,
  "selling_rate":              number | null,
  "line_total":                number | null,    // server-computed; client displays only

  "delivered_rate":            number | null,    // per-line override (rare)
  "billty_rate":               number | null,
  "freight_amount":            number | null,
  "discount":                  number | null,
  "tax_percent":               number | null,
  "notes":                     string | null
}
```

> **Bag/qty rule.** When `unit_type = BAG`, `qty == bags`. When `unit_type = KG`, `qty == total_kg` and `bags / weight_per_unit_kg` are typically null.

## Charges (header-level)

```jsonc
{
  "delivered_rate":   number | null,
  "billty_rate":      number | null,
  "freight_amount":   number | null,
  "freight_type":     "included" | "separate" | null,
  "discount_percent": number | null
}
```

## BrokerCommission

```jsonc
{
  "type":  "percent" | "fixed_per_unit" | "fixed_total",
  "value": number,
  "applies_to": "kg" | "bag" | "box" | "tin" | "once" | null
}
```

`applies_to` is required when `type == "fixed_per_unit"`. Otherwise null. Mirrors the existing wizard's commission UI in [purchase_terms_only_step.dart](../flutter_app/lib/features/purchase/presentation/wizard/purchase_terms_only_step.dart).

## Warning

```jsonc
{
  "code":       string,         // e.g. BAG_COUNT_MISMATCH
  "severity":   "info"|"warn"|"blocker",
  "target":     string | null,  // dotted path, e.g. "items[2].bags"
  "message":    string,
  "suggestion": string | null,
  "params":     object | null
}
```

---

## Confirm-save request

`POST /v1/me/scan-purchase-v2/confirm`

```jsonc
{
  "scan_token":      string,    // returned by /scan-purchase-v2
  "business_id":     uuid,
  "force_duplicate": boolean,   // default false
  "purchase_date":   string,    // ISO yyyy-mm-dd; client decides default
  "payload":         <ScanResult shape but with edits applied>
}
```

Server response on success:

```jsonc
{
  "trade_purchase_id": uuid,
  "human_id":          string,   // e.g. PUR-2026-0001
  "warnings":          [Warning, …]
}
```

---

## Correction request (alias learning)

`POST /v1/me/scan-purchase-v2/correct`

```jsonc
{
  "scan_token":  string,
  "business_id": uuid,
  "corrections": [
    {
      "type":     "supplier" | "broker" | "item",
      "raw_text": string,             // what AI saw
      "ref_id":   uuid                // user's confirmed pick
    }, …
  ]
}
```

Server upserts rows into `catalog_aliases` ([backend/app/models/ai_engine.py](../backend/app/models/ai_engine.py)) with `business_id`, `alias_type`, `ref_id`, normalized name. Idempotent.

---

## Pydantic equivalents (server)

`backend/app/services/scanner_v2/types.py` defines these as Pydantic models. Source-of-truth field names exactly mirror the JSON keys above. We use `Decimal` for money and `int`/`Decimal` for kg/bags. Wire encoding emits `Decimal` as JSON numbers (precision-safe up to 2 decimals; rounding by `decimal_precision.quantize_money`).

---

## JSON Schema (draft-07) — authoritative for tests

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ScanResult",
  "type": "object",
  "required": ["supplier","items","charges","confidence_score","needs_review","warnings","scan_token","scan_meta"],
  "additionalProperties": false,
  "properties": {
    "supplier":          {"$ref":"#/definitions/Match"},
    "broker":            {"oneOf":[{"$ref":"#/definitions/Match"},{"type":"null"}]},
    "items":             {"type":"array","items":{"$ref":"#/definitions/Item"}},
    "charges":           {"$ref":"#/definitions/Charges"},
    "broker_commission": {"oneOf":[{"$ref":"#/definitions/Commission"},{"type":"null"}]},
    "payment_days":      {"type":["integer","null"],"minimum":0,"maximum":365},
    "totals":            {"type":"object"},
    "confidence_score":  {"type":"number","minimum":0,"maximum":1},
    "needs_review":      {"type":"boolean"},
    "warnings":          {"type":"array","items":{"$ref":"#/definitions/Warning"}},
    "scan_token":        {"type":"string"},
    "scan_meta":         {"type":"object"}
  },
  "definitions": {
    "Match": {
      "type":"object",
      "required":["raw_text","matched_id","matched_name","confidence","match_state"],
      "properties":{
        "raw_text":{"type":"string"},
        "matched_id":{"oneOf":[{"type":"string","format":"uuid"},{"type":"null"}]},
        "matched_name":{"type":["string","null"]},
        "confidence":{"type":"number","minimum":0,"maximum":1},
        "match_state":{"enum":["auto","needs_confirmation","unresolved"]},
        "candidates":{"type":"array"}
      }
    },
    "Item": {
      "type":"object",
      "required":["raw_name","unit_type","match_state","confidence"],
      "properties":{
        "raw_name":{"type":"string"},
        "matched_catalog_item_id":{"oneOf":[{"type":"string","format":"uuid"},{"type":"null"}]},
        "matched_name":{"type":["string","null"]},
        "confidence":{"type":"number","minimum":0,"maximum":1},
        "match_state":{"enum":["auto","needs_confirmation","unresolved"]},
        "unit_type":{"enum":["BAG","BOX","TIN","KG","PCS","LTR","SACK"]},
        "weight_per_unit_kg":{"type":["number","null"]},
        "bags":{"type":["number","null"]},
        "total_kg":{"type":["number","null"]},
        "qty":{"type":["number","null"]},
        "purchase_rate":{"type":["number","null"]},
        "selling_rate":{"type":["number","null"]},
        "line_total":{"type":["number","null"]},
        "delivered_rate":{"type":["number","null"]},
        "billty_rate":{"type":["number","null"]},
        "freight_amount":{"type":["number","null"]},
        "discount":{"type":["number","null"]},
        "tax_percent":{"type":["number","null"]},
        "notes":{"type":["string","null"]}
      }
    },
    "Charges": {
      "type":"object",
      "properties":{
        "delivered_rate":{"type":["number","null"]},
        "billty_rate":{"type":["number","null"]},
        "freight_amount":{"type":["number","null"]},
        "freight_type":{"enum":["included","separate",null]},
        "discount_percent":{"type":["number","null"]}
      }
    },
    "Commission": {
      "type":"object",
      "required":["type","value"],
      "properties":{
        "type":{"enum":["percent","fixed_per_unit","fixed_total"]},
        "value":{"type":"number"},
        "applies_to":{"enum":["kg","bag","box","tin","once",null]}
      }
    },
    "Warning": {
      "type":"object",
      "required":["code","severity","message"],
      "properties":{
        "code":{"type":"string"},
        "severity":{"enum":["info","warn","blocker"]},
        "target":{"type":["string","null"]},
        "message":{"type":"string"},
        "suggestion":{"type":["string","null"]},
        "params":{"type":["object","null"]}
      }
    }
  }
}
```

The `backend/tests/scanner_v2/test_pipeline_e2e.py` validates every response against this schema.
