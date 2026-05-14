# Purchase Assistant — Deep UX & Bug Fix Report
> **Status:** Production-blocking issues found across 7 areas  
> **Scope:** Flutter app (`flutter_app/lib/`) · Backend error handling · UI/UX  
> **Priority:** P0 = crash / data loss · P1 = broken flow · P2 = bad UX · P3 = polish

---

## QUICK REFERENCE — ORDERED TO-DO LIST

| # | Priority | Area | File(s) | Status |
|---|---|---|---|---|
| 1 | P0 | App error boundary swallowing all Flutter errors | `app.dart` | ❌ |
| 2 | P0 | PDF save → server error → full-screen crash state stuck on back | `app.dart`, `purchase_pdf.dart` | ❌ |
| 3 | P0 | Edit Item dialog: keyboard covers fields + Continue button overlap | `catalog_item_detail_page.dart` | ❌ |
| 4 | P1 | Supplier search: scroll kills field, suggestions close, letters lost | `party_inline_suggest_field.dart` | ❌ |
| 5 | P1 | Continue button overlapped by keyboard in purchase wizard | `purchase_entry_wizard_v2.dart` | ❌ |
| 6 | P1 | Purchase list shows stats but renders zero cards | `purchase_home_page.dart` | ❌ |
| 7 | P1 | Reports page: always loading, period filter errors, data sync | `reports_page.dart`, `reports_provider.dart` | ❌ |
| 8 | P1 | History page: cards missing real data | `item_history_page.dart` | ❌ |
| 9 | P2 | Home dashboard item-view tap jumps through category/types page | `home_page.dart`, `app_router.dart` | ❌ |
| 10 | P2 | Report page: remove avg weight / avg bags / avg rate metrics | `reports_page.dart` | ❌ |
| 11 | P2 | Purchase history: missing "late delivery" icon + high-to-low sort | `purchase_home_page.dart` | ❌ |
| 12 | P2 | PDF: supplier name / date / time missing in saved file | `purchase_pdf.dart` | ❌ |
| 13 | P2 | Report history list: bad UX — text too small, no color hierarchy | `reports_page.dart` | ❌ |
| 14 | P3 | Purchase list tab filter chips look broken on iPhone 16 Pro notch | `purchase_home_page.dart` | ❌ |
| 15 | P3 | Report page text colors — body too grey, values need teal accent | `reports_page.dart` | ❌ |

---

## ISSUE 1 — P0 · App Error Boundary Catches Everything
**File:** `flutter_app/lib/app.dart` — `_HexaErrorBoundaryState`

### What's happening
`_HexaErrorBoundary` replaces `FlutterError.onError` globally. Any widget build error — including transient layout overflows, provider loading glitches, even some package internals — sets `_error` and replaces the **entire app** with the orange-triangle "Something went wrong loading the app." screen. Clicking **back** doesn't clear `_error`, so users are trapped permanently until they force-quit.

### Root cause
```dart
// app.dart ~line 175
FlutterError.onError = (FlutterErrorDetails details) {
  _previousOnError?.call(details);
  if (mounted) {
    setState(() => _error = details.exception);  // ← any error kills entire app
  }
};
```
The error is never scoped — a RenderFlex overflow in a child widget causes the same full-screen crash as a fatal null dereference.

### Fix
```dart
// 1. Only catch truly fatal errors (not layout warnings)
FlutterError.onError = (FlutterErrorDetails details) {
  _previousOnError?.call(details);
  // Skip non-fatal layout / assertion errors in profile/release
  final msg = details.exception.toString();
  final isFatal = details.silent != true &&
      !msg.contains('RenderFlex') &&
      !msg.contains('overflowed') &&
      !msg.contains('BoxConstraints');
  if (mounted && isFatal) {
    setState(() => _error = details.exception);
  }
};

// 2. Add a "Go to home" button that resets state properly
TextButton(
  onPressed: () {
    setState(() => _error = null);
    // Force router to re-initialise to root
    ref.read(appRouterProvider).go('/');
  },
  child: const Text('Go to Home'),
),
```

