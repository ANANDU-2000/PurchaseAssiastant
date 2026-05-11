# PURCHASE ASSISTANT v14 — SOLUTION TASK LIST
> Ordered by priority. Cursor agent works top-to-bottom.
> Check each box when done. Run `flutter analyze` after every task group.
> Last updated: 2026-05-11

---

## PROGRESS SUMMARY

| Phase | Tasks | Done | Remaining |
|-------|-------|------|-----------|
| P0 Critical Bugs | 3 | 3 | 0 |
| P1 High Bugs | 5 | 4 | 1 (T-005) |
| P1 Delivery Feature | 7 | 6 | 1 (T-015) |
| P2 Search Enhancements | 4 | 2 | 2 (backend totals T-007; T-005) |
| P2 Item Create Fast | 3 | 1 | 2 (T-017, T-018) |
| P2 AI Chatbot Upgrade | 4 | 1 | 3 (T-020–T-022) |
| P3 Backup + Others | 3 | 1 | 2 (T-023, T-025) |

**v14 agent batch (2026-05-11):** T-001 ✅ · T-002 ✅ · T-003 ✅ · T-004 ✅ · T-006 ✅ · T-007 ✅ (client-side) · T-008 ✅ · T-009 ✅ · T-010 ✅ · T-011 ✅ · T-012 ✅ · T-013 ✅ · T-014 ✅ · T-016 ✅ · T-019 ✅ · T-024 ✅

**v14 one-shot spec alignment (2026-05-11):** T-007 type rows use `matchingItemIds` + `(category_name ?? type_name)` vs type name per master prompt; T-012 delivery prompt runs via `_scheduleDeliveryPrompt` (post-frame callback, then await). `flutter analyze` + `flutter test` clean; no `print(` in `lib/`.

---

## PHASE 0 — CRITICAL BUGS (Fix First)

---

### T-001 · Fix Dashboard "Today" Infinite Loading

**✅ Done 2026-05-11** — 4s cap on `refreshing` when no hydrated cache (`home_dashboard_provider.dart`).

**File:** `flutter_app/lib/core/providers/home_dashboard_provider.dart`

Root cause: When `HomePeriod.today` has no cache and `reportsHomeOverview` returns 0 purchases, the provider falls through the full 2-phase fetch. On completion the result is empty but the shell still shows skeleton because the state assignment races.

- [ ] Find `HomeDashboardDataNotifier.build()` — the `Future.microtask` block
- [ ] After `if (_dead) return;` + `state = HomeDashboardDashState(snapshot: payload, refreshing: false)`: confirm this runs even when payload is empty
- [ ] Add explicit check: after phase 1 snapshot has `purchaseCount == 0 && totalPurchase == 0`, skip phase 2 entirely and return immediately:
```dart
final fromSnapshot = homeDashboardDataFromApiSnapshot(period, snap);
// SHORT-CIRCUIT: if server confirms nothing for this range, skip the
// expensive local purchase-list+catalog phase.
if (!_snapshotHasTradeActivity(fromSnapshot)) {
  return ok(fromSnapshot, readDegradedBanner: readDegradedBanner, readDegraded: readDegraded);
}
```
Wait — this already exists at line ~651. The issue is the `homeDashboardSyncCacheProvider` returns `null` for today (no cache), so `refreshing = true` until microtask resolves. The fix: set initial `refreshing: false` when cache is null for a period that hasn't been fetched before:
- [ ] Change: `final hasRenderableCache = hydrated != null;` 
- [ ] Add: check if we have RECENTLY completed a fetch for this exact key: add `_completedFetchKeys = <String>{}` set; add key to set after `state = ...` resolves; seed `hasRenderableCache = _completedFetchKeys.contains(dedupeKey)` fallback
- [ ] Alternative simpler fix: add a 3-second timeout: if after 3s `refreshing` is still true AND `state.snapshot.data == HomeDashboardData.empty`, force `refreshing = false`
- [ ] Test: tap "Today" chip → data shows within 3 seconds (or empty state message, not spinner)

