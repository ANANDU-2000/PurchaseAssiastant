# AI PURCHASE DRAFT ENGINE

The AI scanner **never** directly creates purchases. Production flow is **scan → draft/review → validation → human confirm → purchase**.

**Strict pipeline (single sentence):**  
IMAGE → AI extraction → normalization → alias matching → confidence scoring → financial validation → purchase draft → human review → final purchase creation.

**OCR-style pipelines are forbidden** for purchase bills: use **OpenAI Vision** (image → structured JSON) only. Any legacy “OCR extracting / rates validated” UI is misleading and must not ship.

**Never persist to `trade_purchases` without:** draft/review UI, validation gates, and an explicit user confirm action.

---

## Known gaps (screenshot / product backlog)

Use this as the burn-down checklist (verbatim themes from field review):

1. OCR-style fake progress UI  
2. Overlapping bottom sheet  
3. Keyboard covering modal  
4. No item confidence system (consistent UX + API contract per field/row)  
5. No DB smart matching  
6. Weak item normalization  
7. No alias engine  
8. No multi-page flow  
9. No purchase draft wizard flow  
10. No quantity / unit intelligence  
11. Thin freight / bilty / delivery parsing  
12. No structured financial summary from backend  
13. Duplicate detection / supplier-broker intelligence insufficient vs wholesale needs  
14. Table truncation; item preview too compressed  
15. No expandable rows  
16. AI returns raw noisy names  
17. Edit search not connected to DB keyword aliases  
18. No Malayalam normalization dictionary  
19. No fuzzy matching engine  
20. No scan confidence score **per field** (structured, not ad-hoc)  
21. No fallback validation system  
22. No dedicated financial validation layer (server-enforced before save)  

**Flutter note:** The faux OCR **checklist** was removed from the scan bill screen; staged progress copy is Vision-first. Other items still apply until backend + wizard ship.

---

## Strict end-to-end flow

```
UPLOAD BILL (camera / gallery / recent scans)
        ↓
OpenAI Vision analysis (strict JSON schema)
        ↓
RAW EXTRACTION STORED (immutable snapshot)
        ↓
NORMALIZATION ENGINE
        ↓
DB MATCH ENGINE (aliases + history + fuzzy)
        ↓
CONFIDENCE ENGINE (per field / row)
        ↓
FINANCIAL VALIDATION (backend-only totals)
        ↓
PURCHASE DRAFT WIZARD (human review)
        ↓
STEP 1 — Supplier / broker (+ bill identity: bill date, invoice #, notes, confidence) — editable
        ↓
STEP 2 — Terms & charges (payment days, delivered rate, freight, bilty,
        broker commission / discount as on bill)
        ↓
STEP 3 — Item review TABLE (ERP columns; expandable rows; tap row → edit sheet;
        typeahead matching e.g. Sug → SUGAR 50 KG via aliases + history — inline in editor)
        ↓
STEP 4 — Financial summary (totals, bags, kg, charges, margin — backend ONLY)
        ↓
STEP 5 — Final validation (duplicates, missing rates, abnormal qty, unknown
        supplier/items, total mismatch) → explicit confirm
        ↓
CREATE PURCHASE (single server command after explicit confirm)
```

**UX variants:** Steps **1 + 2** may be a single **“Bill overview”** screen in the app. Some designs add a **dedicated item-matching step** between table and financial — equivalent if the same matching gates run before save.

**Anti-pattern:** scan → instant create (causes wrong totals, duplicate lines, inventory/report corruption).

---

## Purchase draft wizard (five steps — roadmap primary)

Aligned with stakeholder **REAL FLOW**: Supplier/Broker → Terms & Charges → Item table → Financial → Validation.

