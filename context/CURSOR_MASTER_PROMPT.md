# 🚨 HARISREE PURCHASE ASSISTANT — CURSOR MASTER FIX PROMPT
**App:** Flutter (Riverpod) + FastAPI + Supabase/Postgres + Vercel  
**Company:** New Harisree Agency, Thrissur 680619  
**Date:** 12 May 2026  
**Priority:** CRITICAL — Production UX blockers + Performance + Data integrity

> **Instructions for Cursor:** Read this entire file before touching any code. Work through each section in order. After each section, run `flutter analyze` and `pytest` (backend). Do not skip sections or combine fixes carelessly — each issue has specific root cause and targeted fix. Reference existing providers, widgets, and routes from the codebase. Do NOT break `purchaseDraftProvider`, `tradePurchasesListProvider`, or any backend route under `/v1/businesses/{id}/...`.

---

## 📋 TABLE OF CONTENTS

1. [CRITICAL: Item Entry — Add Item Button Auto-Scroll](#1-critical-item-entry--add-item-button-auto-scroll)
2. [CRITICAL: Suggestion Dropdown Closes on Touch](#2-critical-suggestion-dropdown-closes-on-touch)
3. [CRITICAL: Silent Save Failure — Missing Per-Bag KG](#3-critical-silent-save-failure--missing-per-bag-kg)
4. [HIGH: Home Dashboard Stuck on Loading Spinner](#4-high-home-dashboard-stuck-on-loading-spinner)
5. [HIGH: All Actions & UI Extremely Slow — Optimistic Updates](#5-high-all-actions--ui-extremely-slow--optimistic-updates)
6. [HIGH: Reports Page Tab/Filter Unresponsive](#6-high-reports-page-tabfilter-unresponsive)
7. [HIGH: Purchase History Full-Screen Missing Filter Icons](#7-high-purchase-history-full-screen-missing-filter-icons)
8. [HIGH: Item Search — View Page Breaks When Searching](#8-high-item-search--view-page-breaks-when-searching)
9. [MEDIUM: Keyboard Overlaps Edit Fields (Keyboard Safe-Area)](#9-medium-keyboard-overlaps-edit-fields-keyboard-safe-area)
10. [MEDIUM: Add Item Search Field — Accessibility & Bold Styling](#10-medium-add-item-search-field--accessibility--bold-styling)
11. [MEDIUM: Suggestion List UX — Remove Small Div Scroll Pattern](#11-medium-suggestion-list-ux--remove-small-div-scroll-pattern)
12. [INFRA: Backend Cold Start / Render Logs / Error Monitoring](#12-infra-backend-cold-start--render-logs--error-monitoring)
13. [INFRA: Supabase Free Tier + Vercel Performance Tuning](#13-infra-supabase-free-tier--vercel-performance-tuning)

---

## 1. CRITICAL: Item Entry — Add Item Button Auto-Scroll

### 📸 Screenshots Evidence
`Image 8` (`New purchase — Items` page): When items list is empty, "Add Item" button is visible. After user adds 1–2+ items, the button is pushed far below the list and user cannot see it without scrolling manually.

### 🔍 Root Cause
In `flutter_app/lib/features/purchase/widgets/purchase_item_entry_sheet.dart` (or the Items step of `purchase_entry_wizard_v2`), after saving an item (`Save & add more` button), the ListView of items grows but the viewport does not scroll to show the `+ Add Item` button at the bottom.

### ✅ Fix Required

**File:** `flutter_app/lib/features/purchase/screens/purchase_items_step.dart` (or equivalent Items-step widget)

```dart
// 1. Add a ScrollController to the items list widget
final ScrollController _itemsScrollController = ScrollController();

// 2. After any item is added (on Save & add more, or after Save), scroll to bottom:
void _scrollToAddButton() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_itemsScrollController.hasClients) {
      _itemsScrollController.animateTo(
        _itemsScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  });
}

// 3. Call _scrollToAddButton() immediately after:
//    - ref.read(purchaseDraftProvider.notifier).addLine(line)
//    - Any "Save & add more" callback

// 4. Ensure the "+ Add Item" button has a GlobalKey so it can also be used
//    with Scrollable.ensureVisible() as a fallback:
final GlobalKey _addItemKey = GlobalKey();

// In the button widget:
ElevatedButton(
  key: _addItemKey,
  onPressed: _openAddItemSheet,
  child: const Text('+ Add Item'),
)
```

**Also ensure:** The `ListView.builder` or `Column` wrapping items uses the `_itemsScrollController` and is inside a `SingleChildScrollView` with `physics: const AlwaysScrollableScrollPhysics()`.

---

## 2. CRITICAL: Suggestion Dropdown Closes on Touch

### 📸 Screenshots Evidence
`Image 11` / `Image 13` (`New purchase — Party`): Supplier search shows dropdown list. When user taps any suggestion, the dropdown closes **immediately** before registering the selection. Same issue in broker search and item search in Add Item step.

### 🔍 Root Cause
The search field uses a `Focus` node + `onTapOutside` or `onFocusChange` listener that dismisses the overlay/dropdown when any touch is detected outside the text field — including taps ON the suggestion list items. The suggestion list is likely rendered as an `OverlayEntry` or `Positioned` widget without proper gesture absorption, so the touch bubbles up and triggers focus loss → dropdown close.

### ✅ Fix Required

**Files to check:**
- `flutter_app/lib/shared/widgets/search_with_suggestions.dart` (or similar shared search widget)
- `flutter_app/lib/features/purchase/widgets/supplier_search_field.dart`
- `flutter_app/lib/features/purchase/widgets/broker_search_field.dart`
- `flutter_app/lib/features/purchase/widgets/item_search_field.dart`

```dart
// WRONG PATTERN — causes immediate close on suggestion tap:
Focus(
  onFocusChange: (hasFocus) {
    if (!hasFocus) setState(() => _showSuggestions = false); // ← THIS IS THE BUG
  },
  child: TextField(...)
)

// CORRECT PATTERN — use TapRegion to scope dismissal:
TapRegion(
  onTapOutside: (_) {
    setState(() => _showSuggestions = false);
    _focusNode.unfocus();
  },
  child: Column(
    children: [
      TextField(
        focusNode: _focusNode,
        onChanged: _onSearch,
      ),
      if (_showSuggestions) _buildSuggestionList(), // inside same TapRegion
    ],
  ),
)

// The suggestion list must be a sibling inside the TapRegion, NOT an OverlayEntry
// If using Overlay, wrap OverlayEntry child in TapRegion or GestureDetector with
// behavior: HitTestBehavior.opaque
```

**Additional requirements for suggestion list:**
- Minimum height: `min(suggestions.length * 56, 280)` px with internal scroll
- Add a visible **close/done button** (✕ icon) at the top-right of the suggestion panel
- Each suggestion item must have `onTap` wrapped in `GestureDetector` with `behavior: HitTestBehavior.opaque`
- Add `HapticFeedback.selectionClick()` on successful selection
- After selection, call `_focusNode.unfocus()` then `setState(() => _showSuggestions = false)`

**Apply this fix to ALL search fields:**
1. Supplier search (New purchase — Party step)
2. Broker search (New purchase — Party step)
3. Item search (New purchase — Add item step)
4. Global search

---

## 3. CRITICAL: Silent Save Failure — Missing Per-Bag KG

### 📸 Screenshots Evidence
`Image 3` (TRUSALT CRYSTAL 25KG item ledger), `Image 4` (Items contacts search). User selects item "TRUE SALT CRYSTAL", picks unit `bag`, fills all fields, taps Save — nothing happens, no error shown. Item has no `kg_per_unit` stored.

### 🔍 Root Cause
In `flutter_app/lib/features/purchase/widgets/purchase_item_entry_sheet.dart`, when unit type is `bag` and `catalog_item.kg_per_bag` (or `default_kg_per_unit`) is null/0, the line money calculation fails silently (`qty × null × rate = null`), and the save validation rejects the line without surfacing an error message to the user.

### ✅ Fix Required — Multi-Part

#### Part A: Detect Missing KG-per-Bag During Item Selection

```dart
// In purchase_item_entry_sheet.dart, after item is selected and unit is resolved to 'bag':
void _onItemSelectedOrUnitChanged() {
  final item = _selectedItem;
  final unit = _resolvedUnit; // 'bag', 'kg', 'piece', etc.

  if (unit == 'bag' && (item?.kgPerBag == null || item!.kgPerBag! <= 0)) {
    // Show the per-bag KG dialog BEFORE allowing save
    _showPerBagKgDialog(item);
  }
}
```

#### Part B: Per-Bag KG Dialog with Item Rename

```dart
Future<void> _showPerBagKgDialog(CatalogItem item) async {
  final TextEditingController kgController = TextEditingController();
  final result = await showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        left: 24, right: 24, top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚠️ Missing bag weight for\n"${item.name}"',
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'This item has no per-bag KG saved. Enter the weight per bag so the app can calculate correctly. This will be saved and you won\'t be asked again.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: kgController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'KG per bag (e.g. 25)',
              suffixText: 'kg/bag',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1A7A6A), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Show proposed new name
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: kgController,
            builder: (_, val, __) {
              final kg = double.tryParse(val.text);
              if (kg == null || kg <= 0) return const SizedBox.shrink();
              final baseName = _stripKgSuffix(item.name); // remove any existing KG suffix
              final newName = '$baseName ${kg.toInt()}KG';
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit, color: Color(0xFF1A7A6A), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Item will be renamed to:\n"$newName"',
                        style: const TextStyle(
                          color: Color(0xFF1A7A6A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A7A6A)),
                  onPressed: () {
                    final kg = double.tryParse(kgController.text);
                    if (kg != null && kg > 0) Navigator.pop(ctx, kg);
                  },
                  child: const Text('Save & Continue', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (result != null) {
    await _saveKgPerBagToItem(item, result);
  }
}

/// Remove existing KG suffix like "25KG", "30 KG", "50KG" from item name
String _stripKgSuffix(String name) {
  return name.replaceAll(RegExp(r'\s*\d+\s*KG\s*$', caseSensitive: false), '').trim();
}
```

#### Part C: Save KG-per-bag to Catalog Item (API Call + Rename)

```dart
Future<void> _saveKgPerBagToItem(CatalogItem item, double kgPerBag) async {
  final baseName = _stripKgSuffix(item.name);
  final newName = '$baseName ${kgPerBag.toInt()}KG';

  try {
    // PATCH /v1/businesses/{id}/catalog/items/{itemId}
    await ref.read(catalogApiProvider).updateItem(
      itemId: item.id,
      name: newName,
      kgPerBag: kgPerBag,
      defaultUnit: 'bag',
    );

    // Update local draft with resolved item
    ref.invalidate(catalogItemProvider(item.id));
    setState(() {
      _selectedItem = item.copyWith(name: newName, kgPerBag: kgPerBag);
      _kgPerUnit = kgPerBag;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item renamed to "$newName" and ${kgPerBag}kg/bag saved.'),
          backgroundColor: const Color(0xFF1A7A6A),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
```

#### Part D: Clear Error Message When Save Still Fails

```dart
// In the Save / Save & add more handler, BEFORE calling the API:
String? _validateLine() {
  if (_selectedItem == null) return 'Please select an item.';
  if (_qty == null || _qty! <= 0) return 'Quantity must be greater than 0.';
  if (_resolvedUnit == 'bag' && (_kgPerUnit == null || _kgPerUnit! <= 0)) {
    return 'Please enter KG per bag for this item first.';
  }
  if (_purchaseRate == null || _purchaseRate! <= 0) return 'Purchase rate is required.';
  return null;
}

// Show inline error (NOT a snackbar):
void _onSave() {
  final error = _validateLine();
  if (error != null) {
    setState(() => _inlineError = error); // show red text below form
    return;
  }
  // proceed with save...
}
```

#### Part E: Backend — Add `kg_per_bag` to Catalog Item Model & PATCH Endpoint

```python
# backend/app/models/catalog.py — add field if not present:
class CatalogItem(Base):
    # ... existing fields ...
    kg_per_bag: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 3), nullable=True)
    default_unit: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)

# backend/app/routers/catalog.py — PATCH endpoint:
@router.patch("/businesses/{business_id}/catalog/items/{item_id}")
async def update_catalog_item(
    business_id: UUID, item_id: UUID,
    payload: CatalogItemUpdate,
    session: AsyncSession = Depends(get_session),
):
    item = await session.get(CatalogItem, item_id)
    if not item or item.business_id != business_id:
        raise HTTPException(404)
    if payload.name is not None:
        item.name = payload.name
    if payload.kg_per_bag is not None:
        item.kg_per_bag = payload.kg_per_bag
    if payload.default_unit is not None:
        item.default_unit = payload.default_unit
    await session.commit()
    await session.refresh(item)
    return item
```

---

## 4. HIGH: Home Dashboard Stuck on Loading Spinner

### 📸 Screenshots Evidence
`Image 12` / `Image 14` (`Home` screen): Dashboard shows "Loading..." spinner indefinitely. After tab switch (Today → Week → Month → Year), it reloads from scratch each time. Shows ₹0 even when purchases exist.

### 🔍 Root Cause
1. `homeDashboardProvider` likely has no timeout guard — if Supabase/backend is slow (free-tier cold start), it stalls forever
2. Tab switching (Today/Week/Month/Year) invalidates the whole provider instead of just updating the date range parameter
3. No skeleton loading — the spinner blocks the entire screen instead of showing partial data

### ✅ Fix Required

**File:** `flutter_app/lib/features/home/providers/home_dashboard_provider.dart`

```dart
// Use keepAlive to prevent rebuild on tab switch:
@riverpod
class HomeDashboard extends _$HomeDashboard {
  @override
  Future<DashboardData> build(DateRange range) async {
    // Cache for 60 seconds — do NOT invalidate on every tiny interaction
    final link = ref.keepAlive();
    Timer(const Duration(seconds: 60), link.close);

    // Hard timeout — never stall forever
    return await ref
      .read(dashboardApiProvider)
      .fetchDashboard(range: range)
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Dashboard load timed out'),
      );
  }
}

// Separate provider for period — changing period does NOT rebuild the shell
@riverpod
class SelectedPeriod extends _$SelectedPeriod {
  @override
  DashboardPeriod build() => DashboardPeriod.today;

  void select(DashboardPeriod period) => state = period;
}
```

**File:** `flutter_app/lib/features/home/screens/home_screen.dart`

```dart
// Use AsyncValue properly — show skeleton, not full-screen spinner:
ref.watch(homeDashboardProvider(range)).when(
  loading: () => const HomeDashboardSkeleton(), // ← skeleton cards, NOT CircularProgressIndicator
  error: (e, _) => HomeErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(homeDashboardProvider)),
  data: (data) => HomeDashboardContent(data: data),
)

// Period chips use select() not invalidate():
PeriodChip(
  onTap: () => ref.read(selectedPeriodProvider.notifier).select(DashboardPeriod.week),
)
```

**HomeDashboardSkeleton widget (create new):**

```dart
class HomeDashboardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      // Shimmer card for total amount
      ShimmerBox(height: 80, borderRadius: 12),
      const SizedBox(height: 16),
      // Shimmer for chart area
      ShimmerBox(height: 200, borderRadius: 12),
      const SizedBox(height: 16),
      // Shimmer for list items
      for (int i = 0; i < 4; i++) ...[
        ShimmerBox(height: 56, borderRadius: 8),
        const SizedBox(height: 8),
      ],
    ],
  );
}
```

**Real-time updates:** After any purchase is saved or status updated, call:
```dart
ref.invalidate(homeDashboardProvider);
// This triggers a background refresh — UI keeps showing old data until new arrives
```

---

## 5. HIGH: All Actions & UI Extremely Slow — Optimistic Updates

### 📸 Screenshots Evidence
`Image 7` (Purchase History): Actions like "Mark Delivered" / "Mark Paid" take 3–4 seconds to show feedback.

### 🔍 Root Cause
The app waits for full round-trip API response before updating UI. On Supabase free tier, cold API responses can be 2–3 seconds. No optimistic state is applied.

### ✅ Fix Required

**File:** `flutter_app/lib/features/purchase/providers/trade_purchases_provider.dart`

```dart
// Pattern: Optimistic update → API call → rollback on error
Future<void> markDelivered(String purchaseId) async {
  // 1. IMMEDIATELY update local state (optimistic)
  state = AsyncData(state.value!.map((p) =>
    p.id == purchaseId ? p.copyWith(deliveryStatus: 'received') : p
  ).toList());

  HapticFeedback.mediumImpact(); // instant tactile feedback

  try {
    // 2. Fire API in background
    await ref.read(tradePurchasesApiProvider).markDelivered(purchaseId);
    // 3. Soft refresh (don't show loading)
    ref.invalidate(tradePurchasesListProvider);
  } catch (e) {
    // 4. Rollback on failure + show error
    ref.invalidate(tradePurchasesListProvider); // reload real state
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
```

**Apply the same optimistic pattern to:**
- `markPaid` 
- `markDelivered`
- `cancelPurchase`
- Adding/removing purchase lines
- Any status change button

---

## 6. HIGH: Reports Page Tab/Filter Unresponsive

### 📸 Screenshots Evidence
`Image 10` (Reports): Correct data showing but switching tabs (Overview/Items/Suppliers/Brokers) or applying filters (Bags/Box/Tin) takes too long and shows a full loading state.

### 🔍 Root Cause
Each tab switch invalidates and re-fetches the entire reports provider. The reports data should be fetched once per period and filtered client-side for tab/group changes.

### ✅ Fix Required

**File:** `flutter_app/lib/features/reports/providers/reports_provider.dart`

```dart
// 1. Fetch ALL report data once per period (not once per tab):
@riverpod
Future<TradeReportData> tradeReport(TradeReportRef ref, DateRange range) async {
  return ref.read(reportsApiProvider).fetchAll(range: range);
  // Returns: { items: [...], suppliers: [...], categories: [...], summary: {...} }
}

// 2. Client-side filtering — NO network call:
@riverpod
List<ReportItem> filteredReportItems(FilteredReportItemsRef ref, {
  required DateRange range,
  required String groupFilter, // 'all', 'bags', 'box', 'tin'
  required String sortBy, // 'largest', 'name', etc.
}) {
  final data = ref.watch(tradeReportProvider(range));
  return data.whenData((d) {
    var items = d.items;
    if (groupFilter != 'all') {
      items = items.where((i) => i.unitType == groupFilter).toList();
    }
    // sort...
    return items;
  }).valueOrNull ?? [];
}
```

**Tab switch:** Only calls `ref.read(selectedReportTabProvider.notifier).state = tab` — no network.  
**Group filter change:** Same — purely in-memory filter, instant response.

---

## 7. HIGH: Purchase History Full-Screen Missing Filter Icons

### 🔍 Issue
When viewing Purchase History in full screen, there is no visible filter icon (for time period) or status filter icon (pending/delivered/paid). User must exit full screen to filter, which is a terrible UX.

### ✅ Fix Required

**File:** `flutter_app/lib/features/purchase/screens/purchase_history_screen.dart`

```dart
// Add to AppBar actions:
AppBar(
  title: const Text('Purchase History'),
  actions: [
    // Time period filter
    IconButton(
      icon: const Icon(Icons.calendar_today_outlined),
      tooltip: 'Filter by period',
      onPressed: _showPeriodFilterSheet,
    ),
    // Status filter (pending / delivered / paid / overdue)
    IconButton(
      icon: Badge(
        isLabelVisible: _hasActiveFilter,
        child: const Icon(Icons.filter_list),
      ),
      tooltip: 'Filter by status',
      onPressed: _showStatusFilterSheet,
    ),
  ],
)

// Period filter bottom sheet:
void _showPeriodFilterSheet() {
  showModalBottomSheet(
    context: context,
    builder: (_) => PeriodFilterSheet(
      selected: ref.read(purchaseHistoryPeriodProvider),
      onSelect: (period) {
        ref.read(purchaseHistoryPeriodProvider.notifier).state = period;
        Navigator.pop(context);
      },
    ),
  );
}

// Status filter bottom sheet:
void _showStatusFilterSheet() {
  showModalBottomSheet(
    context: context,
    builder: (_) => StatusFilterSheet(
      selected: ref.read(purchaseHistoryStatusFilterProvider),
      onSelect: (statuses) {
        ref.read(purchaseHistoryStatusFilterProvider.notifier).state = statuses;
        Navigator.pop(context);
      },
      options: ['All', 'Pending', 'Received', 'Paid', 'Overdue'],
    ),
  );
}
```

---

## 8. HIGH: Item Search — View Page Breaks When Searching

### 🔍 Issue
In Contacts → Items tab:
- **Without search (scroll + tap):** Opens full item detail with ledger, edit, PDF, new purchase options ✅
- **With search → tap result:** Opens a broken/partial view without edit, ledger, PDF options ❌

### 🔍 Root Cause
The search result `onTap` likely navigates using item name only (string), not `itemId`. Without the ID, the detail route `/catalog/item/:itemId` cannot load the full item context.

### ✅ Fix Required

**File:** `flutter_app/lib/features/contacts/screens/contacts_items_screen.dart`

```dart
// WRONG — search result navigates by name:
onTap: () => context.push('/item-analytics/${item.name}')

// CORRECT — always navigate by ID:
onTap: () => context.push('/catalog/item/${item.id}')
```

Ensure the search results include the full `CatalogItem` object with `id`, not just `name`. If the search API returns minimal data, make a secondary lookup or ensure the search endpoint returns `id` field.

**File:** `flutter_app/lib/features/catalog/screens/item_detail_screen.dart`

Ensure the item detail screen always shows full options (Edit, Ledger, New Purchase, PDF) regardless of how navigation occurred:
```dart
// Always show these buttons if itemId is valid:
if (itemId != null && itemId.isNotEmpty) ...[
  NewPurchaseButton(itemId: itemId),
  LedgerButton(itemId: itemId),
  EditButton(itemId: itemId),
  PDFButton(itemId: itemId),
]
```

---

## 9. MEDIUM: Keyboard Overlaps Edit Fields (Keyboard Safe-Area)

### 📸 Screenshots Evidence
`Image 2` (Edit item modal): Keyboard appears and covers the `Default unit` field. User has no way to know they need to scroll to see hidden fields.

### 🔍 Issue
The edit modal (and other modals/sheets) don't use `MediaQuery.of(context).viewInsets.bottom` to pad content above the keyboard.

### ✅ Fix Required — Apply to ALL modals, bottom sheets, and full-screen forms

**Pattern to use everywhere:**
```dart
// In every modal/sheet build():
Padding(
  padding: EdgeInsets.only(
    bottom: MediaQuery.of(context).viewInsets.bottom + 16, // ← KEY LINE
    left: 16, right: 16, top: 16,
  ),
  child: SingleChildScrollView( // ← Always wrap form in scroll
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // all form fields...
      ],
    ),
  ),
)
```

**For `showModalBottomSheet` calls:**
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true, // ← REQUIRED to allow full height
  builder: (ctx) => ...
)
```

**Files to audit and fix (apply the above pattern to ALL):**
1. `purchase_item_entry_sheet.dart` — Add item form
2. Edit item modal (wherever item edit is shown)
3. Quick-create supplier/broker sheets
4. Any other `showModalBottomSheet` call in the app

**Run this audit command in Cursor:**
```bash
grep -r "showModalBottomSheet" flutter_app/lib/ --include="*.dart" -l
```
Then check each file for `isScrollControlled: true` and `viewInsets.bottom` padding.

---

## 10. MEDIUM: Add Item Search Field — Accessibility & Bold Styling

### 📸 Screenshot Evidence
`Image 9` (Add item form): The item search field `Search item (name, code, HSN)...` has faint placeholder text and light border — hard for older users / low vision to see.

### ✅ Fix Required

**File:** `flutter_app/lib/features/purchase/widgets/purchase_item_entry_sheet.dart` (item search field)

```dart
// Replace the existing item search field decoration with:
InputDecoration(
  hintText: 'Search item (name, code, HSN)...',
  hintStyle: const TextStyle(
    color: Color(0xFF666666),
    fontWeight: FontWeight.w500,
    fontSize: 15,
  ),
  prefixIcon: const Icon(Icons.search, color: Color(0xFF1A7A6A), size: 22),
  // Bold green border when focused:
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFF1A7A6A), width: 2.5),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFF9ECEC9), width: 1.5),
  ),
  filled: true,
  fillColor: const Color(0xFFF0FAF9),
  // Drop shadow to make field stand out:
  // (Wrap in DecoratedBox for shadow since InputDecoration doesn't support it directly)
),

// Wrap the TextField in a container with shadow:
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF1A7A6A).withOpacity(0.15),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ],
  ),
  child: TextField(
    style: const TextStyle(
      fontWeight: FontWeight.w600, // Bold text input
      fontSize: 15,
      color: Color(0xFF1A7A6A), // Green text when typing
    ),
    // ... rest of field config
  ),
)
```

---

## 11. MEDIUM: Suggestion List UX — Remove Small Div Scroll Pattern

### 🔍 Issue
Several pages have a small scrollable `div` (or Flutter `Container` with limited height) showing suggestion lists. When the user touches inside to scroll, the whole container closes or the touch is not registered. This is especially bad in:
- Supplier/Broker search (purchase wizard step 1)
- Item search (purchase wizard step 3)
- Contacts search

### ✅ Fix Required — Convert to Full Bottom Sheet

```dart
// Instead of inline dropdown suggestions, use a full bottom sheet for selecting:
void _openSupplierPicker() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          // Search field pinned at top
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              autofocus: true,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'Search supplier...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          // Scrollable results
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: _suggestions.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(_suggestions[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_suggestions[i].gst ?? _suggestions[i].phone ?? ''),
                onTap: () {
                  _selectSupplier(_suggestions[i]);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

**Apply this pattern to:** Supplier picker, Broker picker, Item picker in all search flows.

---

## 12. INFRA: Backend Cold Start / Render Logs / Error Monitoring

### 🔍 Issues Identified
- Vercel/Render cold starts causing 3–5 second delays on first API call
- Render logs not showing (user says "render logs not show full — why")
- No error monitoring — when backend crashes, user has no visibility
- No structured request logging

### ✅ Fix Required

#### A. FastAPI Request Logging Middleware

**File:** `backend/app/main.py`

```python
import time
import logging
from fastapi import Request

logger = logging.getLogger("purchase_api")

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration_ms = (time.time() - start) * 1000
    
    # Log slow requests prominently
    log_fn = logger.warning if duration_ms > 2000 else logger.info
    log_fn(
        f"{request.method} {request.url.path} → {response.status_code} "
        f"[{duration_ms:.0f}ms]"
    )
    
    # Add timing header for debugging
    response.headers["X-Response-Time"] = f"{duration_ms:.0f}ms"
    return response

@app.middleware("http")
async def handle_errors(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception as e:
        logger.exception(f"Unhandled error on {request.url.path}: {e}")
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})
```

#### B. Health Check Endpoint

```python
@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}

@app.get("/health/db")
async def health_db(session: AsyncSession = Depends(get_session)):
    try:
        await session.execute(text("SELECT 1"))
        return {"status": "ok", "db": "connected"}
    except Exception as e:
        return JSONResponse(status_code=503, content={"status": "error", "db": str(e)})
```

#### C. Fix Render Logs Not Showing

In `render.yaml` or Render dashboard:
```yaml
services:
  - type: web
    name: purchase-api
    env: python
    startCommand: uvicorn app.main:app --host 0.0.0.0 --port $PORT --log-level info
    # NOT --log-level warning — this hides most logs!
```

Add to `backend/app/main.py`:
```python
import logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    force=True,  # Override any other config
)
```

#### D. Free-Tier Cold Start Fix — Keep-Alive Ping

On Render free tier, the service sleeps after 15 minutes. Add a cron job or use UptimeRobot (free) to ping `/health` every 10 minutes.

In Flutter app, also add a pre-warm call:
```dart
// In app startup (before user tries any action):
Future<void> _prewarmBackend() async {
  try {
    await Dio().get('${AppConfig.apiBaseUrl}/health').timeout(
      const Duration(seconds: 5),
    );
  } catch (_) {} // Silent — just warming up
}
```

---

## 13. INFRA: Supabase Free Tier + Vercel Performance Tuning

### 🔍 Issues
- Supabase free tier pauses DB after 7 days of inactivity → cold start queries
- Large queries (reports, item history) slow on free-tier DB (shared resources)
- No caching layer

### ✅ Fix Required

#### A. Supabase — Prevent DB Pause

Add a lightweight cron job (GitHub Actions or Render cron) to query Supabase every 5 days:
```yaml
# .github/workflows/keepalive.yml
name: Supabase Keep-Alive
on:
  schedule:
    - cron: '0 0 */5 * *' # Every 5 days
jobs:
  ping:
    runs-on: ubuntu-latest
    steps:
      - run: curl -s "${{ secrets.SUPABASE_URL }}/rest/v1/" -H "apikey: ${{ secrets.SUPABASE_ANON_KEY }}" > /dev/null
```

#### B. Add Database Indexes for Slow Queries

```sql
-- Run in Supabase SQL editor:

-- Purchase history by business + date (most used filter):
CREATE INDEX IF NOT EXISTS idx_trade_purchases_business_date 
  ON trade_purchases(business_id, date DESC) 
  WHERE status != 'cancelled';

-- Item lookup by catalog_item_id:
CREATE INDEX IF NOT EXISTS idx_trade_purchase_lines_item 
  ON trade_purchase_lines(catalog_item_id);

-- Supplier filter:
CREATE INDEX IF NOT EXISTS idx_trade_purchases_supplier 
  ON trade_purchases(supplier_id, business_id);

-- Status filter:
CREATE INDEX IF NOT EXISTS idx_trade_purchases_status 
  ON trade_purchases(business_id, status);
```

#### C. Flutter API Caching (SWR Pattern)

```dart
// In providers, use staleTime + background refresh:
@riverpod
Future<List<TradePurchase>> tradePurchasesList(
  TradePurchasesListRef ref, {
  required String businessId,
  required DateRange range,
}) async {
  // Keep cached data for 30 seconds before considering stale
  ref.keepAlive();
  
  final result = await ref.read(tradePurchasesApiProvider)
    .list(businessId: businessId, range: range)
    .timeout(const Duration(seconds: 8));
  
  return result;
}
```

---

## ✅ POST-IMPLEMENTATION CHECKLIST

After all fixes are applied, verify each item:

### UX Tests (Manual — use physical device)
- [ ] Add 5 items to a purchase — "Add Item" button is always visible after each save
- [ ] Search "su" in supplier field — tap "SUMATHI SPICES" — it gets selected, dropdown closes, field shows name
- [ ] Create purchase with "TRUE SALT CRYSTAL", select "bag" unit — per-bag dialog appears
- [ ] Enter 25 in per-bag dialog — item renamed to "TRUE SALT CRYSTAL 25KG", saved, purchase continues
- [ ] Next time same item is used — no per-bag dialog shown (saved value used automatically)
- [ ] Home → switch Today/Week/Month/Year — no full-screen spinner, skeleton shown at most once
- [ ] Mark purchase as Delivered — button shows feedback within 500ms (not 3-4 seconds)
- [ ] Reports → switch Items/Suppliers tabs — instant switch, no loading
- [ ] Purchase History full screen — filter icon and period icon visible in header
- [ ] Contacts → Items → search "salt" → tap TRUSALT CRYSTAL 25KG → full detail page with Edit, Ledger, PDF, New Purchase buttons shown
- [ ] Edit any item → keyboard appears → all fields visible above keyboard (no overlap)
- [ ] Item search field in Add Item step → active state shows bold green text + strong border + shadow

### Performance Tests
- [ ] Cold open → Home loads within 3 seconds (on 4G)
- [ ] Any action (Mark Delivered, Mark Paid) → UI responds within 500ms
- [ ] Tab switch (reports, home period) → under 150ms visual update

### Backend Tests
- [ ] `curl https://your-api.onrender.com/health` → `{"status":"ok"}`
- [ ] `curl https://your-api.onrender.com/health/db` → `{"status":"ok","db":"connected"}`
- [ ] Render dashboard → Logs show all INFO-level request logs
- [ ] `pytest backend/` → all tests pass

### Flutter Analysis
```bash
cd flutter_app
flutter analyze
flutter test
```

---

## 📁 KEY FILES REFERENCE

| Area | File |
|------|------|
| Purchase wizard | `flutter_app/lib/features/purchase/screens/purchase_entry_wizard_v2.dart` |
| Item entry sheet | `flutter_app/lib/features/purchase/widgets/purchase_item_entry_sheet.dart` |
| Home dashboard | `flutter_app/lib/features/home/screens/home_screen.dart` |
| Home provider | `flutter_app/lib/features/home/providers/home_dashboard_provider.dart` |
| Trade purchases provider | `flutter_app/lib/features/purchase/providers/trade_purchases_provider.dart` |
| Reports screen | `flutter_app/lib/features/reports/screens/reports_screen.dart` |
| Contacts/Items | `flutter_app/lib/features/contacts/screens/contacts_items_screen.dart` |
| Item detail | `flutter_app/lib/features/catalog/screens/item_detail_screen.dart` |
| Router | `flutter_app/lib/core/router/app_router.dart` |
| Calc engine | `flutter_app/lib/core/calc_engine.dart` |
| API main | `backend/app/main.py` |
| Catalog router | `backend/app/routers/catalog.py` |
| Trade purchases router | `backend/app/routers/trade_purchases.py` |

---

## 🚫 DO NOT BREAK

These are protected — do NOT modify their API or behaviour without explicit instruction:

- `purchaseDraftProvider` — core purchase state
- `purchaseTotalsProvider` — financial calculations
- `tradePurchasesListProvider` — purchase list data
- Backend route prefix `/v1/businesses/{business_id}/...`
- `computeTradeTotals` in `calc_engine.dart`
- Any existing Alembic migration files

---

## 📝 IMPLEMENTATION ORDER

Work in this exact priority order:

1. **Issue #2** (Dropdown close bug) — fixes the #1 user frustration immediately
2. **Issue #3** (Silent save failure + per-bag KG dialog) — enables currently-broken purchases
3. **Issue #1** (Auto-scroll Add Item button) — completes the purchase flow UX
4. **Issue #4** (Home dashboard loading) — fixes the "app is broken" first impression
5. **Issue #5** (Optimistic updates) — makes all actions feel instant
6. **Issues #6–#11** — in order as listed
7. **Issues #12–#13** (Infrastructure) — last, after all UI fixes

---

*Generated: 12 May 2026 | For: Harisree Purchase Assistant | Stack: Flutter + FastAPI + Supabase + Vercel/Render*
