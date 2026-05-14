# HARISREE PURCHASE ASSISTANT — MASTER CURSOR PROMPT
## Version: v16 Fix Pass | Date: 2026-05-13
## Priority: CRITICAL → HIGH → MEDIUM

---

## ⚠️ RULES — READ BEFORE TOUCHING CODE

```
DO NOT:
- Break existing SSOT unit engine (calc_engine.dart, central_calculation_engine.dart)
- Break GST / tax logic (purchase_tax_prefs.dart)
- Remove or alter delivery_aging.dart logic (already correct)
- Duplicate providers or calculations
- Hardcode text strings
- Introduce mismatched totals between PDF and dashboard

DO:
- Guard every timer callback with if (!mounted) return
- Guard every async gap (await) with if (!mounted) return
- Preserve all existing test contracts
- Keep bottom nav: Home | Reports | History | Search + FAB (already correct — DO NOT change)
- Keep FAB on bottom-right inside nav bar (already correct — DO NOT change)
- Run flutter analyze after every file change
```

---

## 🔴 PRIORITY 1 — CRITICAL CRASH (App blank on Home)

### Bug: "Bad state: Cannot use 'ref' after the widget was disposed"
**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

**Root cause:**
The `_handlePurchasePostSave()` method is called from `build()`. It calls
`WidgetsBinding.instance.addPostFrameCallback((_) async { ... ref.invalidate(...) })`.
This callback may fire after the widget is disposed. Additionally, `_loadCapTimer`
and `_resumeRefreshDebounce` timers access `ref` after possible disposal.
The `ShellScreen` `SchedulerBinding.addPostFrameCallback` also touches `ref` after
potential disposal.

**Exact fixes required:**

**Fix 1 — `_handlePurchasePostSave` in `home_page.dart`:**
```dart
// BEFORE (line ~519):
WidgetsBinding.instance.addPostFrameCallback((_) async {
  if (!mounted) {
    _handlingPurchasePostSave = false;
    return;
  }
  ref.invalidate(homeDashboardDataProvider);     // ← crashes if disposed
  ...

// AFTER: capture ref snapshot BEFORE the async gap
WidgetsBinding.instance.addPostFrameCallback((_) async {
  if (!mounted) {
    _handlingPurchasePostSave = false;
    return;
  }
  // Capture all reads synchronously before any await:
  final container = ProviderScope.containerOf(context, listen: false);
  container.invalidate(homeDashboardDataProvider);
  container.invalidate(homeShellReportsProvider);
  container.invalidate(reportsPurchasesPayloadProvider);
  invalidateTradePurchaseCachesFromContainer(container);
  container.read(purchasePostSaveProvider.notifier).state = null;
  _handlingPurchasePostSave = false;
  if (!mounted) return;
  final route = await showPurchaseSavedSheet(...);
  if (!mounted) return;
  ...
});
```

**Fix 2 — `_loadCapTimer` callback in `home_page.dart`:**
```dart
// BEFORE:
_loadCapTimer ??= Timer(const Duration(seconds: 6), () {
  if (!mounted) return;
  ref.read(homeDashboardDataProvider.notifier).forceStopRefreshing(); // ← ref access
  setState(() { ... });
});

// AFTER:
_loadCapTimer ??= Timer(const Duration(seconds: 6), () {
  if (!mounted) {
    _loadCapTimer = null;
    return;
  }
  ref.read(homeDashboardDataProvider.notifier).forceStopRefreshing();
  if (!mounted) return;
  setState(() {
    _loadCapReached = true;
    _loadCapTimer = null;
  });
});
```

**Fix 3 — `_resumeRefreshDebounce` callback in `home_page.dart`:**
```dart
// AFTER every await inside this timer callback add:
if (!mounted) return;
```