| Step | Screen | Contents |
|------|--------|----------|
| **1 — Supplier / broker** | Parties + identity | Supplier, broker, bill date, invoice number, notes; **per-field confidence**; editable. *(Bill-level identity fields can live here or stay merged with step 2 in one UI.)* |
| **2 — Terms & charges** | Money headers | Payment days, delivered rate, freight, bilty, broker commission / broker figure / discount as extracted from bill. |
| **3 — Item review table** | ERP layout | Columns: item, qty, unit, kg, purchase rate, selling rate, line amount, confidence; **expandable rows**; tap row → edit sheet (keyboard-safe). **Item matching:** typeahead (`Sug` → catalog) inside the editor **or** a dedicated sub-step — same rules. |
| **4 — Financial summary** | Totals | Total qty, bags, kg, item subtotal, freight, delivery, bilty, extras, final amount, expected profit, margin — **server-computed only**. |
| **5 — Final validation** | Gate | Duplicates, missing rates, abnormal qty, unknown supplier/item, total mismatch → **then** user confirms → create purchase. |

**Always:** AI SCAN → DRAFT → REVIEW → CONFIRM → PURCHASE (never write `trade_purchases` on scan alone).

---

## Draft vs purchase persistence

- **Today:** Vision scan returns `ScanResult` + `scan_token` (server cache). User edits and **`POST .../scan-purchase-v2/confirm`** creates `TradePurchase`. That is already “draft then confirm,” but UI still mixes scan + review on one page.
- **Target:** Persist **`scan_drafts`** / **`scan_draft_items`** (and optional `purchase_validation_logs`) so every edit and audit trail is recoverable; confirm reads draft row, runs validators, then inserts purchase.
- Scan/analysis endpoints must remain **side-effect free** on `trade_purchases` except intentional alias learning endpoints.

---

## REQUIRED SYSTEMS

### 1. RAW EXTRACTION ENGINE

Persist and never overwrite:

- Raw bill text / line blobs as returned by the model (where applicable).
- `raw_item_name`, raw supplier/broker strings.
- Multi-page: ordered `pages[]` with merged extraction.

---

### 2. NORMALIZATION ENGINE

Normalize before matching:

- Lowercase, collapse spaces, strip symbols.
- Unit formats: `50kg` → `50 kg`.
- Spelling correction (e.g. `suger` → `sugar`).
- Malayalam → canonical English/Manglish map (dictionary-backed).
- Manglish variants.

Example:

```
BAKER CRAFT ICING SUGAR 1KG  →  normalize tokens → match against aliases / catalog
Suger 50kg                   →  sugar 50 kg
```

Poor catalog matches are usually **post-AI normalization + matching**, not model vendor issues.

---

### 3. ALIAS ENGINE (DB)

Tables (conceptual; migrate explicitly):

- `item_aliases`
- `supplier_aliases`
- `broker_aliases`

Draft, audit, and telemetry (target schema):

- `scan_logs`
- `scan_drafts`
- `scan_draft_items`
- `purchase_validation_logs`

Signals:

- Trigram / fuzzy similarity.
- Keyword and alias hits.
- Supplier purchase history.
- Previous scan / draft history.

Typing `Sug` in item search must surface `SUGAR 50 KG`, `SUGAR 25 KG`, etc., from aliases + catalog + history.

---

### 4. CONFIDENCE ENGINE

Every extracted field supports:

```json
{
  "supplier": { "value": "Surag", "confidence": 0.81 }
}
```

Policy (tunable):

- **≥ 0.92** — auto OK, green.
- **0.75–0.92** — amber; confirm or pick candidate.
- **&lt; 0.75** — suggestions list; block silent auto-match where risk is high.

Align UI with badges (green / yellow / red).

---

### 5. MULTI-PAGE SUPPORT

- Upload **Scan Page 1 + Page 2 + …**
- Preserve order; send **`images: []`** to analysis.
- Merge line items and totals with dedupe rules.

---

### 6. PURCHASE DRAFT FLOW

Follow the **five-step roadmap table** above. **Item matching** (aliases, `Sug` → `SUGAR 50 KG`) is required before finalize and typically lives **inside step 3** (row editor) unless product adds a separate matching screen.

**Scan screen (pre-wizard):** camera, gallery, recent scans only — no faux OCR milestone checklist.

---

## ITEM TABLE RULES

