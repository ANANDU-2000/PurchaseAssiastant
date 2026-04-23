# PURCHASE MANAGEMENT SAAS — ADVANCED MASTER PLAN (FINAL v3)

---

# 1. PRODUCT DEFINITION

# 🔥 CORE PURCHASE FLOW (FINAL LOGIC)

## SINGLE SCREEN FLOW

1. Select Supplier
2. Select / Type Item
3. Enter Qty
4. Enter Rate
5. Auto Calculate
6. Add Line
7. Save Purchase

---

## LINE CALCULATION

IF unit = bag:  
total_kg = qty × kg_per_bag

line_total = qty × rate

---

## PURCHASE TOTAL

subtotal = sum(line_total)

final_total = subtotal

- freight
- commission
- discount

---

## AUTO BEHAVIOR

- selecting supplier → loads preferred items
- selecting item → loads default unit + rate
- entering qty → auto focuses rate
- entering rate → auto calculates total

---

## SAVE FLOW

ON SAVE:

- insert purchase
- insert lines
- update supplier stats
- update item usage
- invalidate all caches

---

END

## 1.1 Goal

Build a **high-speed purchase entry system** for traders:

- No-scroll UI
- Instant search
- Accurate calculations
- Full supplier/broker/item tracking
- GST + HSN compliant
- Ledger + reports ready

CORE PRINCIPLE:  
FAST ENTRY + ZERO THINKING

---

# 2. MASTER DATA MODELS (FULL)

---

## 2.1 SUPPLIER (FINAL STRUCTURE)

Fields:

- id
- name (required)
- phone
- whatsapp
- location
- GSTIN
- payment_days
- default_discount_percent
- default_freight
- default_billty
- default_delivered_rate_per_unit ✅ (ADDED)
- default_commission_percent
- credit_limit
- notes

### JSON

```id="sup_json"
supplier {
  id,
  name,
  contact: {
    phone,
    whatsapp,
    location
  },
  tax: {
    gstin
  },
  defaults: {
    payment_days,
    discount_percent,
    freight,
    billty,
    delivered_rate_per_unit,
    commission_percent
  }
}

```

---

## 2.2 BROKER

Fields:

- id
- name
- phone
- commission_percent
- location
- notes

---

## 2.3 CATEGORY + SUBCATEGORY

Fields:

- category_id
- category_name
- subcategory_id
- subcategory_name

---

## 2.4 ITEM (FULLY CORRECTED)

Fields:

- id
- item_name
- item_code
- category_id
- subcategory_id
- unit_type ✅ (kg / bag / box / piece / liter)
- packing_type ✅ (50kg bag / 1L / 10 box etc)
- units_per_pack ✅ (numeric)
- default_landing_cost
- default_selling_price
- HSN_code
- GST_percent
- description

### JSON

```id="item_json_full"
item {
  id,
  name,
  code,
  category_id,
  subcategory_id,
  unit: {
    type,
    packing_type,
    units_per_pack
  },
  pricing: {
    landing_cost,
    selling_price
  },
  tax: {
    hsn,
    gst_percent
  }
}

```

---

## 2.5 RELATION MAPS (FULL)

### Supplier ↔ Item

```id="map1"
supplier_item_map {
  supplier_id,
  item_id,
  last_used_date,
  priority_rank
}

```

### Broker ↔ Item

```id="map2"
broker_item_map {
  broker_id,
  item_id
}

```

---

# 3. PURCHASE SYSTEM (FULL LOGIC)

---

## 3.1 PURCHASE OBJECT

```id="purchase_json"
purchase {
  id,
  supplier_id,
  broker_id,
  date,
  header: {
    freight,
    billty,
    delivered_rate,
    commission_percent,
    payment_days
  },
  totals: {
    subtotal,
    tax,
    commission,
    final_total
  }
}

```

---

## 3.2 PURCHASE ITEM LINE

```id="line_json"
purchase_line {
  item_id,
  quantity,
  unit,
  rate,
  total,
  landing_cost,
  gst_percent,
  hsn
}

```

---

# 4. PURCHASE FLOW (FULL NUMBERED)

---

## FLOW 1: OPEN PURCHASE

1. User taps "+"
2. Purchase screen opens (single screen)

---

## FLOW 2: SELECT SUPPLIER

