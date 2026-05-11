# PURCHASE ASSISTANT v14 — FULL AUDIT + CLIENT FEATURE PLAN
> Codebase: 258 Dart files | Screenshots: 3 | Date: 2026-05-11
> Client: Harisree Purchases | Owner-facing app (live with real clients)

---

## 📸 SCREENSHOT ANALYSIS → ROOT CAUSES

### Screenshot 1 — Home Dashboard (Month selected)
**What's visible:** `₹66,38,105` total, `1,303 BAGS • 10 BOXES • 1 TIN • 1,03,367 KG` showing in header chips. The **donut chart ring is empty (gray)**. Tabs: Category/Subcategory/Supplier/Items visible. Text: "Loading Items breakdown…"

**Root cause:** The `_homeDashboardPullFresh` function has a **two-phase architecture**:
- Phase 1: `api.reportsHomeOverview()` → returns compact summary (totals + unit counts) → shows header immediately ✅
- Phase 2: When `_snapshotHasTradeActivity` is true but `item_slices` from snapshot is empty → falls through to `_fetchTradePurchasesForHomeRange` + `catalogItemsListProvider` + `aggregateHomeDashboard()` locally → THIS IS SLOW (fetching 500+ records + catalog in series)

The donut ring waits for Phase 2. The `homeDashboardDataProvider` NotifierProvider already shows Phase 1 data (hence the correct totals) but `state.refreshing` stays `false` while Phase 2 runs — there is NO second `refreshing` signal for Phase 2. The donut receives partial `HomeDashboardData` with `itemSlices: []` and shows empty.

**Fix:** Add a `breakdownLoading` flag to `HomeDashboardDashState`. Set it `true` when Phase 1 data arrives but Phase 2 is still computing. Drive the donut + breakdown tabs off this flag.

### Screenshot 1 — "Today" Tab Shows Only Loading
**Root cause:** `HomePeriod.today` uses `from = today 00:00, to = today 23:59`. The `reportsHomeOverview` API call includes `compact: true` with today's date range. When the day has 0 purchases, `_snapshotHasTradeActivity(fromSnapshot)` returns `false` → falls through to `_fetchTradePurchasesForHomeRange` → fetches 0 purchases → returns `HomeDashboardData.empty`. BUT the `homeDashboardSyncCacheProvider` can't serve a cache for today (today's key doesn't exist in offline store) → `seed = HomeDashboardPayload(data: HomeDashboardData.empty)` → `refreshing = true` → shows forever-loading skeleton.

**Fix:** `refreshing` must be `false` after `_homeDashboardPullFresh` completes even when result is empty. The state assignment `state = HomeDashboardDashState(snapshot: payload, refreshing: false)` does run — but only AFTER the full two-phase fetch. The Today view shows loading the entire time. Fix: show `HomeDashboardData.empty` immediately with `refreshing: false` when `from == to` (today) and Phase 1 returns empty.

### Screenshot 2 — Search "sugar"
**What's visible:** "SUGAR 50 KG" shows `Last buy ₹42 · Last sell ₹43 · 40000 kg · PUR-2026-0001`. **Last purchase data is already showing** ✅ 

**Missing:** No date, no "X days ago". Client wants: `"Apr 27 · 14 days ago"` under last purchase info.

**Missing in category/subcategory rows:** The "SUGAR — Under Essentials" type row shows NO purchase summary (bags/kg/total).

### Screenshot 3 — GOPI&CO Supplier Detail
**What's visible:** Supplier detail page with purchase history, items, amounts. **Good data.** 

**Missing:** No "Delivered?" status on each bill. No follow-up flag.

---

## 🔴 BUG REGISTRY (from code + screenshots + client report)

### BUG-001 · Dashboard Donut Empty — "Loading Items breakdown..." Stuck
**Severity:** P0 | **File:** `lib/core/providers/home_dashboard_provider.dart`
The `itemSlices` list is empty in Phase 1 snapshot. Phase 2 aggregation happens but no progress signal. Donut shows gray forever.

### BUG-002 · Dashboard "Today" Tab — Infinite Loading  
**Severity:** P0 | **File:** `lib/core/providers/home_dashboard_provider.dart`
`HomePeriod.today` with no cache shows `refreshing: true` forever until full 2-phase fetch completes. On 0-purchase day, shows empty + spinner forever.

### BUG-003 · Dashboard Tabs Very Slow (Category/Subcategory/Supplier/Items)
**Severity:** P1 | **File:** `lib/features/home/presentation/home_page.dart` + `home_breakdown_tab_providers.dart`
Breakdown tabs rebuild when `homeDashboardDataProvider` rebuilds. Each tab re-renders on period chip switch, pulling all breakdown data synchronously. No memoization per tab.