**Fix 4 — `ShellScreen` in `shell_screen.dart` (line ~24):**
```dart
// BEFORE:
final prevBranch = ref.read(shellCurrentBranchProvider);
if (prevBranch != idx) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (ref.read(shellCurrentBranchProvider) != idx) {
      ref.read(shellCurrentBranchProvider.notifier).state = idx;
    }
  });
}

// AFTER: This postFrameCallback fires after build returns. Use ref.notifier
// directly on next frame only if still valid:
WidgetsBinding.instance.addPostFrameCallback((_) {
  // ref is safe here because ConsumerWidget doesn't dispose mid-frame
  try {
    if (ref.read(shellCurrentBranchProvider) != idx) {
      ref.read(shellCurrentBranchProvider.notifier).state = idx;
    }
  } catch (_) {
    // Provider already disposed — ignore
  }
});
```

**Fix 5 — `_dashRefreshGuardTimer` callback:**
```dart
_dashRefreshGuardTimer = Timer(const Duration(seconds: 6), () {
  if (!mounted) {
    _dashRefreshGuardTimer = null;
    return;
  }
  _dashRefreshGuardTimer = null;
  try {
    ref.read(homeDashboardDataProvider.notifier).forceStopRefreshing();
  } catch (_) {}
});
```

**Verify fix:** After applying, hot-restart → home page must render content, not blank.

---

## 🔴 PRIORITY 2 — REPORT PDF: BAG COUNT COLUMN MISSING IN TABLE

**File:** `flutter_app/lib/core/services/reports_pdf.dart`
**Function:** `buildTradeStatementSsotPdfBytes`

**Current state:** Table has headers: `Date | Supplier | Item | Pack | Qty | Unit | Kg | Rate | Amount`
- The `Pack` column shows label text like "50 BAGS" but has no separate numeric bags column
- Totals footer EXISTS but is buried as plain text at the bottom

**Required changes:**

### Change A — Add "Bags" column to main table

Update the table headers and row builder:

```dart
// BEFORE headers:
const hdrs = ['Date', 'Supplier', 'Item', 'Pack', 'Qty', 'Unit', 'Kg', 'Rate', 'Amount'];

// AFTER headers (add Bags column, remove Pack label column):
const hdrs = ['Date', 'Supplier', 'Item', 'Qty', 'Unit', 'Bags', 'Kg', 'Rate', 'Amount'];
```

For each row, compute bag count:
```dart
// After building `final agg = buildTradeReportAgg(purchases);` and `final lines = buildTradeStatementLines(purchases);`
// Build a per-line bag count map using reportEffectivePack:
final lineBagCounts = <int, String>{};  // index → bag display
for (var i = 0; i < purchases.length; i++) {
  // ... map purchase lines to bag counts using reportEffectivePack
}

// In row builder for each line l:
final packInfo = reportEffectivePack(/* line */);
final bagsCell = (packInfo != null && packInfo.kind == ReportPackKind.bag)
    ? (packInfo.packQty == packInfo.packQty.roundToDouble()
        ? '${packInfo.packQty.round()}'
        : packInfo.packQty.toStringAsFixed(1))
    : '—';

rows.add([
  _df.format(l.date),
  l.supplierName,
  l.itemName,
  // qty
  l.qty == l.qty.roundToDouble() ? '${l.qty.round()}' : money2.format(l.qty),
  l.unit,
  bagsCell,   // ← new bags column
  l.kg < 1e-9 ? '—' : (l.kg == l.kg.roundToDouble() ? '${l.kg.round()}' : l.kg.toStringAsFixed(1)),
  money2.format(l.rate),
  money2.format(l.amountInr),
]);
```

### Change B — Upgrade the totals footer to a proper table

```dart
// REPLACE the plain summaryKv() text block with a proper summary table:
pw.Container(
  padding: const pw.EdgeInsets.all(8),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: _border, width: 0.5),
    color: _headerBg,
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('REPORT TOTALS',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: _border, width: 0.3),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.white),
            children: [
              _totCell('Bags', '${tt.bags > 1e-9 ? tt.bags.round() : 0}', bold: tt.bags > 0),
              _totCell('Boxes', '${tt.boxes > 1e-9 ? tt.boxes.round() : 0}', bold: tt.boxes > 0),
              _totCell('Tins', '${tt.tins > 1e-9 ? tt.tins.round() : 0}', bold: tt.tins > 0),
              _totCell('Total KG', tt.kg > 1e-9 ? '${tt.kg.round()} KG' : '—', bold: true),
              _totCell('Total Amount', 'Rs. ${_money.format(tt.inr)}', bold: true),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text('Period: ${_df.format(from)} → ${_df.format(to)}',
        style: const pw.TextStyle(fontSize: 8, color: _muted)),
      pw.Text('Generated: ${_genDf.format(DateTime.now())}',
        style: const pw.TextStyle(fontSize: 8, color: _muted)),
    ],
  ),
),
```