- ERP-style **table**, not tiny mystery cards.
- Columns: item, qty, unit, kg, purchase rate, selling rate, line amount, confidence.
- Rows **expandable**; tap opens focused edit sheet (keyboard-safe).
- Do not truncate rates or quantities in ways that hide financial risk.

---

## SEARCH ENGINE RULES

Instant suggestions from:

- Aliases, keywords, catalog.
- Prior purchases and supplier-specific history.

---

## FINANCIAL RULES

- **All** rollups (qty, kg, bags/box/tin, freight, bilty, delivery, discounts, commission, grand total, expected margin) are computed **on the backend**.
- Frontend **renders** numbers returned by API; no authoritative client-side totals.

---

## VALIDATION RULES

Block or warn with structured codes:

- Duplicate bills / duplicate lines.
- Missing purchase rates or units.
- Abnormal quantities vs history.
- Unknown supplier/item without explicit user confirmation.
- Scanned vs computed total mismatch.

---

## MOBILE UX RULES

- Keyboard avoiding / inset padding on sheets and full-screen editors.
- Safe areas (notch, home indicator).
- No bottom bar overlap with keyboard.
- Sticky primary actions where possible.
- Readable full-width tables; horizontal scroll acceptable for dense columns.

---

## PERFORMANCE RULES

- Pagination / virtualization for large item lists.
- Memoization for stable subtrees.
- Debounced search/typeahead for catalog and alias suggestions.
- **Flutter:** **Riverpod** (not React Query) with narrow `select`/scoped rebuilds — avoid refetching entire purchase history for small edits.
- Optimistic UI only where rollback is safe.

*(Separate web admin stacks may use TanStack Query; this mobile app does not.)*

---

## FOUR-LAYER MATCHING (summary)

| Layer | Role |
|-------|------|
| **1 — AI extraction** | Raw JSON: `raw_item_name`, entities, numbers as seen. |
| **2 — Cleaner** | Spelling, spacing, units, Malayalam/Manglish normalization. |
| **3 — Alias engine** | DB aliases + fuzzy + history → candidate catalog rows. |
| **4 — Confidence** | Score + threshold → auto vs suggest vs block. |

**Example (icing-sugar vs wholesale sugar):**

```json
{ "raw_item_name": "Suger 50kg" }
```

→ **Cleaner:** `sugar 50 kg` → **Aliases:** `suger`, `sugar50`, `sugar 50kg`, `50kg sugar`, … → **Match:** `SUGAR 50 KG` with score **0.94**.  
If **confidence &lt; 0.75**, UI must show **suggestions**, not silent match.

Wrong outcome **BAKER CRAFT ICING SUGAR 1KG** when the business buys **SUGAR 50 KG** is a **post-AI normalization + alias** problem, not an OpenAI vendor issue.

---

## REFERENCE: WRONG VS RIGHT PRODUCT NAME

- **Wrong outcome:** `BAKER CRAFT ICING SUGAR 1KG` selected when the business buys **`SUGAR 50 KG`**.
- **Fix:** normalization + alias table (`icing sugar`, brand tokens) + supplier line-item history + user correction writes new aliases (`POST /correct` or equivalent).

*(See also the worked example under **Four-layer matching** above.)*

---

## RELATED DOCS

- [`docs/05_AI_SCANNER.md`](05_AI_SCANNER.md) — Vision pipeline and API surface.
- [`docs/AI_SCANNER_SPEC.md`](AI_SCANNER_SPEC.md) — scan contract and confirm flow.
- [`docs/AI_PURCHASE_VALIDATION_AND_SAFETY.md`](AI_PURCHASE_VALIDATION_AND_SAFETY.md) — NEVER/ALWAYS rules, validation gates, audit.
- [`docs/SCAN_GUIDE_UX_SPEC.md`](SCAN_GUIDE_UX_SPEC.md) — full-screen Scan Guide for staff training.
- [`backend/app/services/purchase_draft_engine.py`](../backend/app/services/purchase_draft_engine.py) — shared confidence thresholds (extend for draft-first).