### BUG-004 · Draft Filter in Purchase History — Not Showing WIP Drafts
**Severity:** P1 | **File:** `lib/features/purchase/presentation/purchase_home_page.dart`
The "Draft" filter chip calls `_selectPrimary('draft')` → sets `primary = 'draft'` → but `purchaseHistoryVisibleSortedForRef` never filters by `primary == 'draft'`. The `listTradePurchases` API is called with `status: 'all'` — it returns server-confirmed purchases, not Hive local drafts. Local WIP draft appears only as a banner row (`_LocalWipDraftHistoryRow`) — not in the filtered list. Tapping "Draft" shows the banner but no filter logic applies.

**Fix:** When `primary == 'draft'`, show ONLY the local WIP banner row and any server-side `status: draft` purchases from API.

### BUG-005 · Global Search — User-Created Categories/Subcategories Not Showing
**Severity:** P1 | **File:** `lib/features/search/presentation/search_page.dart` + backend `/v1/search`
`catalog_subcategories` in search results comes from backend. If user created a custom category/subcategory, it may not be indexed in the search service or the query filters to seeded items only.

### BUG-006 · Search Rows Missing Last Purchase Date / Days Ago
**Severity:** P1 | **File:** `lib/features/search/presentation/search_page.dart` lines 265–305
`lastLineByItemId` is populated but only `last_buy/last_sell price` is shown. No date or "days ago" display in UI for catalog item rows.

### BUG-007 · Search Category/Type Rows Missing Unit Totals (Bags/KG/Box/Tin)
**Severity:** P2 | **File:** `lib/features/search/presentation/search_page.dart`
Category and subcategory (`catalog_subcategories`) result rows show only name and parent. No totals (bags, kg, boxes, tins, amounts) shown per row.

### BUG-008 · AI Chatbot Preview — Single-Item Only, No Table, Not Editable
**Severity:** P1 | **File:** `lib/features/assistant/presentation/widgets/preview_card.dart`
`PreviewCard.parse()` only reads `lines.first`. Multi-item purchases show only 1 item. No table layout showing all items. Fields are not editable in the preview — user must re-type to correct.

### BUG-009 · Purchase Item Create Flow — HSN Blocks (Partial — Already Fixed in v14)
**Severity:** Fixed in v14. Verify `purchaseLineSaveBlockReason` now reads `if (tax > 0)` only.

---

## ✅ NEW FEATURES REQUESTED BY CLIENT

---

### FEATURE-A · Delivery Tracking — Yes/No Per Purchase
**Business need:** Client orders items from suppliers. Items take 1–5 days to arrive. Client forgets which orders haven't arrived yet. Needs to mark: "Is this purchase delivered to my warehouse?"

**Data model change:**
```sql
ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS is_delivered BOOLEAN DEFAULT FALSE;
ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS delivery_notes TEXT;
```

**Flutter changes:**
1. `TradePurchase` model: add `isDelivered`, `deliveredAt`, `deliveryNotes` fields
2. After each purchase save: show a bottom sheet "Did this arrive at your warehouse?" with [Not Yet] [Yes, Received] buttons. Default = "Not Yet". Dismissible.
3. `purchase_detail_page.dart`: add delivery status chip (green ✅ Received / orange 🚚 Pending). Tap → toggle with confirmation.
4. `purchase_home_page.dart`: add "Pending Delivery" filter chip. Shows only undelivered confirmed purchases.
5. Dashboard home: add "Pending Arrivals: X bills" alert card when `is_delivered = false` count > 0.
6. Supplier detail page: each bill row shows delivery status badge.
7. New API endpoint: `PATCH /v1/businesses/{bid}/trade-purchases/{id}/delivery` body: `{is_delivered: bool, delivery_notes: str}`

**UX flow for each new purchase:**
```
Save purchase → Success sheet → 
Bottom sheet appears: "🚚 Has this shipment arrived?"
[Later]   [✅ Yes, Mark as Received]
```

---

### FEATURE-B · Search Rows — Last Date + Days Ago + Unit Totals
**For catalog item rows in search:**
- Add: `last_purchase_date` field from server (or compute from `recent_purchases` bills)
- Display: `"Apr 27 · 14 days ago"` below last buy/sell rates
- Show unit quantities in item row: `"40,000 kg · PUR-2026-0001"`