### Additional fix — wrap PDF saves and server calls in their own try/catch
Never let a DioException or API 5xx propagate to `FlutterError.onError`. All async saves must catch and show inline snackbars, not crash the app boundary.

---

## ISSUE 2 — P0 · PDF Save Server Error = Permanent Crash Screen
**Files:** `flutter_app/lib/core/services/purchase_pdf.dart`, `purchase_home_page.dart`

### What's happening
When "Save PDF" is tapped and the backend returns a server error (500/503), the exception propagates to `_HexaErrorBoundary`. The user sees the orange triangle. Pressing back still shows it. The only escape is force-quitting.

### Fix pattern — wrap every PDF/save action
```dart
// purchase_home_page.dart — wherever PDF save is triggered
Future<void> _savePdf(TradePurchase purchase) async {
  try {
    setState(() => _isExportingPdf = true);
    final file = await generatePurchasePdf(purchase);
    await Share.shareXFiles([XFile(file.path)]);
  } on DioException catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('PDF export failed: ${e.message ?? 'Server error'}'),
        action: SnackBarAction(label: 'Retry', onPressed: () => _savePdf(purchase)),
        duration: const Duration(seconds: 6),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not export PDF. Please try again.')),
    );
  } finally {
    if (mounted) setState(() => _isExportingPdf = false);
  }
}
```

---

## ISSUE 3 — P0 · Edit Item Dialog: Keyboard Overlaps All Fields
**File:** `flutter_app/lib/features/catalog/presentation/catalog_item_detail_page.dart`

### What's happening (Image 4)
`_editItemDefaults()` uses `showDialog<bool>` with `AlertDialog`. On iPhone 16 Pro:
- When any field is tapped, the software keyboard rises and **covers** all inputs below it
- `AlertDialog` doesn't call `Scaffold.resizeToAvoidBottomInset` — it sits on a raw `Material`
- The "Save" button is unreachable without dismissing the keyboard
- There is NO `keyboardDismissBehavior` or `scrollPadding` — the `SingleChildScrollView` inside doesn't know about the keyboard inset

### Fix — Replace AlertDialog with a bottom sheet
```dart
Future<void> _editItemDefaults(Map<String, dynamic> item) async {
  // ... existing controller setup stays the same ...

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,          // ← KEY: allows full height
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        return Padding(
          // ← KEY: lifts content above keyboard
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('Edit item',
                        style: Theme.of(ctx).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: [
                      // ... all existing TextField widgets here ...
                      const SizedBox(height: 16),
                      // Save button INSIDE the scroll — always reachable
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: const Color(0xFF0D6B5E),
                        ),
                        child: const Text('Save',
                          style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  // ... rest of save logic unchanged ...
}
```

---

## ISSUE 4 — P1 · Supplier Search: Scroll Kills Field, Suggestions Dismiss
**File:** `flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart`

### What's happening (Image 7)
On iPhone 16 Pro when typing "sur" and trying to scroll the suggestion list:
1. The scroll gesture begins on the suggestion `ListView`
2. Flutter's gesture arena resolves the scroll vs. tap conflict in favor of the parent `Scrollable` (the wizard's page scroll)
3. The `focusNode` reports blur (finger briefly left the text area hit-test zone)
4. `_armSuggestPanelGraceIfNeeded()` fires with only a **420ms** grace window — not enough if the scroll is slow
5. `_tryBlurExactPick()` fires and may auto-select the wrong supplier
6. The browser native keyboard autocomplete overlay (iOS "QuickType" bar) intercepts touch events before Flutter sees them on certain iOS builds

### Fix A — Increase grace period + disable iOS autocorrect interference
```dart
// In _PartyInlineSuggestFieldState
static const _suggestGraceDuration = Duration(milliseconds: 800); // was 420ms

// In the TextField widget inside build():
TextField(
  controller: widget.controller,
  focusNode: widget.focusNode,
  textInputAction: widget.textInputAction,
  onSubmitted: _onFieldSubmitted,
  scrollPadding: _scrollPad(context),
  // ADD THESE — stops iOS QuickType bar from intercepting taps on suggestions:
  autocorrect: false,
  enableSuggestions: false,
  // ...
),
```

