# AI Purchase — Strict Validation and DB Safety

Production-grade rules for the Purchase Assistant used by real wholesalers. **Financial and inventory correctness beat automation speed.**

Companion specs: [`AI_PURCHASE_DRAFT_ENGINE.md`](AI_PURCHASE_DRAFT_ENGINE.md), [`SCAN_GUIDE_UX_SPEC.md`](SCAN_GUIDE_UX_SPEC.md), [`05_AI_SCANNER.md`](05_AI_SCANNER.md).

---

## Core principle

**AI extraction is only a draft suggestion.** No value may affect `trade_purchases` / inventory until it passes normalization, matching, validation, duplicate checks, and explicit user confirmation.

Intended gate chain:

```
normalize → alias/DB match → confidence → financial validation → duplicate validation → user review → transactional write
```

---

## High-risk failure areas (burn down)

1. Wrong item match  
2. Wrong supplier match  
3. Wrong broker match  
4. Wrong unit conversion  
5. Wrong bag/kg calculation  
6. Duplicate item creation  
7. Duplicate supplier creation  
8. Incorrect totals  
9. Incorrect reports  
10. Incorrect profit calculation  
11. OCR / vision hallucination or invented lines  
12. Alias mismatch  
13. Multi-page merge failure  
14. Delivered rate confusion  
15. Purchase/selling rate swap  
16. Invalid quantity parsing  
17. Duplicate purchase save  
18. Frontend-only calculations  
19. Report aggregation mismatch  
20. Stale cache mismatch  

Shorter summary: wrong entity match, wrong units, duplicate data, bad totals, client-side truth, and cache drift.

---

## NEVER / ALWAYS

**NEVER**

- Trust raw OCR or raw model output as authoritative.
- Auto-create suppliers, brokers, or catalog items **silently** when confidence is low.
- Calculate purchase totals, margins, or report rollups **authoritatively** on the client.
- Overwrite immutable raw extraction snapshots.
- Create duplicate purchases or duplicate aliases without dedupe rules.
- Skip duplicate detection on save when business rules require it.

**ALWAYS**

- Normalize and score confidence before auto-binding entities.
- Validate units and conversions using **item master** data where weights apply (do not invent bag weights).
- Run server-side financial recomputation on the final payload before insert.
- Use transactions for writes; rollback on validation failure.
- Audit material changes (see Audit logging).

---

## Supplier match engine

If the supplier exists in DB → prefer match via:

- Normalized name + **aliases** (`supplier_aliases`)
- Fuzzy / trigram similarity
- Phone / GST when present
- Recent purchase history for this business

Examples that should converge: `surag`, `surg`, `suraj`, Malayalam variants (see draft engine — normalization dictionary).

### New supplier safety

If **confidence &lt; 0.80** (tunable): **do not** auto-create. UI: “Possible new supplier” → show top suggestions → user picks existing or explicitly creates new.

---

## Broker match engine

Same pattern as supplier: aliases, historical purchases, supplier–broker associations. Low confidence → require confirmation before save.

---

## Item match engine

Use:

- `item_aliases`, keywords, catalog trigram/fuzzy search
- Previous purchases and **supplier-specific** line history
- Malayalam / Manglish normalization (dictionary-backed)
- Typo correction (e.g. `suger` → `sugar`)
- Optional embedding similarity later; trigram is acceptable MVP

### Item creation safety

If no confident catalog match: **never** auto-create without user choice. Show suggestions → user selects existing or starts controlled “new item” flow with required fields.

### New item validation (before create)

Require at minimum: name, base unit, inventory semantics, conversion rules (e.g. kg per bag) where applicable.

---

## Unit validation engine

Supported wholesale units include: bag, kg, box, tin, packet, sack, litre, piece (extend in schema).

Normalize OCR/model variants:

- `bags`, `bg`, `bgs` → **bag**
- Consistent casing and spelling for ERP keys

---

## KG / bag conversion rules

Most reporting bugs come from bad conversion.

Example intent: **100 bags × 50 kg/bag = 5000 kg**.

Rules:

- **`total_kg`** for bag lines should derive from **`qty × weight_per_unit_kg`** using **item master** when available.
- If master data missing → **flag for review**; do not guess a universal bag weight.

---

## Item master required fields (target)

