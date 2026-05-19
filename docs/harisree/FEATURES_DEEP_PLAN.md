# 🏭 HARISREE — OWNER VISIBILITY + STOCK PAGE TABS + DEEP FEATURES PLAN
## UX Wireframe · User Intent · Mobile Viewport · No Code
## Built from v13 codebase analysis — May 2026

---

## 🧠 USER INTENT MAP — WHO NEEDS WHAT

```
THREE USER TYPES — DIFFERENT GOALS EVERY TIME THEY OPEN THE APP:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OWNER (Sunil Sir) — opens app to CONTROL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Morning: "What came in today? What did my staff do?"
Midday:  "Which items are running low? Do I need to order?"
Evening: "What's today's total purchase value? Any issues?"
Weekly:  "Who's been active? What categories did I spend most on?"

MENTAL MODEL: Sunil is a supervisor + buyer. He makes purchase entries
AND needs to see everything staff touches in real time.

PAIN WITHOUT THIS FEATURE:
  - Staff updates stock physically (e.g. 45 → 60 bags)
  - Sunil doesn't know unless he calls them
  - Sunil also adds purchase (bought 20 bags from supplier)
  - No unified "what changed today" view

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MANAGER — opens app to EXECUTE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Enters purchases fast. Checks low stock. Prints barcodes.
Does NOT need analytics. Does NOT need user management.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
STAFF (warehouse worker) — opens app to VERIFY + UPDATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scans item. Updates physical count. Reports low stock.
Needs ONE TAP to camera. Nothing else matters.
```

---

---

## 📦 FEATURE 1 — TODAY'S STOCK ACTIVITY FEED (Owner's Most Needed View)

### What It Is

```
PROBLEM:
  Owner enters purchase: 20 BAGS Sugar → stock goes from 40 to 60 (auto, via apply_confirmed_purchase_stock)
  Staff does physical verification: counts 57 bags → updates to 57
  Another staff marks 3 bags damaged → reduces to 54
  
  Owner sees NONE of this clearly. Home shows a number. That's it.
  He doesn't know: did stock go up from my purchase? Did staff touch it? Is number right?

SOLUTION: TODAY'S STOCK DELTA FEED
  A live, chronological list of everything that moved stock today.
  Visible on owner home AND as a dedicated sub-page.
```

### Owner Home — New "Today's Stock" Section

```
PLACEMENT: Between the Quick Actions grid and the Low Stock Alert table on home page.

TITLE ROW:
  Left:  "TODAY'S STOCK MOVEMENT"  (12px ALL CAPS, grey)
  Right: "View All →"  (teal, 13px)  →  /stock/today-feed

LIVE BADGE: Small green pill "● LIVE" next to title
  Supabase realtime subscription on stock_audit table updates this feed instantly

FEED LIST (max 6 rows inline on home, then "View All"):

Each row layout (52px height):
  ┌─────────────────────────────────────────────────────┐
  │ [colored icon]  [item name]         [+20 BAG] [time]│
  │                 [who did it · reason]               │
  └─────────────────────────────────────────────────────┘

  Icon types + colors:
    📦 orange circle  = Purchase received (from Sunil's purchase entry)
    ✅ green circle   = Physical verification (staff count)
    🔧 grey circle    = Manual correction (owner/manager adjustment)
    ❌ red circle     = Damage/expired reduction

  Delta text:
    Increase: "+20 BAG" — bold green
    Decrease: "-3 BAG"  — bold red
    Same:     "= 45 BAG" — grey (no change verification)

  Who did it:
    If source = purchase:  "Purchase · Sunil · Sugar 50KG (ITM1022)"
    If source = staff:     "Verified by Ravi · Physical count"
    If source = correction:"Correction · Suresh · Damaged stock"

EMPTY STATE (if no movement today):
  Grey centered: "No stock changes yet today"
  Subtext: "Changes appear here instantly when purchases or updates are saved"
```

### Full Today's Feed Page

