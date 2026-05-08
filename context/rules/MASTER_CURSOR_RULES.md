# Master Cursor Rules — ERP + AI Scanner

**Do not guess — strict ERP + AI scanner rules.** This is a real business purchase system.

## Cursor must never

- Guess missing logic, fields, UI, calculations, item/supplier/broker names, units, totals, kg, bags, profits, or reports.

If uncertain: **STOP → TRACE → LOG → VALIDATE → ASK CODEBASE → CHECK DB → CHECK TYPES → CHECK API → CHECK EXISTING PURCHASE FLOW.**

---

## Critical real-world business rule

**AI scanner never creates the final purchase.**

AI only creates a **purchase draft**. Final purchase is created only after:

1. AI extraction  
2. DB matching  
3. Validation  
4. Duplicate check  
5. User review  
6. Purchase wizard confirmation  
7. Backend recalculation  
8. Authoritative totals  
9. Final create  

---

## Current critical issues (track in `BUGS.md`)

1. **Wrong item matching** — e.g. bill says “Sugar 50kg” but system maps to unrelated retail SKU (severe).  
2. **Unit logic failure** — wholesale bag/kg vs retail packet; destroys stock, totals, reports.  
3. **Reports wrong** — dashboard vs detail vs charts mismatch; “no data” after non-zero totals.  
4. **Delete failure** — UI hides row but data/cache still visible or inconsistent.  
5. **UI/UX** — overlap, keyboard, tables, whitespace, sticky summary, wizard clarity, viewport (e.g. iPhone 16 Pro).  
6. **AI extraction gaps** — delivered/bilty/freight/commission/broker figure/payment days; multi-page merge.  
7. **Search/suggestions** — typing `sug` must surface ranked catalog + aliases + history (not silent).

---

## Mandatory architecture (conceptual pipeline)

AI scan page → upload → **vision/text extraction (strict JSON)** → normalization → structured JSON → match engine → purchase draft wizard → validation → final purchase create.

**Raw extraction is not trusted for writes** until matched, validated, and confirmed.

---

## Mandatory purchase draft flow

1. Supplier + broker matching  
2. Terms + charges  
3. Item matching  
4. Financial summary (backend-authoritative)  
5. Validation + create  

---

## Strict match engine rules (item)

Priority order:

1. Exact alias  
2. Normalized exact  
3. Supplier history  
4. Unit match  
5. Bag/kg consistency  
6. Fuzzy similarity  
7. AI semantic backup (last resort)  

### Critical unit safety

Never match wholesale pack size to incompatible retail unit (e.g. 50kg bag line → 1kg packet SKU). **Unit mismatch → force manual review** (low confidence / blocked auto-match).

### Mandatory pre-auto-match checks

Compare: unit, package size, category, aliases, supplier history, prior purchases, quantity pattern, weight pattern.

---

## Confidence

Bands: **HIGH / MEDIUM / LOW**. LOW requires manual review. **Unit mismatch → force review.**

---

## Mandatory item payload (target shape)

Store at minimum: `raw_text`, `normalized_text`, `matched_item_id`, `confidence`, `qty`, `unit`, `weight_kg`, `purchase_rate`, `selling_rate`, line-level charges if applicable, `line_total`, margin fields as **server-computed**, `aliases_used`, `user_corrected`.

---

## Normalization engine

Normalize: Malayalam, Manglish, shorthand, extraction typos, spacing, unit aliases (e.g. suger→sugar, bg→bag, kgs→kg).

---

## Search engine (item fields)

Live autocomplete over: names, aliases, supplier-specific items, recent purchases. Show unit, supplier context, last rate when available.

---

## Supplier / broker match

Aliases, phone, prior bills, broker relation, fuzzy search. **Never auto-create silently** — confirm “Create new …?” when unknown/low confidence.

---

## Financial engine

**All totals backend-authoritative.** Frontend displays; does not own truth for bags, kg, lines, freight, bilty, commission, margins, profit.

---

## Reports engine

Dashboard, purchase detail, reports, charts must use the **same backend aggregation contracts**. Single source of truth; no duplicate client-side aggregation for money totals.

---

## Mandatory delete flow

Server delete (or defined soft-delete) → cache invalidation → refetch lists/summaries → charts/totals refresh → no stale local optimistic state.

---

## UI/UX rules

Sticky safe bottom actions where applicable; equal-width primary actions; readable tables; minimize overlap (keyboard, sheets, nav). Optimize critical viewports (e.g. 393×852) with safe areas.

**Scan page scope:** upload, progress, preview extraction, **open draft wizard** — not full ERP editing (editing belongs in wizard / existing purchase flows).

---

## Purchase flow integration

AI scan → **purchase draft wizard** → reuse **existing manual purchase / trade flows** for final create — do not maintain a second incompatible pipeline.

---

## Performance

Debounce search, paginate/virtualize large lists, avoid full-tree rebuilds; invalidate caches narrowly after mutations.

---

## Logging / audit

Log raw extraction snapshots, normalization output, match attempts, rejections, validation failures, unit conflicts, delete IDs, and report calculation inputs (without secrets).

---

## Mandatory tracking files (repo root)

Agents update when behavior changes:

| File | Purpose |
|------|---------|
| `PROJECT_STATUS.md` | Completed / current / pending / blockers |
| `TASKS.md` | Phased tasks (canonical; mirror under `context/rules/` if duplicated) |
| `CURRENT_CONTEXT.md` | Active screen, bug, logic, last edits |
| `BUGS.md` | Repro, severity, status |
| `SCAN_ENGINE.md` | Extraction flow, prompt hooks, schema |
| `MATCH_ENGINE.md` | Aliases, fuzzy, confidence, rejections |
| `REPORT_ENGINE.md` | Formulas, aggregation, cache |

---

## Mandatory AI scanner goal

Support wholesalers, handwriting, Malayalam, multi-page, terms/charges, supplier/broker match, autocomplete, corrections, **safe** financial math — without wrong items, broken totals, broken inventory, fake profits, or silent duplicates.

---

## Final rule

This is **real money, real inventory, real accounting.** Behave as a senior ERP + inventory + financial validator + vision extraction engineer — **not** a UI demo builder.
