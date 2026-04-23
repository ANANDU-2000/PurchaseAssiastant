# PURCHASE APP — UX/UI ENGINEERING SYSTEM (FINAL PRODUCTION FIX)

---

# 1. CORE UX PRINCIPLE (STRICT)

This app MUST behave like:

→ Tally mobile  
→ Not like form app  
→ Not like wizard  
→ Not like ERP screens

RULE:

INPUT → SELECT → AUTO → SAVE  
(NO navigation, NO scrolling)

---

# 2. SCREEN SYSTEM (ZERO SCROLL ARCHITECTURE)

---

## 2.1 MAIN PURCHASE SCREEN (ONLY SCREEN)

NO multiple pages  
NO steps  
NO wizard

---

## FIXED LAYOUT (375px iPhone base)

```
[TOP BAR]
← Back        New Purchase

[ROW 1]
Supplier [search inline]

[ROW 2]
Broker [optional]

[ROW 3 - MAIN ENTRY]
Item input (focus field)

[ROW 4]
Qty | Unit | Rate

[ROW 5]
Line total (auto)

[ROW 6]
+ Add Line

[ROW 7 - SUMMARY]
Subtotal
GST
Total

[BOTTOM FIXED]
SAVE BUTTON (sticky)

```

---

## RULES

- ❌ NO vertical scroll
- ❌ NO horizontal scroll
- ❌ NO dropdown outside screen
- ✅ Everything inside viewport
- ✅ Keyboard-safe

---

# 3. SEARCH SYSTEM (CRITICAL FIX)

---

## CURRENT ISSUE (YOU HAVE)

- dropdown appears below
- keyboard hides results
- scroll needed
- lag feeling

---

## FIX (TALLY STYLE)

---

### INLINE SEARCH (MANDATORY)

When typing:

```
[ Item input: "a" ]

--------------------------------
| Apple Oil        ₹120         |
| Amul Milk        ₹60          |
| Aashirvad Rice   ₹200         |
--------------------------------

```

---

## RULES

- results appear INSIDE input block
- max 5 results
- NO scroll list
- NO page shift
- NO navigation

---

## BEHAVIOR

- tap = instantly fills line
- auto move to qty

---

# 4. ITEM ENTRY UX (BIG FIX)

---

## CURRENT (BAD)

- full page form
- many fields
- scroll
- confusion

---

## FIX (INLINE ENTRY ONLY)

---

### FLOW

1. type item
2. select item
3. enter qty
4. enter rate
5. auto calculate
6. done

---

## OPTIONAL FIELDS

Hidden behind:

→ "Advanced"

ONLY when clicked:

- HSN
- GST
- discount

---

# 5. KEYBOARD SYSTEM (CRITICAL)

---

## CURRENT ISSUE

- keyboard overlap
- input hidden
- UI jump

---

## FIX

---

### RULE

Active input must always stay in TOP 40% of screen

---

### IMPLEMENT

- use viewInsets
- auto scroll disabled
- shift layout instead

---

# 6. BUTTON SYSTEM

---

## RULE

ONLY ONE PRIMARY BUTTON

---

### CURRENT ISSUE

- too many buttons
- confusion

---

### FIX

```
ONLY:
SAVE (bottom)

SECONDARY:
+ Add Line

```

---

# 7. FIELD REDUCTION (IMPORTANT)

---

## REMOVE FROM MAIN SCREEN

- billty
- freight
- GST
- notes
- advanced configs

---

## MOVE TO:

→ Advanced modal

---

# 8. CARD & UI CLEANUP

---

## CURRENT ISSUE

- borders everywhere
- heavy cards
- clutter

---

## FIX

- remove borders
- use spacing instead
- 8pt grid system

---

## SPACING SYSTEM

- small = 8px
- medium = 16px
- large = 24px

---

# 9. STATE SYNC (YOUR ISSUE — FIXED)

---

## ROOT PROBLEM

keepAlive providers not invalidated

---

## FINAL RULE

After ANY write:

```
invalidateBusinessAggregates(ref)

ref.invalidate:
- suppliersListProvider
- brokersListProvider
- catalogItemsProvider
- purchaseListProvider
- reportsProvider

```

---

## ALSO ADD

### GLOBAL EVENT BUS

```
onPurchaseSaved → refresh all
onItemCreated → refresh suppliers + items
onDelete → refresh everything

```

---

# 10. NO LAG RULE

---

## MUST

- search local first
- API only after 2 chars
- debounce 150ms

---

# 11. NAVIGATION SYSTEM

---

## REMOVE

- multiple pages
- back and forth

---

## KEEP

ONLY:

- Home
- Purchase
- Reports

---

# 12. TALLY-LIKE EXPERIENCE (FINAL)

---

User flow must feel:

- type → instant result
- enter → auto move
- no thinking
- no waiting
- no confusion

---

# 13. BUG PREVENTION (STRICT)

---

CHECK BEFORE RELEASE:

- keyboard never hides input
- no scroll needed
- search always visible
- totals always correct
- no stale data after save
- delete updates instantly

---

# 14. WHAT YOU MUST REFACTOR (IMPORTANT)

---

START HERE:

1. remove purchase wizard
2. build single screen entry
3. rebuild item search inline
4. remove dropdown system
5. implement cache invalidation globally

---

# 15. FINAL RESULT

---

After this:

- app feels like Tally
- ultra fast
- zero confusion
- production ready
- scalable SaaS

---

END