Add helper function near top of reports_pdf.dart:
```dart
pw.Widget _totCell(String label, String value, {bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label,
            style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          pw.Text(value,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: bold ? 10 : 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            )),
        ],
      ),
    );
```

### Change C — `layoutTradeStatementSsotPdf` stays the same (it calls buildTradeStatementSsotPdfBytes)
**No changes needed to the call site in reports_page.dart.**

---

## 🔴 PRIORITY 3 — PURCHASE HISTORY: DELIVERY AGING CARDS DUPLICATION & ICON OVERLAP

**Files to audit:**
- `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

**Issue 1 — Search icon overlap with FAB:**
The search bar in purchase history (`FocusedSearchChrome` / inline search field) overlaps
with the FAB button area. The search bar must not visually collide with the FAB.

**Fix:** Ensure `ListView` / `CustomScrollView` has `padding: EdgeInsets.only(bottom: 96)` 
so last card is not hidden behind FAB + bottom nav.

**Issue 2 — Duplicate aging icons on cards:**
Purchase history cards are showing DUPLICATE delivery aging chips. This happens because
the aging chip is being rendered in BOTH the card subtitle AND a separate chip row.

**Audit purchase_home_page.dart for this pattern:**
```dart
// Find any block like this (duplicated aging chip):
_historyMetaChip(...undeliveredAgingChipLabel...)  // line A
...
_historyMetaChip(...undeliveredAgingChipLabel...)  // line B — DUPLICATE

// Fix: render the aging chip ONCE only in the status chips row (4th row of card).
// Remove any aging chip from the subtitle/second row.
```

**Issue 3 — Card layout improvement:**
Each purchase card must follow this 4-row layout:
```
┌─────────────────────────────────────┐
│ [Supplier name]          ₹1,48,000  │  ← Row 1: bold
│ Rice 25kg × 50, Sugar × 10          │  ← Row 2: items summary
│ 50 bags • 1,250 kg                  │  ← Row 3: unit totals (teal/cyan styled)
│ 🚚 Pending  ⏰ 7d late  💰 Pay due  │  ← Row 4: status chips
└─────────────────────────────────────┘
```

Verify that `_packSummaryStyledSpans()` is called in Row 3 (already exists).
Verify aging chip is in Row 4 only (via `undeliveredAgingBandForPurchase`).
Verify `_historyMetaChip` is not duplicated.

**Issue 4 — Sort: longest pending FIRST**
The existing filter/sort logic must ensure when "Pending" filter is active, items are sorted
by `undeliveredDaysSincePurchase()` DESCENDING (most days at top).
```dart
// In the pending filter sort:
filtered.sort((a, b) {
  final dA = undeliveredDaysSincePurchase(a);
  final dB = undeliveredDaysSincePurchase(b);
  return dB.compareTo(dA);  // longest pending first
});
```

---

## 🟡 PRIORITY 4 — HOME DASHBOARD: APP BAR ICONS

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`
**Function:** `_buildAppBar()`

**Current:** Settings icon in wrong position / not top-right.
**Required:**
```dart
AppBar(
  // No leading action needed — empty or brand icon
  title: Text('HARISREE'),
  actions: [
    // Settings always top-right:
    IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () => context.push('/settings'),
    ),
  ],
)
```

Remove any duplicate settings icon that might exist in the body/appbar.
The notification bell (if present) goes BEFORE settings in actions row.

---

## 🟡 PRIORITY 5 — GLOBAL SEARCH: SEARCH ICON + BAR BEHAVIOR

**File:** `flutter_app/lib/features/search/presentation/search_page.dart`

**Current issues:**
- Search bar shows a duplicate keyboard/search area that conflicts with bottom nav
- Keyword search bar should auto-focus when Search tab is tapped