---

### T-002 · Fix Dashboard Donut Empty / "Loading Items breakdown..."

**✅ Done 2026-05-11** — skeleton ring + `ListSkeleton` in `home_page.dart` when breakdown loading / empty slices.

**File:** `flutter_app/lib/core/providers/home_dashboard_provider.dart` + `lib/features/home/presentation/home_page.dart`

Root cause: Phase 1 snapshot returns correct totals but `itemSlices: []`. Phase 2 aggregation fills `itemSlices` but there's no intermediate loading state — donut just shows gray ring.

- [ ] Add `breakdownLoading` field to `HomeDashboardDashState`:
```dart
class HomeDashboardDashState {
  const HomeDashboardDashState({
    required this.snapshot,
    required this.refreshing,
    this.breakdownLoading = false,  // NEW
  });
  final bool breakdownLoading;
  // ...
}
```
- [ ] In `_homeDashboardPullFresh`, after getting `fromSnapshot` with `_snapshotHasTradeActivity == true` but `fromSnapshot.itemSlices.isEmpty`:
  - Emit intermediate state with `breakdownLoading: true` via a callback/ref.read
  - OR: split the provider into two: `homeDashboardHeaderProvider` (fast, Phase 1) and `homeDashboardBreakdownProvider` (slow, Phase 2)
- [ ] **Recommended simpler approach:** In `home_page.dart`, where breakdown tabs are built:
  - Check: `if (data.itemSlices.isEmpty && state.refreshing == false)`: show shimmer placeholder for donut + breakdown
  - Show: 3 skeleton rows per breakdown tab instead of "Loading Items breakdown…" text
- [ ] For "Loading Items breakdown…" text: replace with `ListSkeleton(count: 5)` from existing widget
- [ ] Test: on Month view → donut shows skeleton immediately → fills with real data within 5s

---

### T-003 · Fix Dashboard Breakdown Tabs Performance

**✅ Done 2026-05-11** — keep-alive tab bodies + `ListView.builder` in `home_page.dart`.

**Files:** `flutter_app/lib/features/home/presentation/home_page.dart` + `lib/core/providers/home_breakdown_tab_providers.dart`

- [ ] Audit `home_breakdown_tab_providers.dart`: check if tab providers are scoped to rebuild only when their specific data changes (use `select`)
- [ ] In `home_page.dart`: find the `TabBarView` for Category/Subcategory/Supplier/Items
- [ ] Add `AutomaticKeepAliveClientMixin` to each tab page widget so switching tabs doesn't re-render from scratch
- [ ] Add `const` constructors to all list-item widgets in breakdown lists
- [ ] Add `ListView.builder` instead of `Column` + `List.map` for breakdown lists > 5 items
- [ ] Test: switch tabs rapidly → no jank (use Flutter DevTools performance overlay)

---

## PHASE 1 — HIGH PRIORITY BUGS

---

### T-004 · Fix Draft Filter in Purchase History

**✅ Done 2026-05-11** — `draft` + `pending_delivery` filters, WIP banner guard, list badges.

**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

- [ ] In `purchaseHistoryVisibleSortedForRef`: add `primary == 'draft'` handling:
```dart
if (primary == 'draft') {
  // Show only local WIP + server-side draft-status purchases
  v = v.where((p) => p.statusEnum == PurchaseStatus.draft).toList();
}
```
- [ ] The local WIP draft already shows as a banner row — this is correct. When `primary == 'draft'`, also ensure the banner row is visible even if `_selectMode` is active
- [ ] When API fetch returns `status: 'all'` purchases, server-side drafts (if any) will be included — verify API actually returns `status = 'draft'` entries with `status: 'all'`
- [ ] Test: tap "Draft" chip → only WIP banner + any server drafts shown; tap "All" → full list returns

---

### T-005 · Fix Global Search — User-Created Categories/Subcategories

**File:** Backend `backend/app/routers/search.py`

