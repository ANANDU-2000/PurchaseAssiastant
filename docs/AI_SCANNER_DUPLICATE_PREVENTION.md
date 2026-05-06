# AI Purchase Scanner V2 — Duplicate Prevention

We do not allow accidental duplicate purchases — they distort spend, supplier ledgers, broker commissions, and report KPIs. The detector runs **twice**:

1. **At scan time** — best-effort warning so the user sees a hint while editing.
2. **At confirm time** — authoritative; returns 409 unless `force_duplicate=true`.

Source of truth lives in `backend/app/services/scanner_v2/duplicate_detector.py` and reuses the existing logic in [trade_purchase_service.py](../backend/app/services/trade_purchase_service.py).

---

## 1. Inputs

```python
class DupCandidate(TypedDict):
    business_id: UUID
    purchase_date: date
    supplier_id: UUID | None
    broker_id: UUID | None
    total_amount: Decimal
    total_kg: Decimal | None
    item_keys: list[tuple[UUID, str, Decimal]]   # (catalog_item_id, unit_type, qty)
```

Supplier / broker IDs use the **matched** IDs from the matcher; if unresolved, the candidate is missing → cannot reliably duplicate-detect → emit info-level warning only.

---

## 2. Algorithm

```
Look up trade_purchases rows in the SAME workspace where:
   purchase_date == candidate.purchase_date
   AND (
     supplier_id == candidate.supplier_id
     OR (supplier_id IS NULL AND candidate.supplier_id IS NULL)
   )
For each match row M:
  total_amount_diff = abs(M.total_amount - candidate.total_amount)
  total_kg_diff_pct = abs(M.total_kg - candidate.total_kg) / max(M.total_kg, candidate.total_kg)
  jaccard = jaccard_index(M.item_keys, candidate.item_keys)
  score = 0
  if total_amount_diff <= 1.0:           score += 0.5
  if total_kg_diff_pct <= 0.01:          score += 0.3
  if jaccard >= 0.7:                     score += 0.2
  if score >= 0.7: emit suspect (M)
```

We then return the suspects sorted desc by score, with their `human_id`, `id`, date, amount, top items.

### Jaccard on item keys

```
A = set( (catalog_item_id, unit_type, qty_rounded) for each line in row )
B = set( same for candidate )
J = |A ∩ B| / |A ∪ B|
```

`qty_rounded` rounds to nearest 1 (bag/box/tin) or nearest 1 kg for KG units to absorb minor edits.

### Tolerance bands

- Amount: ± ₹1.0 (matches existing `trade_purchase_service` band).
- Total kg: ± 1 % of the larger value (catches re-entered same purchase).
- Jaccard ≥ 0.7 (most lines overlap).

These thresholds are configurable through Settings (`dup_amount_tolerance_inr`, `dup_kg_tolerance_pct`, `dup_jaccard_threshold`) for ops tuning. Defaults are above.

---

## 3. Behaviour & UI

### At scan time

- The pipeline calls `find_duplicates(candidate)` after validators.
- Suspects are surfaced as **warning** entries with code `DUPLICATE_PURCHASE_SUSPECT`, severity `warn`, `params={"suspects": [{id, human_id, total_amount, purchase_date, items_count}, …]}`.
- UI shows the warnings strip; user is informed but **not blocked**.

### At confirm time

- Detector runs again. If suspects exist:
  - if `force_duplicate=false` (default): respond `409 DUPLICATE_PURCHASE`.
  - if `force_duplicate=true`: proceed to save.
- On 409 the UI opens the duplicate-modal:

```
┌──────────────────────────────────────────────────┐
│  Possible duplicate purchase                     │
│                                                  │
│  We found 1 similar purchase on 06 May 2026:     │
│   PUR-2026-0014 · ₹4,04,000 · 7 items            │
│                                                  │
│  [ Open existing ] [ Cancel ] [ Save anyway ]    │
└──────────────────────────────────────────────────┘
```

"Save anyway" re-issues confirm with `force_duplicate=true`. We log the override for audit.

---

## 4. SQL implementation

```python
async def find_duplicates(db, c: DupCandidate) -> list[Suspect]:
    rows = (await db.execute(
        select(TradePurchase).where(
            TradePurchase.business_id == c.business_id,
            TradePurchase.purchase_date == c.purchase_date,
            (TradePurchase.supplier_id == c.supplier_id) if c.supplier_id else (TradePurchase.supplier_id.is_(None)),
        ).options(selectinload(TradePurchase.lines))
    )).scalars().all()

    out: list[Suspect] = []
    for r in rows:
        s = score(r, c)
        if s >= 0.7:
            out.append(Suspect.from_row(r, score=s))
    return sorted(out, key=lambda x: -x.score)
```

We use `selectinload` rather than N+1 line lookups.

---

## 5. Edge cases

- **No supplier matched yet**: detector skips date+supplier filter and only checks `(business_id, purchase_date, total_amount±1)` as a weak hint. Emits info-level warning.
- **Same date, different supplier**: not a dup.
- **Same supplier, different date**: not a dup.
- **Edits that lower amount**: dup may flip to non-dup. Detector re-runs at confirm so it always reflects the final payload.
- **Re-edited save (e.g. user edits an existing trade purchase via wizard)**: this scanner only creates new rows; updates use the existing wizard endpoints. We never collide.

---

## 6. Tests

`backend/tests/scanner_v2/test_duplicate_detector.py` covers:

- exact dup (same date, supplier, amount, kg, items) → suspect, score 1.0
- ±₹0.5 amount → still dup
- ±2 % kg → not dup (band exceeded)
- Jaccard 0.6 → not dup
- supplier mismatch → not dup
- date off-by-one → not dup
- `force_duplicate=true` end-to-end via confirm endpoint → row created
- supplier null on both → still considered (low confidence)

We add an integration test that asserts the existing `tradePurchasesListProvider` shows both rows when `force_duplicate=true` was used and the audit row was written.