**Required behavior (Apple App Store style):**
1. Search tab in bottom nav → page opens with `autofocus: true` on the search field
2. Keyboard opens immediately
3. Below search field: horizontal filter chips row (All | Purchases | Suppliers | Brokers | Items | Bills)
4. Below chips: recent searches list (from `recentUnifiedSearchProvider`)
5. As user types: live search results grouped by category
6. NO separate search bar in the top AppBar — the search field IS the primary header

```dart
// In SearchPage build():
@override
Widget build(BuildContext context, WidgetRef ref) {
  return Scaffold(
    // NO AppBar with separate search — search field IS the top
    body: SafeArea(
      child: Column(
        children: [
          // 1. Search input (autofocus)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search purchases, suppliers, items…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        })
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // 2. Category filter chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_categories[i]),
                selected: _selectedCategory == i,
                onSelected: (_) => setState(() => _selectedCategory = i),
              ),
            ),
          ),
          // 3. Results
          Expanded(child: _buildResults(ref)),
        ],
      ),
    ),
  );
}
```

**Category list:**
```dart
static const _categories = ['All', 'Purchases', 'Suppliers', 'Brokers', 'Items', 'Bills'];
```

---

## 🟡 PRIORITY 6 — RESPONSIVE & OVERFLOW: BOTTOM PADDING

**All list screens** (`purchase_home_page.dart`, `reports_full_list_page.dart`,
`search_page.dart`, `home_page.dart`) must have scroll padding so content is not
hidden behind the bottom nav + FAB.

**Fix — apply to every primary ListView / CustomScrollView / SingleChildScrollView:**
```dart
// Add at the end of every scrollable list:
const SliverToBoxAdapter(child: SizedBox(height: 96)), // for slivers
// or
padding: const EdgeInsets.only(bottom: 96),  // for ListView
```

**Also fix — FAB overlap with search icon in purchase_home_page.dart:**
The inline search field / `FocusedSearchChrome` must have `margin/padding`
that keeps it above the bottom nav. Check if the search bar is positioned
near the bottom and add sufficient bottom offset.

---

## 🟡 PRIORITY 7 — PERFORMANCE: REDUCE REBUILDS

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

**Issue:** `_handlePurchasePostSave()` is called from `build()` on every rebuild,
which calls `ref.watch(purchasePostSaveProvider)` — this is fine (Riverpod handles it),
but if it also calls `setState` inside `build()` indirectly, it causes extra rebuilds.

**Fix:** Convert `_handlePurchasePostSave` to use `ref.listen` instead of
calling it from `build()`:

```dart
// In build(), REPLACE the _handlePurchasePostSave() call with:
ref.listen<dynamic>(purchasePostSaveProvider, (prev, next) {
  if (next == null || _handlingPurchasePostSave) return;
  _handlingPurchasePostSave = true;
  _doHandlePurchasePostSave(next);  // extracted async method
});
```

```dart
// New extracted method:
Future<void> _doHandlePurchasePostSave(dynamic payload) async {
  if (!mounted) { _handlingPurchasePostSave = false; return; }
  ref.invalidate(homeDashboardDataProvider);
  ref.invalidate(homeShellReportsProvider);
  ref.invalidate(reportsPurchasesPayloadProvider);
  invalidateTradePurchaseCaches(ref);
  ref.read(purchasePostSaveProvider.notifier).state = null;
  _handlingPurchasePostSave = false;
  if (!mounted) return;
  final route = await showPurchaseSavedSheet(context, ref,
    savedJson: payload.savedJson, wasEdit: payload.wasEdit);
  if (!mounted) return;
  final sid = payload.savedJson['id']?.toString();
  if (route == 'edit_missing' && sid != null && sid.isNotEmpty) {
    context.go('/purchase/edit/$sid');
  } else if (route == 'detail' && sid != null && sid.isNotEmpty) {
    context.go('/purchase/detail/$sid');
  }
}
```

---

## 🟡 PRIORITY 8 — VERCEL/WEB: HOME RENDER FAILURE DIAGNOSIS