- [ ] In the search router's `unified_search` endpoint: check the SQL query for `catalog_subcategories` / `catalog_types`
- [ ] Verify the query does NOT filter by `is_seeded = true` or similar — user-created types must be included
- [ ] Check: `SELECT id, name, parent_name FROM catalog_types WHERE business_id = $1 AND name ILIKE $2` — ensure `business_id` filter correctly includes user-created records
- [ ] Check Flutter side: `_asMapListSkipBad('catalog_subcategories', data)` — no additional client-side filtering that would drop user-created rows
- [ ] Test: create a custom subcategory "SPECIAL RICE" → search "special" → it appears in results

---

### T-006 · Add Last Purchase Date + Days Ago in Search Rows

**✅ Done 2026-05-11** — enrichment + `TradeIntelCatalogSearchTile` date line (`trade_intel_cards.dart`).

**File:** `flutter_app/lib/features/search/presentation/search_page.dart`

- [ ] In the `items` enrichment block (lines 265–310): `lastLineByItemId` already captures date key. Extract actual `purchase_date` string too:
```dart
final lastDateStringByItemId = <String, String>{};
// In the loop:
final dtStr = p['purchase_date']?.toString() ?? '';
if (dtStr.isNotEmpty && dtK >= prevK) {
  lastDateStringByItemId[cid] = dtStr.substring(0, 10);
}
// In the map:
next['last_purchase_date'] = lastDateStringByItemId[id];
```
- [ ] In the catalog item row UI widget (find where `last buy ₹xx` is built): add below the rate line:
```dart
if (m['last_purchase_date'] != null) {
  final date = DateTime.tryParse(m['last_purchase_date']);
  if (date != null) {
    final daysAgo = DateTime.now().difference(date).inDays;
    final dateStr = DateFormat('MMM d').format(date);
    Text('$dateStr · ${daysAgo == 0 ? "today" : "$daysAgo days ago"}',
      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant));
  }
}
```
- [ ] Test: search "sugar" → "SUGAR 50 KG" row shows `"Apr 27 · 14 days ago"` below rate

---

### T-007 · Add Unit Totals to Search Category/Type Rows

**✅ Done 2026-05-11 (Flutter client-side)** — type rows: `matchingItemIds` from items where `(category_name ?? type_name)` lowercases to catalog type name; sum bags/kg from `lastLineByItemId`. Backend aggregation in doc still optional.

**Files:** Backend `search.py` + Flutter `search_page.dart`

- [ ] Backend: in `catalog_subcategories` search result, add fields: `total_bags`, `total_kg`, `total_boxes`, `total_tins`, `total_amount` from last 30 days aggregation
```sql
SELECT 
  ct.id, ct.name, c.name as parent_name,
  COALESCE(SUM(CASE WHEN pl.unit IN ('bag','sack') THEN pl.qty END), 0) as total_bags,
  COALESCE(SUM(CASE WHEN pl.unit = 'kg' THEN pl.qty END), 0) as total_kg,
  COALESCE(SUM(pl.line_total), 0) as total_amount
FROM catalog_types ct
JOIN catalog_items ci ON ci.type_id = ct.id
LEFT JOIN purchase_lines pl ON pl.catalog_item_id = ci.id
  AND pl.created_at > NOW() - INTERVAL '30 days'
WHERE ct.business_id = $1 AND ct.name ILIKE $2
GROUP BY ct.id, ct.name, c.name
```
- [ ] Flutter: in category/type row builder, add summary chips below name:
```dart
if (totalBags > 0) Chip(label: Text('${fmtQty(totalBags)} bags'))
if (totalKg > 0) Chip(label: Text('${fmtQty(totalKg)} kg'))
if (totalAmount > 0) Text(fmtInr(totalAmount))
```
- [ ] Test: search "pulses" → category row shows `"2,300 bags · ₹12,50,000"`

---

### T-008 · Fix AI Chatbot Preview — Full Table + Editable

**✅ Done 2026-05-11** — `purchase_preview_table.dart` + `assistant_chat_page.dart` (`PurchasePreviewTable`).