```
ROUTE: /stock/today-feed
ACCESSIBLE FROM: Home → "View All →" link, Stock page tab

LAYOUT:

AppBar:
  title: "Today's Stock Activity"
  subtitle: "[date]  ·  [total changes count] changes"
  actions: [filter icon] [calendar icon → pick different date]

DATE NAVIGATOR:
  ← Yesterday  |  Today (18 May)  |  → (disabled if today)
  Tap yesterday → loads that day's audit feed

FILTER CHIPS (horizontal scroll):
  [All] [📦 Purchases] [✅ Verified] [🔧 Corrections] [❌ Damage]

SUMMARY BAR (compact, 3 tiles):
  [+245 BAG added] [−15 BAG removed] [18 items changed]
  Color: green for additions, red for removals, blue for count

TIMELINE LIST (dense, full list):
  GROUP BY TIME BLOCK:
    "MORNING  9:00 AM – 12:00 PM"  (grey sticky header, ALL CAPS)
    "AFTERNOON  12:00 PM – 5:00 PM"
    "EVENING  5:00 PM – close"

  Each entry (64px):
    Left: colored icon circle (24px)
    Center:
      Line 1: Item name — 15px bold
      Line 2: "[old] → [new] (+/- diff [unit])" — 13px
      Line 3: By [name] · [reason] · [time] — 11px grey
    Right: net change badge "+20 BAG" (green) or "-3 BAG" (red)

  Tap row → opens item detail page for that item

DAILY SUMMARY CARD (pinned at bottom):
  Today total added: +245 BAG across 8 purchases
  Today total removed: -15 BAG (damage + corrections)
  Net change: +230 BAG  ← most useful number for owner
```

---

---

## 📊 FEATURE 2 — PURCHASE → STOCK LINK VISIBILITY

### The Gap That Exists

```
CURRENT STATE (what Cursor already built):
  ✅ apply_confirmed_purchase_stock() exists in stock_inventory.py
  ✅ When purchase saved → it auto-increments catalog current_stock
  ✅ Creates stock_audit entry with adjustment_type = 'purchase'
  
WHAT'S MISSING (owner can't see the link):
  ❌ On purchase detail page: doesn't show "This purchase added X BAG to stock"
  ❌ On item detail: recent purchases table exists BUT doesn't say "this purchase caused stock = X"
  ❌ On home feed: stock changes from purchases look same as manual changes
  ❌ No "purchase receipt" confirmation: "Stock updated: +20 BAG Sugar" after purchase save
```

### Purchase → Stock Confirmation UX

```
AFTER PURCHASE SAVE (purchase_entry_wizard_v2.dart success state):

CURRENT: shows "Purchase saved" success and navigates away
IMPROVE: show a "Stock Updated" confirmation card:

  ┌──────────────────────────────────────────────┐
  │  ✅  Purchase Saved                          │
  │                                              │
  │  STOCK UPDATED FOR 3 ITEMS:                  │
  │  ┌──────────────────────────────────────────┐│
  │  │ Sugar 50KG    +20 BAG  →  60 BAG total  ││
  │  │ Rice 25KG     +10 BAG  →  45 BAG total  ││
  │  │ Jeerakam 100G +50 PKT  →  200 PKT total ││
  │  └──────────────────────────────────────────┘│
  │                                              │
  │  [View Purchase] [Share PDF] [Done]          │
  └──────────────────────────────────────────────┘

This tells Sunil: "My purchase of 20 bags got added to stock."
No confusion. No need to check separately.
Auto-dismiss after 8 seconds if no action taken.
```

### Item Detail — Purchase-Source Badge in Stock History

```
FILE: catalog_item_detail_page.dart — Stock History timeline section

CURRENT: shows who updated + time + qty change
IMPROVE: show SOURCE BADGE inline in each history row:

  Green badge  [PURCHASE]     = came from a purchase entry
  Blue badge   [VERIFIED]     = physical count by staff
  Grey badge   [CORRECTION]   = manual adjustment
  Red badge    [DAMAGE]       = damaged/expired reduction

  Example row:
    ● "+20 BAG  (40 → 60)"    [PURCHASE]
      Sunil · ITM1022 · 14:32
      
    ● "+0 BAG  (60 → 57)"     [VERIFIED]
      Ravi · Physical count · 16:00
      Note: "-3 from expected" — system adds this automatically

  The "-3 from expected" NOTE is powerful:
    Expected after purchase: 60
    Counted by staff: 57
    System shows: "Variance: -3 BAG from purchase qty"
    This catches shrinkage/theft/miscounting
```

---

---

## 📊 FEATURE 3 — STOCK VARIANCE ALERT (New Feature)

### What It Is

```
BUSINESS PROBLEM: Sunil buys 20 bags. Staff counts 17 bags.
  3 bags "disappeared" — could be theft, miscounting, or damage not reported.
  Currently: no one notices unless they manually compare.

STOCK VARIANCE DETECTION:
  When purchase adds to stock → system logs expected stock (e.g. 60)
  When staff does physical verification → system compares to expected
  
  If variance > threshold (e.g. > 2% or > 2 units):
    → Create VARIANCE ALERT in notifications
    → Owner sees: "⚠ Sugar 50KG — 3 BAG variance (expected 60, found 57)"

WHERE IT SHOWS:
  1. Notification bell — badge count increases
  2. Owner Home — new "Stock Variances" card (red, shows count)
  3. Stock page — variance icon on affected rows
  4. Item detail — variance note in history timeline
```