**For category/subcategory type rows in search:**
- Show aggregate totals for the matched period (last 30 days): `"124 bags · 62,000 kg · ₹28,500"`
- Backend: add `total_bags`, `total_kg`, `total_boxes`, `total_tins`, `total_amount` fields to `catalog_subcategories` search results

**For supplier rows in search:**
- Show: last purchase date + total bills count + total amount

---

### FEATURE-C · Fast Item Creation from Home Dashboard
**Client need:** Quick button on home to create a new item without navigating deep into Contacts > Catalog.

**Flow:**
```
Home dashboard → FAB shows 2 options (+ and scan already)
Add 3rd quick action: "Add Item" icon (📦)

Tap "Add Item" →
Bottom sheet: 
  Step 1: Search/select Subcategory (searchable, shows user-created + seeded)
  Step 2: Item name (text input + smart duplicate check)
  Step 3: Default unit (bag/kg/box/tin) + kg per bag (if bag)
  [Save] → creates item, shows toast "Item created. Add to a purchase?"
  [Create Purchase] button → navigates to purchase wizard with this item pre-filled
```

**Rule:** Item name uniqueness check: `SELECT id FROM catalog_items WHERE business_id = $1 AND LOWER(name) = LOWER($2)` → if exists, show "Item already exists. Open it?" with options.

---

### FEATURE-D · Batch Item Creation (Linked to Supplier/Broker)
**Client need:** When buying from Surag (supplier), he has 15 items. Every time entering a purchase he has to create items one by one and link supplier. Needs: select supplier once → create multiple items in one flow.

**New flow: "Add Items for Supplier" from supplier detail page:**
```
Supplier Detail (GOPI&CO) → 3-dot menu → "Add Items for This Supplier"

Opens: ItemBatchCreatePage
  - Supplier/Broker auto-filled from context (locked)
  - Item list (dynamic, addable rows):
    Row: [Item Name] [Subcategory] [Default Unit] [Kg/Bag] [Add Another ➕]
  - [Save All Items] button at bottom
  - Creates N items in batch, links supplier defaults
```

**Backend:** `POST /v1/businesses/{bid}/catalog-items/batch` body: `{items: [{name, subcategory_id, default_unit, default_kg_per_bag, default_supplier_id}]}`

---

### FEATURE-E · AI Chatbot — Full Purchase Preview + Editable Table
**Current problem:** Preview shows only 1 item in a tiny card. Not editable. WhatsApp-style input not connected to real OpenAI/Gemini call.

**Required changes:**

1. **Replace `PreviewCard` with `PurchasePreviewTable` widget:**
```
┌─────────────────────────────────────────────────┐
│ 📦 Purchase Preview                              │
│ Supplier: GOPI & CO        Broker: Ravi          │
│ Date: 11 May 2026          Payment: 30 days      │
├──────────────────┬──────┬────────┬──────┬────────┤
│ Item             │ Qty  │ Unit   │ Rate │ Amount │
├──────────────────┼──────┼────────┼──────┼────────┤
│ THUVARA JP       │  67  │ bag    │3,510 │2,35,170│
│ THUVARA GOLD 30K │   5  │ bag    │3,150 │ 15,750 │
├──────────────────┴──────┴────────┴──────┴────────┤
│ Total: ₹2,50,920    Discount: —    Freight: —    │
└─────────────────────────────────────────────────┘
[✏️ Edit]  [❌ Cancel]  [✅ Save Purchase]
```

2. Tap [Edit] → opens `PurchaseEntryWizardV2` pre-filled with the draft (existing `initialDraft` flow)

3. **System prompt for purchase AI** (backend `ai_chat` router):
```python
PURCHASE_ASSISTANT_SYSTEM_PROMPT = """
You are a purchase entry assistant for a Kerala wholesale grocery trading company.

ROLE: Extract purchase data from user's natural language / WhatsApp-style message and return structured JSON.

STRICT RULES:
1. Return ONLY valid JSON when creating a purchase preview. No markdown.
2. Ask for clarification if supplier OR item list is missing — do NOT guess.
3. Units: "bag" for 50kg bags, "kg" for loose, "tin" for tins/cans, "box" for boxed goods.
4. Always ask: "How many days credit?" if not mentioned.
5. NEVER create duplicate purchases — if invoice number already exists, warn user.
6. After collecting all info: return intent="add_purchase_preview" with full entry_draft.
7. Show ALL items in the preview, not just the first.

REQUIRED PURCHASE FIELDS:
- supplier_name (required)
- broker_name (optional)
- lines: [{item_name, qty, unit, purchase_rate, selling_rate}] (at least 1 item required)
- payment_days (optional, ask if not given)

RESPONSE JSON FORMAT:
{
  "intent": "add_purchase_preview",
  "reply": "Here's the purchase preview. Please check and confirm.",
  "preview_token": "...",
  "entry_draft": {
    "supplier_name": "...",
    "broker_name": "...",
    "purchase_date": "YYYY-MM-DD",
    "payment_days": 30,
    "lines": [
      {"item_name": "...", "qty": 67, "unit": "bag", "purchase_rate": 3510, "selling_rate": 3840}
    ]
  }
}
"""
```