**Files:** `lib/features/assistant/presentation/widgets/preview_card.dart` + `assistant_chat_page.dart`

- [ ] Create new widget: `lib/features/assistant/presentation/widgets/purchase_preview_table.dart`
- [ ] Table widget shows ALL lines from `entry_draft.lines`, not just `lines.first`
- [ ] Table columns: Item Name | Qty | Unit | Rate | Amount
- [ ] Header row: Supplier | Broker | Date | Payment Days
- [ ] Footer row: Total amount
- [ ] Add [✏️ Edit in Wizard] button → opens `PurchaseEntryWizardV2` with `initialDraft` from `entry_draft`
- [ ] In `assistant_chat_page.dart`: replace `PreviewCard` → `PurchasePreviewTable` when `intent == 'add_purchase_preview'`
- [ ] In `ChatMessage` model: add `draftSnapshot` field (already exists, verify it carries all lines)
- [ ] Test: tell chatbot "Surag 50 bags THUVARA JP 3510 rate, 5 bags THUVARA GOLD 3150 rate" → preview table shows 2 rows

---

## PHASE 1 — DELIVERY TRACKING (NEW FEATURE)

---

### T-009 · DB Migration — Delivery Fields

**✅ Done 2026-05-11** — Alembic `021_trade_purchase_delivery.py` (+ sqlite bootstrap).

**File:** Backend — create migration `backend/sql/supabase_025_delivery_tracking.sql`

```sql
ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS is_delivered BOOLEAN DEFAULT FALSE;
ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS delivery_notes TEXT;

-- Index for "pending deliveries" dashboard query
CREATE INDEX IF NOT EXISTS idx_tp_delivery 
  ON trade_purchases(business_id, is_delivered, status)
  WHERE status NOT IN ('deleted', 'cancelled');
```

Apply migration. Update RLS if applicable.

- [ ] Run migration on dev/staging DB
- [ ] Verify: `SELECT is_delivered, delivered_at FROM trade_purchases LIMIT 1` returns columns

---

### T-010 · Backend — Delivery Endpoints

**✅ Done 2026-05-11** — `PATCH .../delivery`, schemas + service (`pending_delivery_count` in home overview still T-015).

**File:** `backend/app/routers/trade_purchases.py` (or create `delivery.py`)

- [ ] Add endpoint: `PATCH /v1/businesses/{business_id}/trade-purchases/{purchase_id}/delivery`
  - Body: `{is_delivered: bool, delivered_at?: str, delivery_notes?: str}`
  - Auth: must own the business
  - Response: updated purchase object
- [ ] Add `is_delivered` + `delivered_at` + `delivery_notes` to all `listTradePurchases` and `getTradePurchase` response schemas
- [ ] Add `pending_delivery_count` to `reportsHomeOverview` response: `SELECT COUNT(*) FROM trade_purchases WHERE business_id = $1 AND is_delivered = false AND status NOT IN ('deleted','cancelled','draft')`

---

### T-011 · Flutter Model — Add Delivery Fields to TradePurchase

**✅ Done 2026-05-11**

**File:** `flutter_app/lib/core/models/trade_purchase_models.dart`

- [ ] Add to `TradePurchase` class:
```dart
final bool isDelivered;
final DateTime? deliveredAt;
final String? deliveryNotes;
```
- [ ] Add to `TradePurchase.fromJson`: 
```dart
isDelivered: (j['is_delivered'] as bool?) ?? false,
deliveredAt: j['delivered_at'] != null ? DateTime.tryParse(j['delivered_at'].toString()) : null,
deliveryNotes: j['delivery_notes']?.toString(),
```
- [ ] Run: `flutter analyze`

---

### T-012 · Flutter — Delivery Prompt After Purchase Save

**✅ Done 2026-05-11** — `_scheduleDeliveryPrompt` → post-frame + `_showDeliveryPrompt` after quick save / saved sheet (`purchase_entry_wizard_v2.dart`).

**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

