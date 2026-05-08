# MASTER_CURSOR_RULES.md

# DO NOT GUESS — STRICT ERP + AI SCANNER RULES

THIS IS A REAL BUSINESS PURCHASE SYSTEM.

Cursor MUST NEVER:
- guess missing logic
- invent fields
- invent UI
- invent calculations
- invent item names
- invent supplier names
- invent broker names
- invent units
- invent totals
- invent kg
- invent bags
- invent profits
- invent reports

If uncertain:
STOP
TRACE
LOG
VALIDATE
ASK CODEBASE
CHECK DB
CHECK TYPES
CHECK API
CHECK EXISTING PURCHASE FLOW

==================================================
CRITICAL REAL-WORLD BUSINESS RULE
==================================================

AI SCANNER NEVER CREATES FINAL PURCHASE.

AI ONLY CREATES:
PURCHASE DRAFT

FINAL PURCHASE CREATED ONLY AFTER:

1. AI extraction
2. DB matching
3. validation
4. duplicate check
5. user review
6. purchase wizard confirmation
7. backend recalculation
8. authoritative totals
9. final create

==================================================
CURRENT CRITICAL ISSUES FOUND
==================================================

1. WRONG ITEM MATCHING
Example:
User wrote:
Sugar 50kg

AI created:
BAKER CRAFT ICING SUGAR 1KG

SEVERE BUSINESS FAILURE.

==================================================

2. UNIT LOGIC FAILURE

System:
100 bags
5,000 KG

But matched:
1kg retail packet

This destroys:
- stock
- totals
- inventory
- reports
- profits

==================================================

3. REPORTS WRONG

Home dashboard:
₹2,85,000

Later:
₹0

Charts:
"No data"

Data mismatch between:
- reports
- purchase detail
- dashboard
- draft flow

==================================================

4. DELETE FAILURE

Purchase deleted visually
BUT DATA STILL EXISTS

Possible:
- stale cache
- soft delete mismatch
- query filter bug
- local state issue
- optimistic UI issue

==================================================

5. UI/UX FAILURES

- bottom buttons overlap
- modal overlap
- keyboard overlap
- too much empty space
- huge unused viewport
- horizontal compression
- poor tables
- cards too narrow
- line breaks ugly
- actions cramped
- no sticky summary
- wizard steps confusing
- large whitespace
- no desktop/tablet optimization
- iPhone 16 Pro viewport not optimized

==================================================

6. AI EXTRACTION FAILURES

Missing:
- delivered rate
- bilty rate
- freight
- commission
- broker figure
- payment days
- multiple rates
- page merging
- multi-item handling

==================================================

7. SEARCH + SUGGESTION FAILURE

Typing:
"sug"

Must suggest:
- sugar
- sugar 50kg
- sugar loose
- sugar bag

Currently:
NO suggestions.

==================================================
MANDATORY ARCHITECTURE
==================================================

AI SCAN PAGE
↓
UPLOAD
↓
OCR
↓
NORMALIZATION
↓
STRUCTURED JSON
↓
MATCH ENGINE
↓
PURCHASE DRAFT WIZARD
↓
VALIDATION
↓
FINAL PURCHASE CREATE

==================================================
NEVER CREATE PURCHASE DIRECTLY FROM OCR
==================================================

OCR DATA IS RAW ONLY.

==================================================
MANDATORY PURCHASE DRAFT FLOW
==================================================

STEP 1
Supplier + broker matching

STEP 2
Terms + charges

STEP 3
Item matching

STEP 4
Financial summary

STEP 5
Validation + create

==================================================
STRICT MATCH ENGINE RULES
==================================================

ITEM MATCHING PRIORITY:

1. exact alias
2. normalized exact
3. supplier history
4. unit match
5. bag/kg consistency
6. fuzzy similarity
7. AI semantic backup

==================================================
CRITICAL UNIT SAFETY RULE
==================================================

NEVER MATCH:

50kg bag
TO
1kg packet

NEVER MATCH:
bag item
TO
piece item

NEVER MATCH:
wholesale sack
TO
retail unit

==================================================
MANDATORY ITEM MATCH VALIDATION
==================================================

Before auto-match:
system MUST compare:

- unit
- package size
- category
- aliases
- supplier history
- previous purchases
- quantity pattern
- weight pattern

==================================================
CONFIDENCE SYSTEM
==================================================

HIGH
MEDIUM
LOW

LOW:
requires manual review.

If:
unit mismatch
→ FORCE REVIEW

==================================================
MANDATORY ITEM STRUCTURE
==================================================

Each item MUST store:

{
  raw_text,
  normalized_text,
  matched_item_id,
  confidence,
  qty,
  unit,
  weight_kg,
  purchase_rate,
  selling_rate,
  delivered_rate,
  bilty_rate,
  freight_rate,
  line_total,
  profit,
  aliases_used,
  user_corrected
}

==================================================
MANDATORY NORMALIZATION ENGINE
==================================================

Normalize:
- Malayalam
- Manglish
- shorthand
- OCR mistakes
- spacing
- unit aliases

Examples:

suger
→ sugar

bg
→ bag

kgs
→ kg

==================================================
MANDATORY SEARCH ENGINE
==================================================

Item field:
LIVE AUTOCOMPLETE

Search:
- item names
- aliases
- supplier-specific items
- recent purchases

Typing:
"sug"

Must instantly show:
- Sugar 50kg
- Sugar loose
- Sugar sack
- Sugar 1kg retail

with:
- unit
- supplier
- last rate

==================================================
MANDATORY SUPPLIER MATCH ENGINE
==================================================

Supplier matching uses:
- aliases
- phone
- previous bills
- broker relation
- fuzzy search

NEVER auto-create silently.

If unknown:
show:
"Create new supplier?"

==================================================
MANDATORY BROKER MATCH ENGINE
==================================================

Same strict rules as supplier.

==================================================
MANDATORY FINANCIAL ENGINE
==================================================

ALL TOTALS MUST BE BACKEND AUTHORITATIVE.

Frontend NEVER trusted.

Backend recalculates:
- bags
- kg
- line totals
- freight
- bilty
- commission
- margins
- totals
- profit

==================================================
REPORTS ENGINE RULES
==================================================

Dashboard MUST use:
same backend source as:
- purchase details
- reports
- charts

NO duplicate logic.

Single source of truth only.

==================================================
MANDATORY DELETE FLOW
==================================================

Delete purchase:
1. server delete
2. cache clear
3. state refresh
4. report refresh
5. chart refresh
6. totals refresh

==================================================
MANDATORY UI/UX RULES
==================================================

NO horizontal scroll.

NO overlap.

NO compressed buttons.

NO giant empty spaces.

NO broken viewport.

==================================================
IPHONE 16 PRO RULES
==================================================

Must optimize for:
393 x 852 viewport

Safe-area support mandatory.

==================================================
BOTTOM ACTION BAR RULES
==================================================

Sticky footer.

Buttons:
equal width
single line
large tap targets

NEVER wrap:
PDF
Print
Share

==================================================
ITEM TABLE RULES
==================================================

Replace tiny card layout.

Use:
ERP TABLE STYLE

Columns:
Item
Qty
Unit
P
S
Profit
Confidence

Expandable row:
- raw OCR
- aliases
- correction
- rates
- terms

==================================================
SCAN PAGE RULES
==================================================

Scan page should ONLY:
- upload image
- show progress
- preview extraction
- open wizard

NOT:
full purchase editing.

==================================================
PURCHASE FLOW RULES
==================================================

AI SCAN
→ Purchase Draft Wizard
→ Existing Purchase Flow
→ Final Create

DO NOT build separate broken flow.

REUSE:
existing manual purchase forms.

==================================================
PERFORMANCE RULES
==================================================

NO unnecessary refresh.

NO full page rerender.

Use:
- optimistic updates
- memoization
- pagination
- virtualization
- debounced search

==================================================
MANDATORY LOGGING
==================================================

Log:
- OCR raw
- normalized text
- match attempts
- rejected matches
- validation failures
- unit conflicts
- deleted IDs
- report calculations

==================================================
MANDATORY TRACKING FILES
==================================================

Cursor MUST ALWAYS UPDATE:

1. PROJECT_STATUS.md
2. TASKS.md
3. CURRENT_CONTEXT.md
4. BUGS.md
5. SCAN_ENGINE.md
6. MATCH_ENGINE.md
7. REPORT_ENGINE.md

==================================================
PROJECT_STATUS.md
==================================================

Contains:
- completed
- current work
- pending
- blockers
- architecture

==================================================
TASKS.md
==================================================

Contains:
- todo
- in progress
- completed
- priority

==================================================
CURRENT_CONTEXT.md
==================================================

Contains:
- current screen
- current bug
- current logic
- current architecture
- latest changes

==================================================
BUGS.md
==================================================

Contains:
- reproduction
- severity
- affected screens
- fix status

==================================================
SCAN_ENGINE.md
==================================================

Contains:
- OCR flow
- prompt
- normalization
- matching
- validation
- JSON schema

==================================================
MATCH_ENGINE.md
==================================================

Contains:
- alias logic
- fuzzy rules
- confidence rules
- rejection rules

==================================================
REPORT_ENGINE.md
==================================================

Contains:
- report formulas
- totals
- charts
- cache logic
- aggregation logic

==================================================
MANDATORY AI SCANNER GOAL
==================================================

FINAL SYSTEM MUST:

- support wholesalers
- support handwritten bills
- support Malayalam
- support multi-page bills
- support terms + charges
- support large invoices
- support supplier matching
- support broker matching
- support autocomplete
- support corrections
- support safe financial calculations

WITHOUT:
- broken totals
- wrong item matches
- wrong reports
- broken inventory
- fake profits
- duplicate purchases

==================================================
FINAL RULE
==================================================

This is:
REAL MONEY
REAL INVENTORY
REAL ACCOUNTING

Cursor must behave like:
senior ERP architect
+
inventory systems engineer
+
financial systems validator
+
AI OCR engineer

NOT:
UI demo builder.