### Variance Alert UX on Home

```
PLACEMENT: New card between Quick Actions and Today's Stock Feed on owner home

CARD (only shows when variances detected):
  ┌──────────────────────────────────────────┐
  │ ⚠ STOCK VARIANCES  ·  3 items          │
  │ Counted stock doesn't match purchase qty │
  │                                          │
  │ Sugar 50KG     Expected 60 · Found 57   │
  │ Rice 25KG      Expected 45 · Found 42   │
  │ Oil 5L         Expected 30 · Found 29   │
  │                                          │
  │ [Review All →]                          │
  └──────────────────────────────────────────┘

Background: very light red (#FFF5F5)
Border: red (#C62828) 1px
Dismissible: owner can dismiss for 24 hours
[Review All] → /stock/variances page
```

---

---

## 📱 STOCK PAGE — COMPLETE TABS + VIEWPORT PLAN

### Stock Page Tab Architecture

```
CURRENT: Single list with filter chips at top
PROBLEM: 500+ items, owner needs different VIEWS not just filters

REDESIGN: TabBar with 5 distinct views

TAB BAR (below AppBar, sticky):
┌──────┬──────┬──────┬──────┬──────┐
│ ALL  │ LOW  │TODAY │ CAT  │ SCAN │
│(504) │ (18) │ (12) │ EGORY│      │
└──────┴──────┴──────┴──────┴──────┘

TAB 1: ALL — full stock list (current behavior)
TAB 2: LOW — only low + critical (action-required list)
TAB 3: TODAY — today's changes feed (same as /stock/today-feed)
TAB 4: CATEGORY — group-by-category tree view
TAB 5: SCAN — quick scan entry (camera shortcut for staff)

Badge counts:
  ALL: total item count (504)
  LOW: low+critical count in orange/red (18) — updates realtime
  TODAY: today's change count (12) — updates realtime
  CATEGORY: none
  SCAN: none

Active tab: filled indicator, bold label
Inactive: grey text
Tab bar scrollable if screen is narrow (no wrap)
```

### TAB 1 — ALL ITEMS (Dense Warehouse Table)

```
TOP CONTROLS:
  Row 1: Search field (full width, 40px)
  Row 2: [Sort ↕]  [🔍 Filter ▾]  [count text right-aligned]
    Sort options in bottom sheet: Name A-Z | Stock Low→High | Stock High→Low | Recently Updated | Category
    Filter bottom sheet: Category picker + Status filter

TABLE HEADER (sticky, 32px, dark background):
  | ITEM          | STOCK   | REORDER | UNIT  |
  | flex:3        | 65px    | 60px    | 45px  |
  Background: #37474F white text 11px bold ALL CAPS

EACH ROW (56px height):
  Left status bar: 4px colored vertical bar
    green | orange | red | grey
  
  COL 1 — Item:
    Name: 14px semibold, max 1 line, ellipsis
    Subtext: category · code  (11px grey)
  
  COL 2 — Stock:
    Number: 15px bold, status color
    Unit below: 10px grey
  
  COL 3 — Reorder:
    Number: 13px grey
    "≈ OK" or "⚠ Low" below: 10px status color
  
  COL 4 — Unit:
    Unit type: 12px
    Last update: 10px grey (time ago)

ROW INTERACTIONS:
  Tap → /catalog/item/:id (item detail)
  Long press → action sheet:
    [📦 Update Stock]
    [🖨 Print Barcode]
    [📋 View History]
    [📝 Add to Reorder]
    [✕ Cancel]
  Swipe right → Update Stock sheet (Dismissible, confirmDismiss=false, just opens sheet)

LOAD MORE:
  Load 50 initially. Scroll to bottom → load next 50 (append, don't replace).
  Loading spinner (24px) at bottom while fetching.
  "✓ All 504 items loaded" when complete.
  
REALTIME:
  Green "● LIVE" pulse indicator in AppBar subtitle
  When stock_audit insert fires → affected row flashes green 300ms
```

### TAB 2 — LOW STOCK (Action Required)

