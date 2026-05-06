## AI SCANNER — PURCHASE ENTRY SYSTEM (SPEC)

### Goal

Convert bill photos / handwritten notes (Malayalam + English mix) into a **structured purchase draft** with **high accuracy**.

**Non‑negotiable**: scanner must **never save automatically**. It only produces a preview + draft for the wizard.

---

## Flow (must match UI + backend)

1. **Scan image** (camera / gallery)
2. **OCR** → raw text + confidence
3. **AI Parse (Gemini → Groq failover)** → structured JSON
4. **DB Matching (directory)**
  - Suppliers, Brokers, Catalog items
  - Use fuzzy matching + suggestions
5. **Validation**
  - qty × kg/unit = total kg
  - rate sanity checks
  - duplicate items detection
6. **Preview table (mandatory)**
7. **User confirmation**
8. **Apply to purchase wizard**

---

## Required extracted fields

### Header entities

- **supplier_name_raw**
- **broker_name_raw** (optional)
- **purchase_date** (optional; default to today only in UI, never in backend)
- **charges (optional)**
  - delivered_rate
  - billty_rate
  - freight_amount
  - freight_type (included/separate)
- **payment_days** (optional)
- **invoice_number / narration** (optional)

### Line entities (repeatable)

Each line must support:

- **item_name_raw**
- **qty**
- **unit** (bag/sack/kg/box/tin/ltr/unit)
- **purchase_rate** (P)
- **selling_rate** (S) (optional but supported)
- **weight_per_unit_kg** (optional)

---

## Intelligence rules (strict)

### 1) Name matching (directory)

- Use fuzzy match suggestions; **do not auto-create silently**.
- If supplier/broker/item is not confidently matched → mark as **needs confirmation**.

### 2) Item detection & spelling correction

- Correct common OCR misspellings (suger→sugar; suray→surag).
- Detect pack weights: `25 KG`, `26 KG`, `30 KG`, `50 KG` in the item name.

### 3) Rate detection (handwritten)

- When pattern is `P 56  S 57` or two adjacent numbers:
  - first = purchase rate
  - second = selling rate
- If only one number: treat as purchase rate and mark selling rate as missing.

### 4) Quantity & weight logic

- If unit is **BAG/SACK** and `weight_per_unit_kg` exists, validate:
  - total_kg = qty × weight_per_unit_kg
- If unit is **KG**, qty is already kg; **never multiply by name weight**.

---

## UI requirements (scanner preview)

### Preview header

- Supplier: matched name + “change/select” action
- Broker: matched name + “change/select” action
- Charges summary (collapsed by default)

### Preview table (no horizontal scroll)

Columns (stack on narrow screens):

- Item
- Qty + Unit (+ kg/unit if present)
- P rate
- S rate (optional)

### Blocking states

Scanner must **block “Apply to purchase”** when:

- Supplier is missing or not confirmed
- Any line has missing item name / qty / unit / purchase rate

---

## Error handling

- If OCR text unreadable → show raw OCR + ask user to re-scan or add rows manually.
- If AI parse fails → fall back to heuristic parser; show warning banner.
- Always show `meta.provider_used` and parse warnings (dev friendly).

---

## Done when

- Scanner reliably produces structured preview for messy OCR
- No silent assumptions for missing entities
- User confirmation gate is enforced