### Fix B — Use NeverScrollableScrollPhysics on the inner list, scroll via parent
The root cause of suggestions closing on scroll is gesture competition. The `ClampingScrollPhysics` in the inline suggestion `ListView` competes with the parent `SingleChildScrollView`. Replace it:

```dart
// In the inline panel ListView (build() method, ~line 640)
ListView(
  controller: _inlineSuggestScroll,
  shrinkWrap: true,
  primary: false,
  // ← Replace ClampingScrollPhysics with this:
  physics: const NeverScrollableScrollPhysics(),
  padding: EdgeInsets.zero,
  children: [ ... ],
),
```

This removes the competing gesture arena. The suggestion list will show all items without internal scrolling (already capped at `maxMatches: 6` visible rows). For "See more", keep the sheet.

### Fix C — Prevent premature auto-pick during scroll
```dart
void _tryBlurExactPick() {
  if (_pickInProgress) return;
  if (_suppressPanelAfterPick) return;
  // ADD: don't auto-pick if a scroll gesture may be in progress
  if (_suggestPanelGrace) return;   // ← grace active = user is scrolling
  // ... rest unchanged
}
```

### Fix D — Extend panel stay after IME dismiss on iOS
```dart
void _armSuggestPanelGraceIfNeeded() {
  // ... existing lock check ...
  _suggestPanelGrace = true;
  _suggestPanelGraceTimer = Timer(_suggestGraceDuration, () {  // uses new 800ms constant
    _suggestPanelGraceTimer = null;
    _suggestPanelGrace = false;
    if (!mounted) return;
    if (!widget.focusNode.hasFocus &&
        !_pickInProgress &&
        !_suppressPanelAfterPick) {
      // Don't auto-pick — let user re-tap. Avoids wrong-supplier selection.
      // _tryBlurExactPick();  ← REMOVE THIS CALL
    }
    setState(() {});
    _scheduleOverlaySync();
  });
}
```

---

## ISSUE 5 — P1 · Continue Button Overlapped by Keyboard
**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

### What's happening
In the purchase wizard, the "Continue →" bottom button is rendered in a fixed `SafeArea` bottom row. When the keyboard opens for supplier search, the button slides behind the keyboard because `Scaffold.resizeToAvoidBottomInset` is not set, or the `SafeArea` doesn't account for `viewInsets`.

### Fix
```dart
// In the Scaffold or the bottom action row builder:
bottomNavigationBar: AnimatedPadding(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  padding: EdgeInsets.only(
    bottom: MediaQuery.viewInsetsOf(context).bottom,
  ),
  child: SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: _buildContinueButton(),
    ),
  ),
),
```

Additionally, add `resizeToAvoidBottomInset: true` to the Scaffold if not already set.

---

## ISSUE 6 — P1 · Purchase List Shows Stats But Renders Zero Cards
**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

### What's happening (Images 1 & 2)
The stat chips (₹1.5Cr, 33 Purch, 5,419 bags) are displayed but the `ListView` of purchase cards below is completely blank. The filter tabs (All / Due / Paid / Draft / Awaiting) exist but the list body doesn't render.

### Likely causes
1. The provider `tradePurchasesProvider` has data but a downstream filter predicate is discarding all rows
2. The `_HistPeriodPreset` defaults to `month` but the list render depends on a date range that may be stale on first paint
3. The `ListView` uses `shrinkWrap` or a `Column` parent that gives it zero height

### Diagnostic steps
```dart
// Add temporarily to purchase_home_page.dart build:
final purchasesAsync = ref.watch(tradePurchasesProvider);
purchasesAsync.whenData((list) {
  debugPrint('[PurchaseHome] raw list count: ${list.length}');
  debugPrint('[PurchaseHome] after filter: ${_applyFilters(list).length}');
});
```

### Fix pattern
```dart
// Ensure the ListView always has a bounded height:
Expanded(   // ← wrap ListView in Expanded inside a Column, never inside SingleChildScrollView
  child: ListView.builder(
    itemCount: filteredPurchases.length,
    itemBuilder: (ctx, i) => _buildPurchaseCard(filteredPurchases[i]),
  ),
),

// Ensure the period filter initialises with a valid date range:
@override
void initState() {
  super.initState();
  // Force a reload on first frame to ensure date range is applied
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) ref.invalidate(tradePurchasesProvider);
  });
}
```

