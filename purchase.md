# PURCHASE ENTRY SPEC (STRICT)

## 1. HEADER

Fields:

- purchase_id (auto, preview)
- date (default today, editable)
- supplier (required, searchable)
- broker (optional, auto from supplier OR manual)

RULE:

- selecting supplier MUST update:
  - controller text
  - selectedSupplier state
  - supplier_id
  - defaults

---

## 2. SUPPLIER DEFAULTS

When supplier selected, show:

- payment_days
- delivered_rate
- billty_rate
- freight (amount + type)
- broker_commission

All editable.

---

## 3. ITEM ENTRY

Fields:

- item (search, min 2 chars)
- qty (> 0)
- unit
- landing_cost (> 0)
- selling_price (optional)
- tax % (from HSN)
- discount %

NO "rate" field.

---

## 4. LIVE CALCULATION

- landing_total = qty × landing_cost
- discount applied before tax
- tax applied after discount
- final_line_total

---

## 5. SUMMARY

Show:

- subtotal
- tax
- discount
- freight
- broker_commission
- final_total

---

## 6. VALIDATION

BLOCK SAVE IF:

- supplier missing
- no items
- qty <= 0
- landing_cost <= 0

Show inline errors + scroll to error.

---

## 7. DRAFT SYSTEM

- auto-save every 400ms
- restore on reopen
- clear after save

---

## 8. API RULES

- supplier_id REQUIRED
- landing_cost used (NOT rate)
- no null values
- always sync before save

---

## 9. UI RULES

- single scroll only
- no nested scroll
- no ExpansionTile confusion
- no duplicate fields

---

## 10. PERFORMANCE

- no infinite rebuild
- no setState after dispose
- avoid heavy rebuilds

---

## 11. ERROR HANDLING

- show API error message
- no silent fail
- no stuck loading

---

THIS FILE IS FINAL SOURCE OF TRUTH.