```
PURPOSE: Owner/staff opens this every morning. These items need ordering TODAY.

NO search needed here — the list is already filtered to critical items only.

TOP BANNER:
  ┌────────────────────────────────────────────────────┐
  │ ⚠  18 items need attention                       │
  │ 6 CRITICAL  ·  12 LOW  ·  Last checked 2 min ago │
  └────────────────────────────────────────────────────┘
  Background: light orange. Refresh on pull-to-refresh.

SORT TABS (inline, horizontal chips):
  [Most Critical] [Biggest Deficit] [By Supplier] [By Category]
  
  Most Critical: stock/reorder ratio ascending (closest to 0 first)
  Biggest Deficit: (reorder - stock) descending (needs most units first)
  By Supplier: group by supplier for easy ordering
  By Category: group by category

EACH ROW (72px — bigger than normal, needs attention):
  Left: status bar (RED for critical, ORANGE for low)
  Content:
    Line 1: Item name — 16px bold
    Line 2: "Stock: 5 BAG  ·  Reorder: 20 BAG  ·  Deficit: 15 BAG" — 13px
    Line 3: Supplier: Everest Traders  ·  Rack: B-04 — 12px grey
  Right: [Order] button (44×32px, outlined, teal)
    Tap [Order] → opens "Add to Reorder List" bottom sheet immediately

BOTTOM ACTION (sticky, pinned):
  [📝 Add All Critical to Reorder List] — filled red button
  Only adds items with 'critical' status to reorder list in one tap
  
  Bulk action: powerful for morning routine — owner sees 6 critical items → one tap → all 6 in reorder list

BY SUPPLIER GROUP VIEW (when "By Supplier" sort selected):
  STICKY SECTION HEADER for each supplier:
    ┌──────────────────────────────────────────────────────┐
    │ EVEREST TRADERS  ·  4 items need ordering           │
    │ [Add All 4 to Reorder] ›                            │
    └──────────────────────────────────────────────────────┘
  Under it: all items from that supplier needing stock
  
  This is how real wholesale ordering works:
  Sunil calls Everest → "I need Sugar, Rice, Oil, Jeerakam"
  He sees all 4 grouped together, not scattered in a 500-item list
```

### TAB 3 — TODAY'S CHANGES (Exact Same as /stock/today-feed)

```
Same layout as described in Feature 1 — Today's Feed.
No duplication — reuse the same widget, same API endpoint.

KEY ADDITIONS FOR STOCK PAGE CONTEXT:
  "From Purchase" entries are tappable → opens that purchase detail
  "By Staff" entries are tappable → opens staff activity for that person
```

### TAB 4 — CATEGORY VIEW (Tree/Group)

```
PURPOSE: Owner wants to see "how much Grains do I have? How much Spices?"
Category-level overview, not item-level.

TOP SUMMARY (compact row):
  Total items: 504  |  Total categories: 8  |  Items with issues: 18

CATEGORY LIST (not a table — card groups):

Each category group:
  ┌────────────────────────────────────────────────────────────┐
  │ 🌾 GRAINS                              120 items          │
  │ ████████████████░░░░  82% healthy                         │
  │ 🟢 98 OK  ·  🟠 12 Low  ·  🔴 10 Critical  ·  ⚫ 0 Out  │
  │ ▼ Expand to see items                                      │
  └────────────────────────────────────────────────────────────┘
  
  Background: white card, shadow
  Progress bar: fills proportionally with healthy stock %
  Color: green if > 80% healthy, orange if 50-80%, red if < 50%
  
  EXPAND (tap card or ▼):
    Shows sub-list of items in that category
    Same row style as TAB 1 but indented 8px
    Sub-header row: subcategory name (grey, ALL CAPS)

SUBCATEGORY GROUPING:
  Within an expanded category:
    ── Rice Varieties (15 items) ──
      [item rows]
    ── Wheat Varieties (8 items) ──  
      [item rows]

EMPTY CATEGORY:
  "No items in this category" grey text
  [+ Add Item] button (to add first item in this category)
```

### TAB 5 — SCAN (Staff Quick Entry)

```
PURPOSE: In staff shell, the bottom nav has Scan tab. In owner shell stock page,
this tab is a quick-access camera without leaving the stock context.

FULL SCREEN CAMERA opens within the tab (not navigation):
  Same as barcode_scan_page.dart but embedded in tab
  After scan: shows item detail as a bottom sheet OVER the stock page (not navigation)
  Staff can scan multiple items without going back to list each time
  
  SCAN RESULT BOTTOM SHEET (half screen, draggable):
    Item name + code
    Current stock (large, status color)
    [📦 Update Stock] [📋 History] [✕ Close]
    
  WORKFLOW: Staff holds phone, scans items one by one
    → Sheet pops up → update stock → swipe down → scan next
    Never navigates away from stock page
    
  RECENT SCANS (below camera area, 3 most recent):
    Chips showing last 3 scanned items
    Quick re-access without re-scanning
```

---

---

## 📊 FEATURE 4 — PURCHASE ENTRY LIVE STOCK PREVIEW