Each catalog item should support: display name, **aliases[]**, base unit, bag weight (where relevant), conversion metadata, category, active flag — aligned with [`01_PACKAGE_ENGINE.md`](01_PACKAGE_ENGINE.md) if present.

---

## Financial calculation engine (backend only)

Compute on server from resolved lines + charges:

- Subtotal (lines)
- Freight, bilty, delivered-rate effects, discounts
- Broker commission (percent / fixed rules as per product)
- Final total, landed metrics, expected profit, margin %

**Delivered rate:** when present, apply documented landed-cost rules (prioritize consistency with existing `trade_purchase_service` / package engine).

### Rate validation

Warn or block:

- Negative rates
- Selling rate materially below purchase without override
- Impossible margins or spikes vs historical band (optional heuristic)

Frontend displays API numbers only.

---

## Duplicate purchase detection (implemented behavior)

Server-side creation uses `find_matching_duplicate_trade_purchase` in [`backend/app/services/trade_purchase_service.py`](../backend/app/services/trade_purchase_service.py): same business, date, supplier alignment, compares totals and line fingerprints, with fuzzy kg + catalog overlap heuristics. Conflicts raise **`DUPLICATE_PURCHASE_DETECTED`** unless `force_duplicate` is explicitly set.

Documentation-only: when adding AI draft saves, run the **same** conceptual checks before final insert.

---

## Report engine rules

Aggregations for finance reports must come from **`trade_purchase` line tables** (and related canonical tables), not from cached UI aggregates. Keep dashboard cache as **display-only**.

---

## AI extraction rules

Model returns **strict JSON only** — no markdown fences or commentary in production parsing path.

High-level shape (fields evolve — source of truth in code):

```json
{
  "supplier": {},
  "broker": {},
  "terms": {},
  "charges": {},
  "items": [],
  "totals": {},
  "warnings": [],
  "confidence": {}
}
```

See [`docs/AI_SCANNER_SPEC.md`](AI_SCANNER_SPEC.md) and [`backend/app/services/scanner_v2/prompt.py`](../backend/app/services/scanner_v2/prompt.py) for the live schema.

### Shortcodes (bill handwriting)

Train users via Scan Guide: **SUP**, **BRO**, **PD**, **DR**, **FR**, **BR** (bilty), **BC**, **BF**, **DS**, line-level **P** / **S** — avoid ambiguous single-letter codes (do not use **B** for both broker and bilty).

---

## Malayalam / Manglish

Normalize before match; maintain a growing dictionary (e.g. പഞ്ചസാര → sugar). Details in [`AI_PURCHASE_DRAFT_ENGINE.md`](AI_PURCHASE_DRAFT_ENGINE.md).

---

## Audit logging (target)

For each scan-driven purchase path, log:

- Original extraction blob (immutable)
- Normalized strings and match candidates
- User-selected matches and manual edits
- Validation outcome and final persisted payload

Use `purchase_validation_logs` / `scan_logs` tables when introduced; until then, leverage existing `purchase_scan_traces` where applicable.

---

## Database safety

- Writes that create or update purchases should be **transactional** and **rollback-safe**.
- Prefer a single service path for `TradePurchase` creation (e.g. `create_trade_purchase`) so validation and duplicate checks stay centralized.

---

## Edit item UX (product)

When the user edits a line from the draft wizard:

- Show **instant** debounced suggestions (catalog, aliases).  
- Surface **recent items** and **this supplier’s recent purchase lines** as ranked candidates.  
- Never commit a new catalog row without explicit “create new item” flow + required fields.

---

## UI / UX guardrails

**NO:** tiny cards that hide numbers, overlapping bottom sheets with keyboard, horizontal cutoff of money columns, fake “OCR milestone” checklists that imply validation happened.

**YES:** ERP-style tables, readable rates/qty, keyboard-safe full-screen or padded editors, sticky primary actions, confidence badges (green / amber / red).

---

## Frontend safety

Flutter client is **not** source of truth. Use **Riverpod** with debounced search providers, pagination, and minimal rebuild scope — see performance notes in [`AI_PURCHASE_DRAFT_ENGINE.md`](AI_PURCHASE_DRAFT_ENGINE.md).

---

## Final rule

**Accuracy and financial safety outweigh faster automation.** Never skip validation to shorten the happy path.