---

## ISSUE 7 — P1 · Reports Page Always Loading / Period Filter Errors
**File:** `flutter_app/lib/core/providers/reports_provider.dart`, `reports_page.dart`

### What's happening (Image 3)
- Reports page shows loading spinner indefinitely
- "No purchases in this period" shows simultaneously with spinner
- Switching period filters (Today → Week → Month) throws errors
- Data sync errors visible on slow connections

### Root causes
1. `reportsPurchasesPayloadProvider` has no retry logic — if the first fetch fails, the page stays in `loading` state forever
2. Period filter changes call `ref.invalidate()` immediately but the UI races between the old `AsyncValue.loading` state and the new fetch
3. The stall timer only shows a banner after 2 seconds but never offers a real retry

### Fix A — Add error recovery to reports provider
```dart
// reports_provider.dart — wrap the provider fetch:
final reportsPurchasesPayloadProvider = FutureProvider.autoDispose
    .family<List<TradePurchase>, ReportsDateRange>((ref, range) async {
  try {
    return await ref.read(hexaApiProvider).fetchPurchasesForRange(range);
  } catch (e) {
    // Throw a typed error so the UI can show a retry button
    throw ReportsLoadError(message: 'Failed to load report data', cause: e);
  }
});
```

### Fix B — Reports page error state with retry
```dart
// reports_page.dart — in the .when() handler:
error: (err, _) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
      const SizedBox(height: 12),
      Text('Could not load report data',
        style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _bumpInvalidate,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    ],
  ),
),
```

### Fix C — Debounce period filter changes properly
```dart
void _onPresetChanged(_DatePreset preset) {
  if (_preset == preset) return;
  setState(() => _preset = preset);
  // Debounce so rapid tab taps don't cause multiple inflight requests
  _scheduleReportsReloadForRange();  // already debounced at 400ms — keep
}
```

---

## ISSUE 8 — P1 · History Page: Missing Real Data / History Cards
**File:** `flutter_app/lib/features/item/presentation/item_history_page.dart`

### What's happening
History cards show placeholder/empty state even when real purchase data exists for the item.

### Fix
Ensure the history provider filters by the correct `catalogItemId` and does not rely on a stale cache:
```dart
// item_history_page.dart
@override
void initState() {
  super.initState();
  // Force fresh load every time the history page opens
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) ref.invalidate(itemTradeHistoryProvider(widget.itemId));
  });
}
```

Also verify `itemTradeHistoryProvider` is keyed on `itemId`, not on a global cache that might return an empty list from a previous unrelated item.

---

## ISSUE 9 — P2 · Home Dashboard Item Tap Navigates Through Intermediate Pages
**Files:** `home_page.dart`, `app_router.dart`

### What's happening
Tapping an item in the home breakdown list goes through the categories page → types page → item detail, instead of directly to item detail. This is jarring and slow.

### Fix — Use direct navigation in home item tap handler
```dart
// home_page.dart or home_breakdown_list_page.dart
// Instead of:
context.go('/catalog/${item.categoryId}/${item.subcategoryId}/${item.id}');

// Use:
context.push('/item/${item.id}');  // Direct route to item detail
// or if GoRouter nested:
openTradeItemFromReport(context, ref, catalogItemId: item.id);
```

Verify `open_trade_item_from_report.dart` pushes directly without intermediate route hops.

---

## ISSUE 10 — P2 · Remove Avg Weight / Avg Bags / Avg Rate from Reports
**File:** `flutter_app/lib/features/reports/presentation/reports_page.dart`

### What's happening
The `_MetricTile` widgets for `avg weight`, `avg bags`, and `avg rate` are shown in the report KPI row. The client confirmed these are not needed and confuse users.

### Fix — Remove from the metrics grid
```dart
// reports_page.dart — find the metrics row builder and remove:
// DELETE these tiles:
// _MetricTile(label: 'AVG WEIGHT', value: ...),
// _MetricTile(label: 'AVG BAGS', value: ...),
// _MetricTile(label: 'AVG RATE', value: ...),

// KEEP only:
_MetricTile(label: 'TOTAL', value: _inr0(agg.totalCost)),
_MetricTile(label: 'BAGS', value: '${agg.totalBags}'),
_MetricTile(label: 'KG', value: '${_kgReadable(agg.totalKg)} kg'),
```