### The Problem During Purchase Entry

```
CURRENT FLOW:
  Sunil enters purchase: 20 bags Sugar from Everest
  He sees: price, GST, total amount
  He does NOT see: current stock before purchase

WHY THIS MATTERS:
  He might not realize he already has 200 bags (overstock)
  He might not realize he has only 5 bags (urgent, should buy more)
  He's entering blindly without stock context

SOLUTION: Show current stock DURING item selection in purchase wizard
```

### Item Entry Form — Stock Context Badge

```
DURING purchase item entry (item_entry_minimal_form.dart):
WHEN user selects an item or types item name:

  ABOVE the rate/qty fields, show a compact stock context bar:
  
  ┌──────────────────────────────────────────────────────────┐
  │ 📦 CURRENT STOCK: 5 BAG  ·  Reorder: 20 BAG            │
  │ ⚠ LOW STOCK — buying more is recommended                │
  └──────────────────────────────────────────────────────────┘
  (light orange background if low/critical, light green if healthy)
  
  This shows the MOMENT user picks the item.
  Source: stockItemDetailProvider (already exists in stock_providers.dart)

LIVE TOTAL PREVIEW (during qty entry):
  When qty field has value:
  
  ┌──────────────────────────────────────────────────────────┐
  │ After this purchase:                                     │
  │ Stock: 5 BAG  +20 BAG purchased  =  25 BAG total       │
  │ Status: 🟠 Still low (need 20 to reach reorder level)   │
  └──────────────────────────────────────────────────────────┘
  
  This tells Sunil: "Even after buying 20, you're still low."
  He might decide to buy more on the same purchase.

VISUAL: Small, below item picker, above price fields.
  Non-intrusive — soft background, 12px text.
  Never blocks or overlaps price/qty fields.
```

---

---

## 📊 FEATURE 5 — STAFF TASK BOARD

### What It Is

```
PROBLEM: Owner wants to ASSIGN tasks to staff.
  "Ravi, verify the spices section today"
  "Suresh, count all sugar stock"
  "Deepu, print labels for new items"
  
Currently: Owner calls them. No record. No completion tracking.

SOLUTION: Simple task board (NOT project management — very simple)
```

### Staff Task Board UX

```
ROUTE: /tasks
ACCESSIBLE FROM: Owner home Quick Actions [📋 Tasks] button + Staff home [My Tasks] section

OWNER VIEW — TASK MANAGER:
  AppBar: 'Tasks'  actions: [+ Add Task]

  SECTIONS:
    PENDING (3)  |  IN PROGRESS (1)  |  DONE TODAY (5)

  Each task row (72px):
    Left: priority dot (red=urgent, orange=normal, grey=low)
    Content:
      Line 1: Task title — 15px bold  ("Verify Rice stock section B")
      Line 2: Assigned to: Ravi  ·  Due: Today 5 PM — 12px grey
      Line 3: Section: Stock / Barcode / Purchase — 11px grey badge
    Right: status badge [PENDING] / [DONE ✓]
    
  Tap row → task detail (see progress, mark done)
  Long press → [Edit] [Reassign] [Delete]

ADD TASK BOTTOM SHEET:
  Title (text field)
  Assign to: (staff selector — shows staff list with online indicator)
  Category: [Stock Check] [Barcode Print] [Purchase Entry] [Other]
  Priority: [Urgent] [Normal] [Low] toggle
  Due: [Today] [Tomorrow] [Custom date]
  Notes: (optional text)
  [Create Task] button

STAFF VIEW — MY TASKS:
  On staff home page, a new section:
  
  "MY TASKS TODAY" section (shows 3 max inline):
    Each row: task title + [Mark Done] button
    [Mark Done] → sends completion to owner + removes from staff list
    
  If no tasks: "No tasks assigned today" grey text (hidden section)
  
  Tap task → opens task detail:
    Description, notes from owner, due time
    [Mark as Done] large button
    [Add note] (staff can add completion note: "counted 47 bags, found 2 damaged")

OWNER NOTIFICATION:
  When staff marks task done → notification to owner:
    "✅ Ravi completed: Verify Rice stock section B
     Note: 47 bags, 2 damaged"
```

---

---

## 📊 FEATURE 6 — DAILY STOCK REPORT (WhatsApp / PDF)

### What It Is

```
OWNER NEED: Every evening, Sunil wants one summary:
  - What came in today (purchases)
  - What changed (staff updates)
  - What's still low
  - What needs ordering

Currently: He has to go into 3 different pages and piece this together.
Solution: One-tap daily stock summary, shareable via WhatsApp.
```

### Daily Report UX