**Root cause hypothesis:**
The Flutter Web build on Vercel is rendered from `main.dart.js`. The "blank screen" seen
in the screenshot is caused by the disposed-ref crash (Priority 1 above) crashing the
entire widget tree on initial mount.

**Additional web-specific fix in `main.dart`:**
```dart
void main() {
  // Catch Flutter framework errors and show them gracefully
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Do NOT rethrow — prevents full white-screen on web
  };
  
  runApp(
    ProviderScope(
      child: const HexaApp(),
    ),
  );
}
```

**Also check `flutter_app/lib/core/platform/remove_boot_overlay_web.dart`:**
Ensure the boot overlay is removed AFTER the first frame renders, not before.
If the overlay removal throws, it can blank the screen.

---

## 🟡 PRIORITY 9 — SUPABASE FREE TIER: CONNECTION POOL EXHAUSTION

**Context:** Backend is on Supabase Free (limited connections) + Render Free (cold starts).
Blank screen can also happen if ALL of these occur simultaneously on cold start:
- Dashboard provider fires
- Reports provider fires  
- Purchase list provider fires
- Session provider fires

**Fix — `api_warmup.dart`:** Ensure the warmup ping is the FIRST request and
subsequent providers wait for it via `ref.watch(apiWarmupProvider)` before
fetching data.

**Fix — Add connection delay stagger in `home_dashboard_provider.dart`:**
```dart
// If warmup not ready, stagger requests:
await ref.watch(apiWarmupProvider.future);
// Only THEN fetch dashboard data
```

---

## 🟡 PRIORITY 10 — NAV: BOTTOM NAV VISUAL CONSISTENCY

**File:** `flutter_app/lib/features/shell/shell_screen.dart`

**Current state is CORRECT:** Home | Reports | History | Search | [FAB]
**Do NOT change the navigation structure.**

**Minor fix needed:** The FAB container uses `SizedBox(width: 60)` which on
narrow screens (≤360px) can cause the nav tiles to be too narrow.

**Fix:**
```dart
// In _ShellBottomBar.build():
// Wrap nav tiles in LayoutBuilder to ensure minimum 42px tap targets:
Expanded(
  child: LayoutBuilder(
    builder: (context, constraints) {
      final tileWidth = (constraints.maxWidth - _fabOuter - 4) / 4;
      return Row(
        children: [
          // Each tile gets max(42, tileWidth):
          SizedBox(width: math.max(42, tileWidth), child: _ShellNavTile(...Home...)),
          SizedBox(width: math.max(42, tileWidth), child: _ShellNavTile(...Reports...)),
          SizedBox(width: math.max(42, tileWidth), child: _ShellNavTile(...History...)),
          SizedBox(width: math.max(42, tileWidth), child: _ShellNavTile(...Search...)),
        ],
      );
    }
  ),
),
```

---

## 🟡 PRIORITY 11 — OFFLINE CACHE STORE: ERROR ON INIT

**Console shows:** 
```
Got object store box in database offline_cache.
Got object store box in database offline_entries.
Got object store box in database purchase_wizard_draft.
Got object store box in database scan_queue.
Bad state: Cannot use "ref" after the widget was disposed.
```

The IndexedDB (Hive/Isar) object stores are opening fine. The crash happens
AFTER the stores initialize, during the first frame render of `HomePage`.
Confirm the fix in Priority 1 resolves this. If not, add error boundary:

**File:** `flutter_app/lib/app.dart`
```dart
// Wrap the router widget in an error boundary:
class HexaApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      ...
      builder: (context, child) {
        return _ErrorBoundary(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

class _ErrorBoundary extends StatefulWidget {
  final Widget child;
  const _ErrorBoundary({required this.child});
  @override
  State<_ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<_ErrorBoundary> {
  Object? _error;
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Material(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text('Something went wrong loading the app.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
```

---

## 🟢 PRIORITY 12 — PDF: REPORT PERIOD LABEL IMPROVEMENT

**File:** `flutter_app/lib/core/services/reports_pdf.dart`

**In `buildTradeStatementSsotPdfBytes`**, the period line currently shows:
```
${_df.format(from)} – ${_df.format(to)}
```
using a plain dash. Make it clearer and add report count:

