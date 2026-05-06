# AI Purchase Scanner V2 — Validation Engine

The validator is a pure function:

```python
validate(scan_result: ScanResult, ctx: ValidationCtx) -> list[Warning]
```

It runs **server-side** during scan AND during confirm-save. The client also runs a JS-equivalent subset for instant feedback, but the server's verdict is authoritative.

`Warning` shape:

```json
{
  "code": "BAG_COUNT_MISMATCH",
  "severity": "blocker|warn|info",
  "target": "items[2].bags",
  "message": "Bag count 100 × 50 kg ≠ total 4500 kg.",
  "suggestion": "Set total_kg=5000 or bags=90.",
  "params": {"bags": 100, "weight_per_unit_kg": 50, "total_kg": 4500}
}
```

`severity` semantics:

- **blocker** — `/confirm` will return 422 if any present.
- **warn** — surfaced amber; user must acknowledge to save.
- **info** — green/neutral; informational only.

---

## The 13 rules

### V-01. `BAG_COUNT_MISMATCH` (blocker)
- **Trigger:** `unit_type ∈ {BAG, BOX, TIN}` AND `weight_per_unit_kg > 0` AND `bags > 0` AND `total_kg > 0` AND `abs(bags * weight_per_unit_kg - total_kg) > 1`.
- **Reason:** Bag math must reconcile or the report breaks.
- **Suggestion:** auto-fix candidates `bags=round(total_kg/wpu)` or `total_kg=bags*wpu`.

### V-02. `KG_MISMATCH` (blocker)
- **Trigger:** `unit_type == KG` AND `qty != total_kg` (when both present).
- **Reason:** For KG unit, qty is already kg.

### V-03. `DUPLICATE_ITEM_ROW` (warn)
- **Trigger:** Two `items[]` rows resolve to the same `matched_catalog_item_id` AND same `unit_type`.
- **Suggestion:** merge rows.

### V-04. `DUPLICATE_PURCHASE_SUSPECT` (warn at scan, blocker only on confirm without `force_duplicate`)
- **Trigger:** Duplicate detector returns suspects. See `AI_SCANNER_DUPLICATE_PREVENTION.md`.

### V-05. `IMPOSSIBLE_RATE` (blocker)
- **Trigger:** `purchase_rate <= 0` OR `purchase_rate > 1_000_000` OR `selling_rate < purchase_rate * 0.5` OR `selling_rate > purchase_rate * 5` (last two are warn, not blocker; configurable).
- **Reason:** Catch OCR digit-swap errors (e.g. `560` read as `5.6`).

### V-06. `MISSING_SUPPLIER` (blocker)
- **Trigger:** `supplier.matched_id is None` AND status != "unresolved-allowed".
- **Note:** Server allows `force_unresolved_supplier=false`; UI must require user to pick.

### V-07. `UNRESOLVED_BROKER` (warn)
- **Trigger:** `broker.raw_text` non-empty AND `broker.matched_id is None`.
- **Reason:** Broker is optional; we warn so user can either link or clear.

### V-08. `MISSING_QUANTITY` (blocker)
- **Trigger:** Any `items[i].bags == 0 AND total_kg == 0 AND qty == 0`.

### V-09. `WRONG_UNIT_TYPE` (blocker)
- **Trigger:** `unit_type` set to value AND catalog item's `default_unit` exists AND they conflict (e.g. catalog says BAG but scan says PCS) without explicit user override.
- **Mitigation:** UI offers "Use catalog default" button.

### V-10. `ZERO_KG` (warn)
- **Trigger:** `total_kg == 0` for a non-PCS item.

### V-11. `NEGATIVE_AMOUNT` (blocker)
- **Trigger:** Any `line_total < 0`, `total_amount < 0`, or any rate < 0.

### V-12. `MALFORMED_RATE` (blocker)
- **Trigger:** Rate is not a number, contains non-numeric chars, or has > 2 decimal places.

### V-13. `OCR_CORRUPTION` (warn)
- **Trigger:** Heuristic — OCR text contains > 30 % characters outside `[a-zA-Z0-9 .,/\-:%₹\u0D00-\u0D7F\n]` for the section that matched a numeric field.

---

## Cross-field consistency checks (auxiliary, severity warn)

- **`A-01 LINE_TOTAL_DRIFT`** — server-recomputed `line_total` differs from incoming `line_total` by > ₹1.
- **`A-02 GRAND_TOTAL_DRIFT`** — sum of `line_total` differs from `total_amount` by > ₹1.
- **`A-03 COMMISSION_OUT_OF_RANGE`** — `broker_commission.value < 0` or > 100 % or > ₹1000/kg etc.
- **`A-04 PAYMENT_DAYS_OUT_OF_RANGE`** — `payment_days < 0` or > 365.

---

## Run order

```
parse → matcher → bag_logic.normalize() → validators → duplicate_detector
```

`bag_logic.normalize` may **derive** `bags` or `total_kg` from one another when only one is given. Validators run **after** normalization so we don't false-positive.

---

## Implementation

`backend/app/services/scanner_v2/validators.py`:

```python
from __future__ import annotations

from typing import Iterable
from app.services.scanner_v2.types import ScanResult, Warning

def validate(scan: ScanResult, ctx) -> list[Warning]:
    out: list[Warning] = []
    out.extend(_validate_supplier(scan, ctx))
    out.extend(_validate_broker(scan, ctx))
    for idx, item in enumerate(scan.items):
        out.extend(_validate_item(idx, item, scan, ctx))
    out.extend(_validate_totals(scan))
    return out
```

Tests in `backend/tests/scanner_v2/test_validators.py` create one fixture per code and assert the exact `code`, `severity`, and `target`.

---

## Client-side mirror

`flutter_app/lib/features/purchase/state/scan_v2_validators.dart` re-implements V-01, V-02, V-08, V-11, V-12 for instant in-cell error indication. Server response is the source of truth on save.