1. User types (1 letter)
2. Instant inline suggestions
3. Select supplier
4. Auto-fill defaults:
  - payment days
  - delivered rate
  - commission %

---

## FLOW 3: SELECT BROKER

1. Optional
2. Same inline search
3. commission auto set

---

## FLOW 4: ADD ITEM (CRITICAL FLOW)

1. Tap item field
2. Type name
3. Inline suggestions appear
4. Select item OR create new

IF NEW:  
→ open small modal (NOT new page)  
→ fill:

- name
- category
- unit
- HSN
- GST  
→ save → return instantly

---

## FLOW 5: ENTER QUANTITY

- quantity input
- unit auto-selected
- packing applied

---

## FLOW 6: ENTER RATE

- rate input
- auto calculation starts

---

## FLOW 7: AUTO CALCULATION

System calculates:

- total
- landing cost
- GST
- profit

---

## FLOW 8: ADD MULTIPLE LINES

- repeat item flow
- no navigation

---

## FLOW 9: REVIEW (INLINE)

No separate screen

Show:

- subtotal
- GST
- commission
- final total

---

## FLOW 10: SAVE

1. Click SAVE
2. Validate
3. Save DB
4. Update all modules
5. Redirect home
6. Show bottom sheet:
  - View
  - Share PDF
  - WhatsApp

---

# 5. CALCULATION ENGINE

---

## BAG

total = bags × rate_per_bag  
kg = bags × units_per_pack

---

## KG

total = kg × rate_per_kg

---

## GST

tax = subtotal × GST%

---

## FINAL

final = subtotal + tax + commission + freight

---

# 6. MOBILE UI (NO SCROLL DESIGN)

---

## SCREEN STRUCTURE

```id="ui_layout"
[TOP FIXED]
Supplier | Broker

[MIDDLE FIXED]
Item input
Qty input
Rate input
Add line button

[SUMMARY]
Subtotal
GST
Total

[BOTTOM FIXED]
SAVE BUTTON

```

---

## RULES

- max 6 visible inputs
- no vertical scroll
- no horizontal scroll
- modal for extra fields

---

## MODAL SYSTEM

Used for:

- create item
- advanced fields

---

# 7. SEARCH SYSTEM (ADVANCED)

---

## REQUIREMENTS

- 1 letter search
- fuzzy match
- no API delay
- local cache

---

## PRIORITY ORDER

1. recent items
2. supplier items
3. global items

---

## UI BEHAVIOR

- results inside input
- no dropdown below
- no page shift

---

# 8. DATA FLOW (FULL SYNC FIX)

---

## ON SAVE

Must update:

- purchase list
- supplier ledger
- broker ledger
- item usage
- reports
- dashboard

---

## CACHE INVALIDATION

MANDATORY:

- suppliers
- brokers
- items
- reports
- purchases

---

## ON DELETE

- remove purchase
- update totals
- refresh all screens

---

# 9. HISTORY MODULE

---

## VIEW

- list purchases
- filter:
  - supplier
  - item
  - date

---

## ACTIONS

- view
- edit
- delete
- share PDF

---

# 10. LEDGER SYSTEM

---

## SUPPLIER LEDGER

- total purchases
- pending
- history

---

## BROKER LEDGER

- commission earned
- linked purchases

---

# 11. PDF SYSTEM (ADVANCED)

---

## HEADER

- company name
- GST
- invoice number

---

## TABLE

Columns:

- item
- HSN
- qty
- unit
- rate
- GST
- amount

---

## TOTALS

- subtotal
- GST
- commission
- final total

---

# 12. REPORTS SYSTEM

---

## METRICS

- spend
- profit
- deals
- avg value

---

## SECTIONS

- top items
- top suppliers
- category performance
- profit trend

---

# 13. CRITICAL UX RULES

---

MUST:

- instant response
- no lag
- minimal clicks
- inline everything

---

MUST NOT:

- dropdown search
- multi-step wizard
- long scroll forms

---

# 14. TEST CASES

---

## PURCHASE

- create
- edit
- delete

---

## SEARCH

- instant result
- correct ranking

---

## UI

- no overlap
- no scroll
- keyboard safe

---

## DATA

- sync everywhere

---

# 15. FINAL SYSTEM OUTPUT

---

This system becomes:

- fast purchase diary
- lightweight ERP
- scalable SaaS product

---

END OF DOCUMENT