---

## ISSUE 11 — P2 · Purchase History: Missing "Late Delivery" Icon + Sort
**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

### What's happening
- There is no visual indicator for purchases awaiting delivery that are **overdue** (older than expected delivery window)
- No way to sort purchase history **high-to-low by value**

### Fix A — Late delivery icon in history card
```dart
// purchase_home_page.dart — in the purchase card builder:
// The app already has delivery_aging.dart — use it:
final aging = DeliveryAging.of(purchase);
if (aging.isOverdue) {
  // Show a warning chip:
  _historyMetaChip(
    label: '${aging.daysSinceExpected}d late',
    bg: const Color(0xFFFFF3CD),
    border: const Color(0xFFFFCC02),
    fg: const Color(0xFF856404),
    icon: Icons.timer_off_rounded,
    fontSize: 9.5,
  );
}
```

The `delivery_aging.dart` file already exists at `core/purchase/delivery_aging.dart`. Wire it up to the card.

### Fix B — High-to-low sort option
```dart
// Add to the filter row enum:
enum _PurchaseSortOrder { newest, oldest, highValue, lowValue }

// In the sort chips row:
ChoiceChip(
  label: const Text('₹ High→Low'),
  selected: _sortOrder == _PurchaseSortOrder.highValue,
  onSelected: (_) => setState(() => _sortOrder = _PurchaseSortOrder.highValue),
),

// In the filter function:
List<TradePurchase> _sortedFiltered(List<TradePurchase> raw) {
  final filtered = _applyStatusFilter(raw);
  return switch (_sortOrder) {
    _PurchaseSortOrder.newest => filtered..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate)),
    _PurchaseSortOrder.highValue => filtered..sort((a, b) => b.totalCost.compareTo(a.totalCost)),
    _PurchaseSortOrder.lowValue => filtered..sort((a, b) => a.totalCost.compareTo(b.totalCost)),
    _PurchaseSortOrder.oldest => filtered..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate)),
  };
}
```

---

## ISSUE 12 — P2 · PDF Export: Supplier Name / Date / Time Missing
**File:** `flutter_app/lib/core/services/purchase_pdf.dart`

### What's happening
Generated PDFs don't include supplier name, purchase date, or time in the header / filename.

### Fix A — PDF header
```dart
// purchase_pdf.dart — in the PDF content builder:
pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text('PURCHASE RECEIPT',
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 4),
    pw.Text('Supplier: ${purchase.supplierName ?? '—'}',
      style: pw.TextStyle(fontSize: 12)),
    pw.Text('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(purchase.purchaseDate)}',
      style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
    pw.Text('PUR ID: ${purchase.humanId ?? '—'}',
      style: pw.TextStyle(fontSize: 11)),
  ],
),
```

### Fix B — PDF filename
```dart
// Instead of a generic name:
final filename = 'Purchase_${purchase.supplierName?.replaceAll(' ', '_') ?? 'Receipt'}'
    '_${DateFormat('ddMMMyyyy').format(purchase.purchaseDate)}.pdf';
```

---

## ISSUE 13 — P2 · Report History List: Poor Text Hierarchy & Readability
**File:** `flutter_app/lib/features/reports/presentation/reports_page.dart`, `reports_item_tile.dart`

### What's happening
The report item list has:
- All text the same grey — no visual hierarchy
- Bag/kg values are styled the same as labels (not bold/teal)
- Item names too small and low-contrast
- No "View purchase" call-to-action in the history drill-down