```
TRIGGER LOCATIONS:
  1. Owner home → Quick Actions → [📊 Daily Report] button
  2. Reports page → AppBar → [Today's Report]
  3. Automated: backend APScheduler sends at 7 PM every day (if WhatsApp configured)

DAILY REPORT MODAL (bottom sheet, full scroll):
  Title: "Stock Report — 18 May 2026"
  Subtitle: "Generated 6:00 PM"

  SECTION 1: TODAY'S PURCHASES (from purchase history)
    Total: ₹45,200 across 3 purchases
    Items purchased:
      Sugar 50KG    20 BAGS   ₹1,850/bag   = ₹37,000
      Rice 25KG     10 BAGS   ₹820/bag     = ₹8,200

  SECTION 2: STOCK UPDATES BY STAFF
    8 updates by 2 staff members
    Ravi: 5 verifications, 1 damage report
    Suresh: 2 corrections

  SECTION 3: CURRENT LOW STOCK (snapshot)
    18 items below reorder level
    [View list] expandable

  SECTION 4: VARIANCES TODAY (if any)
    Sugar 50KG: Expected 60, Found 57 — Variance -3

  ACTION BUTTONS:
    [📤 Share via WhatsApp] — opens WhatsApp with pre-formatted text
    [📄 Download PDF] — generates PDF with same data
    [✕ Close]

WHATSAPP FORMAT:
  *HARISREE STOCK REPORT — 18 May 2026*
  
  📦 TODAY'S PURCHASES: ₹45,200
  • Sugar 50KG × 20 BAGS — Everest Traders
  • Rice 25KG × 10 BAGS — Everest Traders
  
  📊 STOCK UPDATES: 8 changes by staff
  
  ⚠ LOW STOCK: 18 items need ordering
  
  ❗ VARIANCES: Sugar (-3 BAGS)
  
  _Harisree Agency · HexaStack_
```

---

---

## 📊 FEATURE 7 — QUICK REORDER (One Tap from Low Stock)

### Problem

```
CURRENT LOW STOCK FLOW (too many steps):
  Owner sees Low Stock list → selects item → goes to item detail → 
  taps "Add to Reorder" → opens bottom sheet → confirms → 
  repeat for every low item

This is 5 taps per item. 18 low items = 90 taps.
```

### Redesigned Reorder Flow

```
ON STOCK PAGE LOW TAB:
  Each low item row has [Order] button (32px height, small)
  
  TAP [Order] on any item:
    NOT a new page. NOT a bottom sheet.
    INLINE CONFIRMATION (expand row 2 lines):
      "+[   ] BAG  →  [Confirm] [Cancel]"
      Pre-filled with: (reorder_level - current_stock) as suggested qty
      User can change the number inline
      Tap Confirm → adds to reorder list → row collapses → shows "📋 In Reorder"
    
    Total time: 3 taps, 10 seconds per item
    vs current: 5 taps, 30 seconds per item

SELECT MULTIPLE + BULK REORDER:
  Long press any row → enters selection mode
  Checkboxes appear on all rows
  Select multiple items
  Bottom sticky bar: "[X items selected] [📝 Add All to Reorder]"
  One tap → all selected items added to reorder list
  Total time: 3 taps for any number of items
```

---

---

## 📊 FEATURE 8 — ITEM PHOTO + LABEL (Visual Catalog)

### What It Is

```
WAREHOUSE PROBLEM: Item names like "ITM1022" mean nothing.
  New staff doesn't know what "Jeerakam 100GM ITM1243" looks like.
  Wrong items get pulled from racks.

SOLUTION: Item photos in catalog and on barcode labels
```

### Photo Feature UX

```
ITEM DETAIL PAGE — photo section:
  TOP of page (or side of header):
    Image: 72×72 rounded (already in layout)
    But: most items have no image currently
    
  WHEN NO IMAGE:
    Show grey box with item initials or category icon
    Tap → [📷 Take Photo] [🖼 Choose from Gallery] options
    
  WHEN HAS IMAGE:
    Show image
    Tap → full screen view
    Long press → [Change Photo] [Remove Photo]

BARCODE LABEL WITH PHOTO:
  Large label size (100×50mm): add small item photo (20×20mm) 
  in top-left corner of label
  Staff reading label in warehouse immediately recognizes item
  
  This is a premium feature — add as toggle in print options:
    "Include item photo on label" switch (disabled if no photo)

CATALOG QUICK PHOTO DURING ITEM CREATE:
  catalog_add_item_page.dart — image picker field (already planned)
  Make it the SECOND field after item name (not last)
  Visual catalog is much better than text-only
```

---

---