4. **WhatsApp integration:** The existing `whatsapp_reports` router supports outbound WhatsApp. Extend it with an inbound webhook listener (`POST /v1/webhook/whatsapp`) that:
   - Receives WhatsApp message from Meta Business API
   - Routes to `ai_chat` with `channel: "whatsapp"`
   - Sends formatted reply back via WhatsApp API

---

### FEATURE-F · Data Backup (Manual — ZIP Download)
**Client need:** Monthly/weekly manual backup of all purchase PDFs + data. Save to WhatsApp or download.

**Implementation:**
1. **Flutter: Settings > Backup page:**
```
Backup & Export
┌─────────────────────────────────────────┐
│ 📦 Full Data Backup                     │
│ Exports all purchases as PDF + CSV      │
│                                         │
│ [This Month] [Last 3 Months] [All Time] │
│                                         │
│ [Generate Backup ZIP]                   │
└─────────────────────────────────────────┘
```
2. **Backend endpoint:** `POST /v1/businesses/{bid}/exports/backup` body: `{period: "month"|"3months"|"all", format: "zip"}`
   - Generates ZIP file containing: `purchases.csv`, individual PDF for each purchase, `summary.csv`
   - Returns signed URL for download (valid 1 hour)
3. **Flutter:** On URL received → `share_plus` share sheet → user can save to Files, WhatsApp, Google Drive, etc.
4. **Progress:** Show progress bar during generation (poll endpoint or SSE)

---

### FEATURE-G · Remove Unwanted Features/Icons
**Items to hide/remove (per client request):**
1. Voice page (`/voice`) — client doesn't use voice, remove tab icon from shell
2. Dashboard home page legacy `features/dashboard/presentation/home_page.dart` — this appears to be a duplicate of `features/home/presentation/home_page.dart`. Remove the shell tab pointing to the wrong one.
3. Settings: remove any "Cloud payment" / "maintenance fee" UI if not relevant for this client
4. Analytics page: if showing same data as Reports, consider merging or removing the redundant Analytics tab

---

### FEATURE-H · Supplier/Broker/Item View — Summary Header Enhancements
**Client request:** When viewing a supplier, broker, or item detail:
- Header must show: **Last purchase date**, **X days ago**, **Total bills (period)**, **Total bags/kg/box/tin**, **Total amount**
- Each bill row must show: delivery status badge (from FEATURE-A)

**Changes:**
1. `supplier_detail_page.dart`: Add to stats row: `Last buy: Apr 28 · 13 days ago`
2. `broker_detail_page.dart`: Same
3. `catalog_item_detail_page.dart`: Add header stats: `Last buy: 40,000 kg · ₹42/kg · Apr 27`
4. Each bill row in these pages: add `🚚 Pending` / `✅ Received` badge

---

## 📊 PRIORITY MATRIX

| # | Feature/Bug | Impact | Effort | Priority |
|---|-------------|--------|--------|----------|
| BUG-001 | Donut empty | 🔴 High | 2h | P0 |
| BUG-002 | Today infinite loading | 🔴 High | 1h | P0 |
| BUG-003 | Tabs slow | 🟠 Med | 3h | P1 |
| BUG-004 | Draft filter broken | 🟠 Med | 2h | P1 |
| BUG-005 | Search categories | 🔴 High | 3h | P1 |
| BUG-006 | Search date/days | 🟠 Med | 2h | P1 |
| BUG-008 | AI preview table | 🔴 High | 4h | P1 |
| FEATURE-A | Delivery tracking | 🔴 High | 6h | P1 |
| FEATURE-B | Search totals | 🟡 Med | 2h | P2 |
| FEATURE-C | Fast item create | 🟡 Med | 3h | P2 |
| FEATURE-D | Batch item create | 🟡 Med | 4h | P2 |
| FEATURE-E | AI WhatsApp | 🟠 Med | 6h | P2 |
| FEATURE-F | Backup ZIP | 🟡 Med | 4h | P3 |
| FEATURE-G | Remove unused | 🟡 Low | 1h | P3 |
| FEATURE-H | View summaries | 🟡 Med | 3h | P3 |