### Fix — Improve tile text hierarchy
```dart
// reports_item_tile.dart — replace text styles:

// Item name — primary, bold, dark
Text(item.name,
  style: const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Color(0xFF1A1A1A),  // dark, not grey
  ),
),

// Volume — teal accent, bold
Text('${item.totalBags} bags • ${_kgReadable(item.totalKg)} kg',
  style: const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Color(0xFF0D9488),  // brand teal
  ),
),

// Value — right-aligned, bold
Text(_inr0(item.totalCost),
  style: const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    color: Color(0xFF111827),
  ),
),

// Date / supplier — secondary
Text('${item.supplier} • ${DateFormat('dd MMM').format(item.lastDate)}',
  style: const TextStyle(
    fontSize: 11,
    color: Color(0xFF6B7280),
  ),
),
```

---

## ISSUE 14 — P3 · iPhone 16 Pro Notch / Dynamic Island Clipping
**File:** `purchase_home_page.dart`

### Fix
Ensure the top stat chip row is wrapped in a `SafeArea`:
```dart
SafeArea(
  bottom: false,
  child: _buildFilterChipRow(),
),
```

---

## ISSUE 15 — P3 · Report Page Text Colors Lacking Brand Accent
**File:** `reports_page.dart`

All value text (totals, bag counts) should use brand teal `Color(0xFF0D9488)` consistently. Body labels should use `Color(0xFF6B7280)` (grey-500), not black. Section headers `FontWeight.w700` minimum.

---

## PRODUCTION READINESS CHECKLIST

Before shipping, verify these are all green:

- [ ] **Issue 1** — Error boundary scoped to fatal errors only; Retry goes to home
- [ ] **Issue 2** — All async saves (PDF, payment, server sync) wrapped in try/catch with snackbar
- [ ] **Issue 3** — Edit Item uses `showModalBottomSheet(isScrollControlled: true)` with keyboard padding
- [ ] **Issue 4** — Supplier search grace period ≥ 800ms; `NeverScrollableScrollPhysics` on inline list; `autocorrect: false` on TextField
- [ ] **Issue 5** — Continue button uses `MediaQuery.viewInsetsOf(context).bottom` padding
- [ ] **Issue 6** — Purchase list ListView in `Expanded` + provider invalidated on init
- [ ] **Issue 7** — Reports provider has typed error + retry button in UI; filter changes debounced
- [ ] **Issue 8** — History page force-invalidates provider on open
- [ ] **Issue 9** — Home item tap uses `context.push('/item/${id}')` directly
- [ ] **Issue 10** — Avg weight / avg bags / avg rate tiles removed from reports
- [ ] **Issue 11** — Late delivery chip visible in purchase history cards; high-to-low sort chip added
- [ ] **Issue 12** — PDF includes supplier name, date, time; filename is human-readable
- [ ] **Issue 13** — Report tiles: item name dark+bold, volume teal+bold, value right-aligned+bold
- [ ] **Issue 14** — iPhone 16 Pro SafeArea wrapping filter row
- [ ] **Issue 15** — Brand teal applied to all value text in reports

---

## ARCHITECTURE NOTES

### Why the keyboard issues are worse on iPhone 16 Pro specifically
The Dynamic Island changes the safe area insets and the keyboard height calculation. `MediaQuery.viewInsetsOf(context)` returns the correct value but only **after** the keyboard animation completes. For smooth UX, use:
```dart
// Listen to keyboard animation, not just final state:
final kb = MediaQuery.viewInsetsOf(context).bottom;
// Animate with:
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  padding: EdgeInsets.only(bottom: kb),
  child: ...,
)
```

### Why suggestions close on scroll — gesture arena
Flutter resolves gesture arenas at the first `pointerDown`. When the user's finger moves onto the suggestion `ListView`, the arena competing are: (1) the wizard's parent `SingleChildScrollView` and (2) the suggestion `ListView`. Whichever claims the gesture first "wins". Setting `NeverScrollableScrollPhysics` on the inner list removes it from the arena entirely, leaving all vertical scroll to the parent — and the suggestion panel stays visible.

### Error boundary scope
`FlutterError.onError` is a global last-resort handler. It should only be used for unhandled exceptions that have already escaped all try/catch blocks. For every user action (PDF save, data sync, filter change), errors must be caught at the point of origin and shown inline. The boundary is a safety net, not the primary error handler.

---

*Generated by deep analysis of `PurchaseAssiastant-main` codebase + live screenshot UX review.*  
*All file paths relative to `flutter_app/lib/`.*