- [ ] After `_doSave()` success — in the code where `PurchaseSavedSheet` is shown:
- [ ] Add logic: after the saved sheet dismisses (or alongside it), show delivery prompt:
```dart
Future<void> _showDeliveryPrompt(String purchaseId) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => _DeliveryPromptSheet(purchaseId: purchaseId),
  );
  if (result == true) {
    // PATCH delivery endpoint
    await ref.read(hexaApiProvider).markPurchaseDelivered(
      businessId: bid, purchaseId: purchaseId, isDelivered: true);
    invalidatePurchaseWorkspace(ref);
  }
}
```
- [ ] Create `_DeliveryPromptSheet` widget:
```
🚚 Has this shipment arrived at your warehouse?
[Not Yet — Remind Later]   [✅ Yes, Mark Received]
```
- [ ] Wire `markPurchaseDelivered` to `hexaApiProvider` → calls `PATCH .../delivery` endpoint
- [ ] The "Not Yet" button dismisses without marking — the purchase stays `is_delivered: false`

---

### T-013 · Flutter — Delivery Status in Purchase History Rows

**✅ Done 2026-05-11**

**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

- [ ] In each purchase list tile (find `_PurchaseTile` or equivalent):
- [ ] Add delivery badge:
```dart
if (!purchase.isDelivered)
  Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
    child: Text('🚚 Pending', style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
  )
else
  Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
    child: Text('✅ Received', style: TextStyle(fontSize: 10, color: Colors.green.shade800)),
  )
```
- [ ] Add "Pending Delivery" filter chip to the horizontal chip list (alongside All/Due/Paid/Draft)
- [ ] Wire filter: when selected → filter to `!purchase.isDelivered && purchase.statusEnum != PurchaseStatus.deleted`

---

### T-014 · Flutter — Delivery Toggle in Purchase Detail

**✅ Done 2026-05-11**

**File:** `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`

- [ ] Add delivery status section below the bill header:
```dart
ListTile(
  leading: Icon(purchase.isDelivered ? Icons.check_circle : Icons.local_shipping,
    color: purchase.isDelivered ? Colors.green : Colors.orange),
  title: Text(purchase.isDelivered ? 'Received at warehouse' : 'Pending delivery'),
  subtitle: purchase.deliveredAt != null 
    ? Text('Received on ${DateFormat('MMM d, y').format(purchase.deliveredAt!)}') 
    : null,
  trailing: TextButton(
    onPressed: _toggleDelivery,
    child: Text(purchase.isDelivered ? 'Mark Pending' : 'Mark Received'),
  ),
)
```
- [ ] `_toggleDelivery()` calls PATCH endpoint, invalidates provider

---

### T-015 · Flutter — Pending Deliveries Dashboard Alert

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

- [ ] Add to `reportsHomeOverview` data parse: extract `pending_delivery_count`
- [ ] Add a new `HomeDashboardData` field: `pendingDeliveryCount`
- [ ] In home page, after the unit summary row: add a warning card when count > 0:
```dart
if (data.pendingDeliveryCount > 0)
  InkWell(
    onTap: () => context.go('/purchase?filter=pending_delivery'),
    child: Card(
      color: Colors.orange.shade50,
      child: ListTile(
        leading: Icon(Icons.local_shipping, color: Colors.orange),
        title: Text('${data.pendingDeliveryCount} shipments pending arrival'),
        subtitle: Text('Tap to view and confirm delivery'),
        trailing: Icon(Icons.chevron_right),
      ),
    ),
  )
```

---

## PHASE 2 — FAST ITEM CREATION

---

### T-016 · Fast Item Create — Bottom Sheet from Home

**✅ Done 2026-05-11** — `quick_add_item_sheet.dart` (category + type + `createCatalogItem`); secondary FAB on home.

**File:** `flutter_app/lib/features/home/presentation/home_page.dart` + new `quick_add_item_sheet.dart`

