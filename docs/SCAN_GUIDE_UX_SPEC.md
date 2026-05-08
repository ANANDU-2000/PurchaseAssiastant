# Scan Guide — UX and AI Input Format

Business-facing spec for teaching wholesalers, brokers, godown staff, and accountants how to write bills so **OpenAI Vision** scans succeed. Not a developer README.

Related: [`AI_PURCHASE_DRAFT_ENGINE.md`](AI_PURCHASE_DRAFT_ENGINE.md), [`AI_PURCHASE_VALIDATION_AND_SAFETY.md`](AI_PURCHASE_VALIDATION_AND_SAFETY.md).

---

## Primary goal

Reduce scan failures, wrong matches, wrong totals, and confusion about “what the AI expects.” Better handwriting habits → fewer ERP errors.

---

## Entry point (Flutter)

- **Where:** Top-right on the scan bill screen (AppBar action).
- **Labels:** “Scan guide” or “How to write for AI scan”.
- **Presentation:** **Full-screen route** (`push` a dedicated page). Not a tooltip, not a small popup, not a half-height bottom sheet.

---

## Page structure (mobile-first)

Large typography, high contrast, scrollable, image-heavy where helpful. Sticky **Close** (leading) and bottom **Start AI scan** CTA that `pop`s back to the scanner.

---

### Section 1 — Best writing format

Large visual example block:

```
SUP: Surag
BRO: KKKK
PD: 7
DR: 56
FR: 1200
BR: 350
BC: 2%
BF: 5000
DS: 300

Sugar 50kg | 100 bag | P 57 | S 58
Rice 26kg | 50 bag | P 830 | S 860
Sunrich 1ltr | 20 box | P 1450 | S 1520
```

---

### Section 2 — Supported shortcodes

ERP-style table:

| Code | Meaning |
|------|---------|
| SUP | Supplier |
| BRO | Broker |
| PD | Payment days |
| DR | Delivered rate |
| FR | Freight |
| BR | Bilty rate |
| BC | Broker commission |
| BF | Broker figure |
| DS | Discount |
| P | Purchase rate (per line) |
| S | Selling rate (per line) |

**Conflict rule:** Do not overload ambiguous letters — **never use `B` for both broker and bilty**; use **SUP/BRO/BR** as above.

---

### Section 3 — Item line format

Teach one pattern:

`Item Name | Qty Unit | P purchase | S selling`

Example:

`Sugar 50kg | 100 bag | P 57 | S 58`

Rules: one item per line; clear spacing; rates kept on the same row as the item; avoid arrows and scribbled symbols between columns.

---

### Section 4 — Good vs bad examples

**Good:** flat paper, good light, clear handwriting, one line per item, dark pen.

**Bad:** folded paper, shadows, crossed-out layers, overlapping numbers, tiny cramped text, blurry photo.

Use side-by-side thumbnails or illustrations.

---

### Section 5 — AI scan tips

Checklist:

- One item per line  
- Use supported shortcodes in the header area  
- Black or blue pen  
- Keep paper flat  
- Avoid shadows and glare  
- Avoid side-angle photos  
- Keep rates adjacent to each item row  

---

### Section 6 — Supported languages

- English  
- Malayalam  
- Manglish  

Examples:

- പഞ്ചസാര → sugar  
- സുരഗ് → Surag (supplier nickname variants normalize after extraction)

---

### Section 7 — Supported units

bag, kg, box, tin, sack, litre, packet, piece.

Normalization examples: `bags`, `bg`, `bgs` → **bag**.

---

### Section 8 — Multi-page bills

Explain that users may photograph multiple pages (notebook spreads, long invoices, multiple WhatsApp images). Product target: upload **`images[]`** in order; backend merges extraction (see draft engine).

---

### Section 9 — Common mistakes

- All items in one paragraph  
- Random floating numbers with no item  
- Missing or ambiguous units  
- Rates separated far from items  
- Heavy corrections on top of corrections  

---

### Section 10 — Sample bill preview

Static **ERP-style** preview card: supplier, broker, terms strip, charges line, items table, totals footer — reinforces the target structure.

---

## Bottom CTA

**Start AI scan** — closes the guide and returns to the scanner.

---

## AI system prompt support

The Vision / structured parser **must** understand these bill shorthands (aligned with Section 2):

**SUP**, **BRO**, **PD**, **DR**, **FR**, **BR** (bilty), **BC**, **BF**, **DS**, and per-line **P** / **S**.

Low-confidence extractions require user confirmation per [`AI_PURCHASE_VALIDATION_AND_SAFETY.md`](AI_PURCHASE_VALIDATION_AND_SAFETY.md).

---

## Input normalization (post-capture, pre-match)

Before matching entities:

- Normalize shorthand spacing and punctuation.  
- Apply Malayalam / Manglish dictionary passes where configured.  
- Collapse duplicate spaces; unify unit tokens (`50kg` → `50 kg`, `bgs` → bag).

---

## Strict AI extraction rules

The model **must not** invent suppliers, brokers, or line items to “fill” the bill. Unknown fields stay empty or low-confidence and force review. Output **JSON only** in the production path (no markdown wrapper).

---

## Financial safety (recap)

Never trust model-printed totals as authoritative. Recompute **bag totals, kg totals, line amounts, freight/bilty/delivery, commission, final total, margin** on the server from resolved IDs and rates.

---

## Final goal

Train wholesalers so **structured bills → higher scan accuracy → fewer ERP mistakes → faster safe purchase entry**.

---

## Search and match (when editing items)

Typing `sug` should surface catalog and alias suggestions instantly (debounced server or local index). Implement together with item alias tables described in [`AI_PURCHASE_DRAFT_ENGINE.md`](AI_PURCHASE_DRAFT_ENGINE.md).