## 📊 FEATURE 9 — STOCK HEALTH SCORE (Simple KPI)

### What It Is

```
OWNER NEED: One number that tells him "is my stock situation good or bad today?"

STOCK HEALTH SCORE: 0–100

CALCULATION:
  Start at 100
  -3 points per CRITICAL item (stock ≤ 50% of reorder)
  -1 point per LOW item (stock < reorder)
  -5 points per OUT OF STOCK item
  Maximum deduction: 60 points (score floor = 40 if everything is low)
  
  Example: 18 low items, 6 critical, 0 out of stock
    100 - (18×1) - (6×3) - (0×5) = 100 - 18 - 18 = 64/100
    Label: "Fair" (60-75)

HEALTH SCORE LABELS:
  90–100: Excellent 🟢
  75–89:  Good 🟢
  60–74:  Fair 🟡
  40–59:  Low 🟠
  0–39:   Critical 🔴

WHERE IT SHOWS:
  Owner Home: large score number in a circular arc gauge (small, right side of header)
  Stock page header: small score badge "Score: 64"
  
  Tap score → opens explanation: "6 critical items are lowering your score"
  
  Not a complex analytics feature — just one number.
  Tells owner at a glance if things are ok.
```

---

---

## 📊 FEATURE 10 — ITEM ALIAS / ALTERNATIVE NAME

### What It Is

```
REAL BUSINESS PROBLEM:
  "Jeerakam" = "Cumin" = "Jeera" — all the same item
  "Coconut Oil" = "Vennennai" = "Thengaennai"
  
  Staff from different regions use different names.
  When staff types "Jeera" → can't find "Jeerakam" in catalog.
  Duplicate items get created.

SOLUTION: Item aliases (alternative names)
```

### Alias UX

```
ITEM DETAIL PAGE — new "Also known as" section:
  Below item name:
    "Also known as: Cumin · Jeera · ജീരകം"
    Small grey chips, scrollable horizontal row
    [+ Add alias] tap → text field to add new alias

ITEM CREATE — duplicate detection uses aliases:
  When typing "Jeera" → fuzzy check finds alias match → shows warning:
    "⚠ 'Jeera' is an alias for 'Jeerakam 100GM' — use existing?"
    [Yes, use Jeerakam] [No, create new]

SEARCH uses aliases:
  Searching "Cumin" → finds "Jeerakam 100GM" (via alias)
  This makes search much more useful for multilingual warehouse context
  
BARCODE SCAN RESULT:
  If item has aliases: show below item name in small grey text
  "Also: Jeera · Cumin"
```

---

---

## 📱 MOBILE-SPECIFIC UX IMPROVEMENTS — VIEWPORT PLAN

### Suggestion Field — Final Spec (All Devices)

```
CRITICAL: Fix this before any other UX work.
Applies to: Supplier field, Broker field, Item search, Category search

VIEWPORT BEHAVIOR:

iPhone SE (375px, small):
  Field at bottom 40% of screen → list anchors ABOVE field, max height 160px
  Field at top 60% of screen → list anchors BELOW field, max height 160px
  Max 3 visible suggestions before scroll

iPhone 14 Pro (393px, Dynamic Island):
  Same logic, but account for 59px top safe area in position calculation
  Max 4 visible suggestions before scroll

iPhone Plus/Max (430px):
  Max 5 visible suggestions before scroll

Android (varied height):
  Use MediaQuery.viewInsetsOf(context).bottom for keyboard height
  Recalculate anchor point on keyboard open (add listener)

SUGGESTION ITEM HEIGHT: 48px minimum (Apple HIG touch target)
SUGGESTION TEXT: 14px item name + 11px code/detail below
HIGHLIGHT: bold the matching characters in suggestion text
SCROLL INDICATOR: show ScrollBar always (not just on scroll)
  warehouse users need to see there are more items below

EMPTY STATE in suggestions:
  "No items found — [+ Create 'Sugar 50KG']" with one-tap create
  This prevents duplicate creation AND makes create faster
```

### Form Field Focus — Auto-Scroll Spec

```
EVERY FORM must auto-scroll the focused field to visible position above keyboard.

PATTERN (every form page):
  When any TextField gains focus:
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        focusNode.context!,
        alignment: 0.5,  // center field in visible area
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });

FIELDS THAT NEED THIS URGENTLY:
  1. purchase_party_step.dart — broker field (often at bottom)
  2. item_entry_minimal_form.dart — tax field (at bottom of form)
  3. catalog_add_item_page.dart — rack/location field (last in list)
  4. backup_page.dart — any date fields

NEVER USE: fixed bottom padding to hack this
ALWAYS USE: Scrollable.ensureVisible — it's the correct Flutter pattern
```