- [ ] Add a "📦 Add Item" speed dial option to the home FAB (existing FAB is a `+` button)
- [ ] Convert the FAB to `SpeedDial` (add `flutter_speed_dial` or build custom 2-option FAB):
  - Option 1: 🧾 New Purchase (existing)
  - Option 2: 📦 Add Item (new)
  - Option 3: 📷 Scan Bill (existing)
- [ ] "Add Item" opens `QuickAddItemSheet` bottom sheet:
  ```
  Add New Item
  ┌──────────────────────────────────┐
  │ Search subcategory: [________]   │
  │ Item name:         [________]   │
  │ Default unit: [Bag▼] [Kg▼]      │
  │ Kg per bag (if bag): [____]      │
  └──────────────────────────────────┘
  [Cancel]              [Save & Add to Purchase]
  ```
- [ ] Subcategory search: `InlineSearchField` with all catalog types
- [ ] Duplicate check before save: show warning if item exists
- [ ] On save: call `POST /v1/businesses/{bid}/catalog-items`, invalidate catalog providers
- [ ] "Save & Add to Purchase" button: saves item then navigates to `PurchaseEntryWizardV2` with item pre-filled

---

### T-017 · Batch Item Creation from Supplier Detail

**File:** `flutter_app/lib/features/contacts/presentation/supplier_detail_page.dart` + new `batch_item_create_page.dart`

- [ ] Add menu option in supplier detail 3-dot menu: "Add Items for This Supplier"
- [ ] Navigates to `BatchItemCreatePage` with `supplierId` + `supplierName` pre-set
- [ ] Page has a dynamic list of item rows (start with 3, add more button):
  Each row: `[Item Name] [Subcategory] [Unit] [Kg/Bag if bag]`
- [ ] [Save All] button → batch create API call
- [ ] After save: shows count toast "5 items added for GOPI & CO"

---

### T-018 · Batch API Endpoint

**File:** `backend/app/routers/catalog.py`

- [ ] Add `POST /v1/businesses/{bid}/catalog-items/batch`
- [ ] Body: `{items: [{name, type_id, default_unit, default_kg_per_bag, default_supplier_ids}]}`
- [ ] Duplicate prevention: for each item, check `LOWER(name) = LOWER($name)` within business. Skip duplicates, report skipped count.
- [ ] Return: `{created: N, skipped: M, items: [...]}`

---

## PHASE 2 — AI CHATBOT UPGRADE

---

### T-019 · Replace PreviewCard with PurchasePreviewTable

**✅ Done 2026-05-11** (see T-008).

**Files:** `lib/features/assistant/presentation/widgets/purchase_preview_table.dart` (NEW) + `preview_card.dart`

- [ ] Create `PurchasePreviewTable` widget (see design in BUGS_AND_PLAN.md FEATURE-E)
- [ ] Show all lines from `entry_draft.lines`
- [ ] Make row amounts editable: `InlineEditableCell` — tap to edit, updates local state
- [ ] Edit button → opens wizard pre-filled
- [ ] In `assistant_chat_page.dart`: when `previewUi == true`, render `PurchasePreviewTable` instead of `PreviewCard`
- [ ] Keep `PreviewCard` for non-purchase entity previews (supplier create, etc.)
- [ ] Test: multi-item purchase in chat shows full table

---

### T-020 · Update AI System Prompt for Purchase Entry

**File:** `backend/app/routers/ai_chat.py` (or wherever system prompt is defined)

- [ ] Find the system prompt for purchase entry intent
- [ ] Replace with the full PURCHASE_ASSISTANT_SYSTEM_PROMPT from BUGS_AND_PLAN.md FEATURE-E
- [ ] Ensure `entry_draft.lines` always returns array of ALL items, not truncated
- [ ] Add `payment_days`, `broker_name`, `header_discount_percent` to `entry_draft` schema

---

### T-021 · AI Chat — Category/Subcategory Prompt

**File:** `backend/app/routers/ai_chat.py`