```dart
pw.Text(
  'Period: ${_df.format(from)} → ${_df.format(to)}   |   ${purchases.length} purchases',
  style: const pw.TextStyle(fontSize: 9, color: _muted),
),
```

---

## 🟢 PRIORITY 13 — PURCHASE HISTORY: FILTER CHIPS UI

**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

Verify the existing filter chips row (Pending | Delivered | Critical | Due Soon) is:
1. Horizontally scrollable (not wrapping to 2 rows)
2. Not overlapping with the FAB
3. Has minimum 44px touch height

```dart
SizedBox(
  height: 44,
  child: ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    itemCount: _filterChips.length,
    separatorBuilder: (_, __) => const SizedBox(width: 8),
    itemBuilder: (context, i) => FilterChip(...),
  ),
),
```

---

## ✅ ALREADY DONE — DO NOT CHANGE

These are confirmed correct in the codebase. Do NOT re-implement or break them:

1. `delivery_aging.dart` — UndeliveredAgingBand logic ✅
2. `shell_screen.dart` bottom nav structure: Home|Reports|History|Search|FAB ✅  
3. FAB position: bottom-right inside nav bar ✅
4. `buildTradeStatementSsotPdfBytes` — has bag/box/tin totals footer ✅
5. `purchase_home_page.dart` — `_packSummaryStyledSpans()` for styled unit display ✅
6. `unifiedSearchProvider` — debounced server search ✅
7. SSOT unit engine — do not touch ✅
8. GST calc — do not touch ✅

---

## 📋 EXECUTION ORDER FOR CURSOR

Work through this list in order. Do NOT batch-edit unrelated files.

```
STEP 1: Fix disposed-ref crash in home_page.dart          → fixes blank screen
STEP 2: Fix disposed-ref in shell_screen.dart             → prevents nav crash  
STEP 3: Add error boundary in app.dart                    → prevents white screen
STEP 4: Add bottom padding to all list screens (96px)     → fixes FAB overlap
STEP 5: Fix PDF bag count column + totals table           → reports_pdf.dart
STEP 6: Fix purchase card aging chip duplication          → purchase_home_page.dart
STEP 7: Fix search page autofocus + category chips        → search_page.dart
STEP 8: Fix home app bar settings icon position           → home_page.dart _buildAppBar
STEP 9: Fix pending sort: longest days first              → purchase_home_page.dart
STEP 10: Convert _handlePurchasePostSave to ref.listen    → home_page.dart (perf)
STEP 11: Add bottom nav tile min-width guard              → shell_screen.dart
STEP 12: Improve PDF period label + purchase count        → reports_pdf.dart
```

---

## 🔍 FILES TO AUDIT BEFORE CHANGING

Before editing any file, Cursor must READ the full current content:

| File | What to check |
|------|--------------|
| `home_page.dart` | All timer callbacks for `!mounted` guards |
| `shell_screen.dart` | SchedulerBinding postFrameCallback safety |
| `purchase_home_page.dart` | Duplicate chip renders, FAB overlap, sort logic |
| `reports_pdf.dart` | Existing bag/box/tin columns, totals footer |
| `search_page.dart` | Existing autofocus, chip filters, keyboard behavior |
| `app.dart` | Error boundary presence |
| `main.dart` | FlutterError.onError handler |

---

## 🚀 DEPLOYMENT CHECK

After all fixes, before pushing to Vercel:

```bash
# In flutter_app/:
flutter analyze --no-fatal-warnings
flutter test
flutter build web --release --dart-define=FLUTTER_WEB_CANVASKIT_URL=https://unpkg.com/canvaskit-wasm@0.38.2/bin/

# Check output size < 5MB main.dart.js (Vercel free has no size limit but CDN matters)
```

Vercel env vars must include:
```
FLUTTER_WEB_RENDERER=canvaskit
```

---

## ⚠️ CURSOR FOLLOW-UP RULE

After each step, Cursor must:
1. Run `flutter analyze` on changed files
2. Report any NEW errors introduced
3. Confirm: "Step N complete. X errors before, Y errors after."
4. NOT proceed to next step if errors increased

---
*Generated by Claude | HARISREE Purchase Assistant v16 | 2026-05-13*