### Bottom Button — Never Behind Keyboard Spec

```
ALL FORMS WITH A SAVE/SUBMIT BUTTON:

PATTERN A (short form — button visible without scroll):
  Scaffold(
    body: SingleChildScrollView(child: formContent),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: saveButton,
      ),
    ),
  )
  Setting resizeToAvoidBottomInset: true on Scaffold makes bottom nav
  rise above keyboard automatically.

PATTERN B (long form — button inside scroll):
  Column(children: [
    Expanded(child: SingleChildScrollView(child: formContent)),
    // This container ALWAYS stays above keyboard:
    AnimatedPadding(
      duration: Duration(milliseconds: 150),
      padding: EdgeInsets.only(
        bottom: max(MediaQuery.viewInsetsOf(context).bottom, 
                    MediaQuery.viewPaddingOf(context).bottom) + 8,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: saveButton,
      ),
    ),
  ])

NEVER: Column(...) + Positioned or Stack for button → always fails on keyboard open
```

---

---

## 📊 ALL NEW FEATURES SUMMARY — PRIORITY MATRIX

```
FEATURE                          OWNER VALUE   STAFF VALUE   BUILD EFFORT
─────────────────────────────────────────────────────────────────────────
1. Today's Stock Activity Feed   ⭐⭐⭐⭐⭐    ⭐⭐          Medium
2. Purchase→Stock Link Visible   ⭐⭐⭐⭐⭐    ⭐⭐⭐        Easy (UI only)
3. Stock Variance Alert           ⭐⭐⭐⭐⭐    ⭐⭐⭐        Medium
4. Purchase Live Stock Preview    ⭐⭐⭐⭐      ⭐⭐⭐⭐      Easy
5. Staff Task Board               ⭐⭐⭐⭐      ⭐⭐⭐⭐⭐    Hard
6. Daily WhatsApp Report          ⭐⭐⭐⭐⭐    ⭐            Easy (PDF exists)
7. Quick Reorder (1-tap)          ⭐⭐⭐⭐⭐    ⭐⭐⭐        Easy
8. Item Photo + Label Photo       ⭐⭐⭐        ⭐⭐⭐⭐      Medium
9. Stock Health Score             ⭐⭐⭐⭐      ⭐⭐          Easy
10. Item Aliases                  ⭐⭐⭐        ⭐⭐⭐⭐      Medium
─────────────────────────────────────────────────────────────────────────

BUILD ORDER:
  TODAY: Feature 2 (UI only — just show stock in purchase form) + Feature 7 (inline reorder)
  WEEK 1: Feature 1 (today feed) + Feature 4 (purchase stock preview)
  WEEK 2: Feature 3 (variance) + Feature 6 (daily report)
  WEEK 3: Feature 9 (health score) + Feature 8 (photo)
  LATER: Feature 5 (tasks) + Feature 10 (aliases) — bigger builds
```

---

---

## 📊 STOCK PAGE TABS — CURSOR PROMPT SPEC

```
PASTE THIS INTO CURSOR:

"Update stock_page.dart to add a TabBar with 5 tabs: ALL | LOW | TODAY | CATEGORY | SCAN.

Read HARISREE_UIUX_WIREFRAME_PROMPTS.md stock page section first.

TAB ARCHITECTURE:
  Use DefaultTabController(length: 5) wrapping the page.
  Preserve ALL existing stock_page.dart logic — only add the TabBar and tab content switching.
  
  Tab 1 (ALL): existing stock list — no change
  Tab 2 (LOW): same stock list but stockListQueryProvider pre-set to status='low'
               Add top banner showing low+critical count
               Add sticky [Add All Critical to Reorder] button at bottom
  Tab 3 (TODAY): show stockAuditRecentHomeProvider data (already exists)
                 Display as dense timeline (see today-feed UX spec)
  Tab 4 (CATEGORY): use categoriesListProvider to show grouped view
                     Each category as expandable card
  Tab 5 (SCAN): embed BarcodeScanPage camera as a widget inside the tab
                On scan result: show item bottom sheet (not navigation)

BADGE COUNTS on tabs:
  LOW tab: stockAlertCountsProvider.low — update in realtime
  TODAY tab: stockAuditRecentHomeProvider.length
  
DO NOT: create new providers — use existing ones only
DO NOT: break existing stock list behavior
DO NOT: hardcode colors — use HexaColors tokens"
```

---

*Harisree Agency — Owner Visibility + Stock Tabs + Deep Features Plan*  
*HexaStack Solutions — Anandu, Thrissur, Kerala · May 2026*