- [ ] When user types an item name not matched to catalog, AI must ask: "What subcategory does [item] belong to? Here are your categories: [list]"
- [ ] Backend: in purchase preview intent handler, if `catalog_item_id` is null for any line item, return `intent: "clarify_items"` with `missing_items` array
- [ ] Flutter: when `intent == "clarify_items"`, show subcategory picker chips for each unmatched item

---

### T-022 · Strict Duplication Prevention in AI Chat

**File:** `backend/app/routers/ai_chat.py`

- [ ] Before generating a `add_purchase_preview` response: check for recent duplicates:
  - Same supplier + same date → warn: "You already have a purchase from [Supplier] on [Date]. Is this a different bill?"
  - Same invoice number → block with error
- [ ] Add to `entry_draft`: `duplicate_risk: {level: "high|medium|none", reason: str}` flag
- [ ] Flutter: if `duplicate_risk.level == "high"`, show yellow warning banner above the preview table

---

## PHASE 3 — BACKUP + MISC

---

### T-023 · Data Backup Feature

**Files:** New `lib/features/settings/presentation/backup_page.dart` + backend

- [ ] Create `BackupPage` accessible from Settings
- [ ] Period selector: This Month / Last 3 Months / All Time
- [ ] [Generate Backup] button → calls `POST /v1/businesses/{bid}/exports/backup`
- [ ] Backend: generates ZIP (purchases.csv + PDFs for each purchase + summary)
- [ ] Returns download URL (presigned S3/Supabase storage URL)
- [ ] Flutter: opens `share_plus` share sheet with the ZIP URL
- [ ] Progress: `LinearProgressIndicator` while generating

---

### T-024 · Remove Unwanted Features

**✅ Done 2026-05-11** — `FeatureFlags` + maintenance card gate on home; shell references `FeatureFlags.showVoiceTab` (no voice tab in shell).

**Files:** `lib/features/shell/shell_screen.dart` + various

- [ ] In shell bottom nav: check if Voice tab (`/voice`) is shown — remove if client doesn't use it
- [ ] In Settings page: hide "Maintenance Fee" / cloud payment section if not needed by this client (wrap in `kDebugMode` flag or feature flag)
- [ ] In `feature_flags.dart` (already exists!): add `static const bool showVoiceTab = false;` and `static const bool showMaintenanceSection = false;`
- [ ] Check `lib/core/feature_flags.dart` — add flags there, use them to conditionally render UI

---

### T-025 · Enhance Supplier/Broker/Item View Headers

**Files:** `supplier_detail_page.dart`, `broker_detail_page.dart`, `catalog_item_detail_page.dart`

- [ ] Add `last_purchase_date` to supplier/broker/item API responses (backend)
- [ ] In each detail page header section: add `"Last buy: Apr 28 · 13 days ago"` stat chip
- [ ] In bill/purchase list rows: add delivery badge (from T-013 — reuse same widget)

---

## TESTING CHECKLIST

Run after all phases:

**Dashboard:**
- [ ] "Today" tap → shows data or empty state within 3 seconds (NOT infinite spinner)
- [ ] "Month" view → donut fills with category breakdown within 5 seconds
- [ ] Switching Category/Subcategory/Supplier/Items tabs is instant (no re-render)
- [ ] Pending deliveries card shows when there are undelivered purchases

**Delivery Tracking:**
- [ ] Save new purchase → delivery prompt appears
- [ ] Tap "Not Yet" → purchase shows 🚚 Pending badge
- [ ] Tap "Yes, Received" → purchase shows ✅ Received badge
- [ ] "Pending Delivery" filter shows only undelivered purchases

**Search:**
- [ ] User-created subcategory appears in search results
- [ ] Item row shows last purchase date + days ago
- [ ] Category row shows bags/kg totals

**AI Chatbot:**
- [ ] Tell chatbot "Gopi 67 bags thuvara jp 3510 rate, 5 bags thuvara gold 3150" → preview table shows 2 rows with correct amounts
- [ ] Tap Edit → opens wizard pre-filled

**Draft Filter:**
- [ ] Tap "Draft" chip → only WIP draft (if any) shown
- [ ] Tap "All" → full list returns
