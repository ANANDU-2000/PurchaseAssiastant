# Purchase Assistant — COMPLETE PRODUCTION FIX v20
# One-tap build prompt: Give this entire file to your developer / AI coder.
# All fixes include EXACT file paths, FIND text, and REPLACE text.
# Apply in the order listed. Each fix is independent unless noted.

---

## CRITICAL P0 — WRONG PROFIT NUMBER IN PURCHASE DETAIL

**Symptom:** SUGAR 50 KG shows Profit ₹1,37,25,000 on a ₹2,88,750 purchase. Impossible number.

**Root cause:** `sellingGross` getter in `trade_purchase_models.dart` multiplies the per-bag selling
rate (₹2800/bag) by `kgPerUnit` (50), treating it as a per-kg rate.
Result: `100 bags × 50 kg × ₹2800 = ₹1.4 Cr` instead of `100 × ₹2800 = ₹2.8L`.

**File:** `flutter_app/lib/core/models/trade_purchase_models.dart`

**FIND:**
```dart
  /// Gross selling when [sellingCost] is set (per-kg when weight line).
  double get sellingGross {
    final rate = sellingRate ?? sellingCost;
    if (rate == null) return 0;
    if (kgPerUnit != null &&
        landingCostPerKg != null &&
        kgPerUnit! > 0) {
      return qty * kgPerUnit! * rate;
    }
    return qty * rate;
  }
```

**REPLACE WITH:**
```dart
  /// Gross selling value for the line.
  /// Uses direct per-unit multiplication when selling rate is per-bag/box/unit.
  /// Only multiplies by kgPerUnit when the rate is clearly per-kg scale
  /// (i.e., similar magnitude to landingCostPerKg, not per-bag scale).
  double get sellingGross {
    final rate = sellingRate ?? sellingCost;
    if (rate == null) return 0;
    if (kgPerUnit != null && kgPerUnit! > 0 &&
        landingCostPerKg != null && landingCostPerKg! > 0) {
      // Determine if selling rate is per-kg or per-bag by comparing
      // to the known per-kg landing rate. If ratio is within 2×, it's per-kg.
      final directRatio = rate / landingCostPerKg!;
      if (directRatio >= 0.5 && directRatio <= 2.0) {
        // Per-kg selling rate (e.g. sell=₹56/kg, land=₹55/kg → ratio≈1)
        return qty * kgPerUnit! * rate;
      }
      // Per-unit rate (e.g. sell=₹2800/bag, land=₹55/kg → ratio=50.9)
      // Do NOT multiply by kgPerUnit.
    }
    return qty * rate;
  }
```

---

## CRITICAL P0 — SNACKBAR / TOAST BLOCKS BUTTONS (bottom overlap)

**Symptom:** "Marked paid", "Could not export PDF", "Restored draft" — all appear at BOTTOM,
covering buttons. Old users cannot dismiss or read them. (Images 11, 12)

**Fix:** Set all SnackBars to `floating` behavior and show at TOP via `margin`.

**File:** `flutter_app/lib/app.dart`

Add a global SnackBar theme inside `ThemeData` in `MaterialApp`:

**FIND** the `ThemeData` builder (usually `theme: ThemeData(...)`) and **ADD**:
```dart
snackBarTheme: const SnackBarThemeData(
  behavior: SnackBarBehavior.floating,
  // Float above bottom nav — users can always see and dismiss
),
```

**ADDITIONALLY** — for every `showSnackBar` call across the entire app, add this helper function
to a new file `flutter_app/lib/core/utils/snack.dart`:

```dart
import 'package:flutter/material.dart';

/// Shows a snackbar that floats at the TOP of the screen so it never blocks
/// any footer button, bottom bar, or CTA. Colorized by severity.
void showTopSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_rounded : Icons.check_circle_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFB91C1C) : const Color(0xFF0D6B5E),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        // Position near the TOP of the screen below the status bar
        bottom: MediaQuery.of(context).size.height - 
                MediaQuery.of(context).padding.top - 80,
      ),
      duration: duration,
      action: action,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
```

Then replace every `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` with:
```dart
showTopSnack(context, 'Your message here');
// or for errors:
showTopSnack(context, 'Error message', isError: true);
```

Key replacements:
- `'Marked paid'` → `showTopSnack(context, 'Marked as paid ✓')`
- `'Could not export PDF. Try again.'` → `showTopSnack(context, 'Could not export PDF. Check connection and retry.', isError: true)`
- `'Restored your unsaved purchase draft'` → `showTopSnack(context, 'Draft restored ✓')`
- All other success/error messages follow the same pattern.

---

## P0 — MARK DELIVERED TAKES 3 SECONDS (no optimistic update)

**Symptom:** Tapping "Mark Delivered" shows nothing for 3 seconds then updates.
Old users tap it again thinking it didn't work, causing double-toggle.

**File:** `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`

**FIND:**
```dart
  Future<void> _toggleDelivery(
    BuildContext context,
    WidgetRef ref,
    TradePurchase p,
  ) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).markPurchaseDelivered(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            isDelivered: !p.isDelivered,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
    } catch (e) {
```

**REPLACE WITH:**
```dart
  Future<void> _toggleDelivery(
    BuildContext context,
    WidgetRef ref,
    TradePurchase p,
  ) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final newDelivered = !p.isDelivered;
    // OPTIMISTIC UPDATE — show change instantly
    ref.read(tradePurchaseDetailProvider(p.id).notifier)
        .setOptimisticDelivered(newDelivered);
    showTopSnack(
      context,
      newDelivered ? '✅ Marked as delivered' : 'Marked as pending delivery',
    );
    try {
      await ref.read(hexaApiProvider).markPurchaseDelivered(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            isDelivered: newDelivered,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
    } catch (e) {
      // Revert optimistic update on failure
      ref.read(tradePurchaseDetailProvider(p.id).notifier)
          .setOptimisticDelivered(!newDelivered);
```

**Also in `trade_purchase_detail_provider.dart` add:**
```dart
// In the notifier class, add this method:
void setOptimisticDelivered(bool delivered) {
  final cur = state.valueOrNull;
  if (cur == null) return;
  // Create a copy with updated delivery status
  state = AsyncData(cur.copyWithDelivered(delivered));
}
```

**In `TradePurchase` model add:**
```dart
TradePurchase copyWithDelivered(bool delivered) {
  return TradePurchase(
    id: id, humanId: humanId, purchaseDate: purchaseDate,
    // ... all existing fields ...
    isDelivered: delivered,
    deliveredAt: delivered ? DateTime.now() : deliveredAt,
  );
}
```

Also make the **"Mark Delivered" button visually prominent** for older users:

**FIND the delivery toggle button build** (around line 748 in `purchase_detail_page.dart`) and
wrap the delivery card in a highlighted border when delivery is pending:

```dart
// Change the delivery status card container:
Container(
  decoration: BoxDecoration(
    color: p.isDelivered ? Colors.green.shade50 : Colors.orange.shade50,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: p.isDelivered ? Colors.green.shade300 : Colors.orange.shade400,
      width: p.isDelivered ? 1 : 2.5,  // thicker border when pending
    ),
  ),
  // ... existing content ...
)
```

---

## P1 — KEYBOARD DISMISS CLOSES SUGGESTIONS (onDrag still enabled)

**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

**FIND:**
```dart
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
```

**REPLACE WITH:**
```dart
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
```

**Also in supplier field** — `purchase_party_step.dart` lines 407, 450, 509:

**FIND** each `PartyInlineSuggestField` for supplier (search for `debugLabel: 'supplier'`) and add:
```dart
  debugLabel: 'supplier',
  suggestionsAsOverlay: true,   // MUST be true to survive keyboard dismiss on iOS
```

---

## P1 — AUTO-REFRESH ON TAB SWITCH (user must click refresh icon)

**File:** `flutter_app/lib/features/shell/shell_screen.dart`

**FIND** the `navigationShell.currentIndex` handler and **ADD** auto-invalidation:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final idx = navigationShell.currentIndex;
  final prevBranch = ref.read(shellCurrentBranchProvider);
  if (prevBranch != idx) {
    ref.read(shellCurrentBranchProvider.notifier).state = idx;
    // Auto-refresh data when switching tabs (not on first mount)
    if (prevBranch >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (idx) {
          case ShellBranch.home:
            ref.invalidate(homeDashboardDataProvider);
            ref.invalidate(homeShellReportsProvider);
            break;
          case ShellBranch.history:
            invalidateTradePurchaseCaches(ref);
            break;
          case ShellBranch.reports:
            ref.invalidate(reportsPurchasesPayloadProvider);
            break;
        }
      });
    }
  }
  // ... rest of build
```

Also **reduce the home poll from 10 minutes to 5 minutes:**

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

**FIND:** `Timer.periodic(const Duration(minutes: 10), (_) {`
**REPLACE:** `Timer.periodic(const Duration(minutes: 5), (_) {`

---

## P1 — PDF EXPORT NOT WORKING

**Root cause:** `Printing.sharePdf` on iOS requires the `printing` package to have a valid
`NSPhotoLibraryAddUsageDescription` in `Info.plist` AND may fail silently without proper
entitlements for sharing to other apps. The try/catch swallows the error.

**Immediate fix — log the actual error:**

**File:** `flutter_app/lib/core/services/purchase_pdf.dart`

**FIND:**
```dart
void _logPdfFailure(String op, Object e, StackTrace st) {
```

**ADD** inside that function:
```dart
  // Also print to debug console for developer diagnosis:
  debugPrint('PDF $op FAILED: $e\n$st');
  // Report as non-fatal so crash analytics capture it:
  FlutterError.reportError(FlutterErrorDetails(
    exception: e, stack: st,
    library: 'purchase_pdf',
    context: ErrorDescription('PDF $op failed'),
    silent: true,
  ));
```

**Alternative share path** (if `Printing.sharePdf` fails on iOS):

```dart
Future<bool> sharePurchasePdf(TradePurchase p, BusinessProfile biz) async {
  try {
    final doc = await buildPurchaseDoc(p, biz);
    final bytes = await doc.save();
    final filename = buildPurchaseSharePdfFileName(p);
    
    // Try Printing first, fall back to Share.shareXFiles
    try {
      await Printing.sharePdf(bytes: bytes, filename: filename);
      return true;
    } catch (printingError) {
      debugPrint('Printing.sharePdf failed ($printingError), trying share_plus');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: '${p.supplierName ?? 'Purchase'} — ${p.humanId}',
      );
      return true;
    }
  } catch (e, st) {
    _logPdfFailure('share', e, st);
    return false;
  }
}
```

Add to `pubspec.yaml` if not present: `share_plus: ^10.0.0`

---

## P2 — PURCHASE HISTORY CARDS: BOLD COLORED NUMBERS

**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

Find the purchase list card widget (search for `_PurchaseRow` or the card builder).
Update the quantity/amount display to use bold colored text:

```dart
// Bags/Boxes/Kg numbers — teal bold
Text(
  '${p.totalBags > 0 ? "${_qty(p.totalBags)} bags" : ""}${p.totalKg > 0 ? " • ${_qty(p.totalKg)} kg" : ""}',
  style: const TextStyle(
    color: Color(0xFF0D9488),   // teal
    fontWeight: FontWeight.w700,
    fontSize: 12.5,
  ),
),

// Total amount — dark bold, right-aligned
Text(
  _inr(p.totalAmount),
  style: const TextStyle(
    color: Color(0xFF111827),
    fontWeight: FontWeight.w800,
    fontSize: 15,
  ),
  textAlign: TextAlign.right,
),

// Status chip — color by status
Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: _statusChipBg(p),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _statusChipBorder(p), width: 1),
  ),
  child: Text(
    _statusLabel(p),
    style: TextStyle(
      color: _statusChipFg(p),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  ),
),
```

---

## P2 — UNDELIVERED TAB: SORT BY MOST OVERDUE DAYS FIRST

The `purchaseHistoryUndeliveredSortProvider` exists but the button may not be prominent enough.
Ensure the "Awaiting" tab automatically enables the undelivered sort when tapped.

**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

**FIND** where the primary filter chips are built and where `pending_delivery` is set:

```dart
// When user taps "Awaiting" chip, also enable undelivered sort:
onSelected: (_) {
  ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'pending_delivery';
  // Auto-sort by most overdue (most days waiting → top)
  ref.read(purchaseHistoryUndeliveredSortProvider.notifier).state = true;
},
```

**AND** when they leave the Awaiting tab, reset the sort:
```dart
// When tapping any OTHER filter chip:
onSelected: (_) {
  ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = newFilter;
  ref.read(purchaseHistoryUndeliveredSortProvider.notifier).state = false;
},
```

**Make the "Overdue" count in the chip badge RED and BOLD:**
```dart
// In the chip badge for overdue count:
Container(
  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
  decoration: BoxDecoration(
    color: Colors.red.shade600,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Text(
    '$overdueCount',
    style: const TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.w800,
    ),
  ),
),
```

---

## P2 — REPORTS PAGE: REMOVE "WEIGHTED" AND "AVG" LABELS

**File:** `flutter_app/lib/features/reports/reporting/reports_item_metrics.dart`

**FIND:**
```dart
String reportKgWeightedRateLabel(num? rate) {
  if (rate == null || rate <= 0) return '—';
  return '${_fmtRate(rate)}/kg (weighted)';
}
```

**REPLACE WITH:**
```dart
String reportKgWeightedRateLabel(num? rate) {
  if (rate == null || rate <= 0) return '—';
  return '${_fmtRate(rate)}/kg';  // Remove "(weighted)" label
}
```

In `reports_page.dart` and `item_analytics_detail_page.dart`, remove any display of:
- "avg landing" → show as "Rate"
- "avg selling" → show as "Sell Rate"  
- "weighted" suffix → remove completely
- "Avg margin" → show as "Profit/kg"

---

## P2 — ITEM HISTORY IN REPORTS: SHOW REAL DATA

**File:** `flutter_app/lib/features/reports/reporting/reports_item_metrics.dart` and
`reports_page.dart`

In the item drill-down (Sugar 50 KG transactions screen — Image 5/6), each transaction row
should show:
```
[Date] — [Supplier]
[Qty] kg • [Bags] bags
Purchase: ₹[rate]/bag → Sell: ₹[rate]/bag
[Line Total]
```

Remove the "(weighted)" suffix from rate display. Show actual rates, not averages.

---

## P2 — CONTINUE BUTTON KEYBOARD SAFE (party + terms steps)

**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

The footer `AnimatedContainer` already has the math but uses an unsafe subtraction.
Verify this calculation doesn't produce a negative value:

**FIND:**
```dart
                    padding: EdgeInsets.fromLTRB(
                      12,
                      8,
                      12,
                      8 + (kbInset > 0 ? kbInset - MediaQuery.paddingOf(ctx).bottom : 0),
                    ),
```

**REPLACE WITH:**
```dart
                    padding: EdgeInsets.fromLTRB(
                      12,
                      8,
                      12,
                      // Lift footer above keyboard. Clamp to 0 to prevent negative padding.
                      8 + (kbInset > 0
                          ? (kbInset - MediaQuery.paddingOf(ctx).bottom).clamp(0.0, 500.0)
                          : 0),
                    ),
```

---

## P2 — ADD ITEM PAGE: COMPACT SUMMARY ALWAYS VISIBLE WHEN KEYBOARD OPEN

The previewPinned double-counting was partially fixed. Confirm the fix is complete:

**File:** `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart`

**FIND (around line 3763):**
```dart
                final imeBottom = MediaQuery.viewInsetsOf(context).bottom;
                final safeBottom = MediaQuery.paddingOf(context).bottom;
                final double previewBottomPad = imeBottom > 0
                    ? imeBottom + 12.0
                    : (safeBottom > 0 ? safeBottom + 8.0 : 12.0);
```

**REPLACE WITH:**
```dart
                // Scaffold.resizeToAvoidBottomInset:true already shrinks the body.
                // ONLY add safe-area bottom — never add imeBottom (double-counts).
                final safeBottom = MediaQuery.paddingOf(context).bottom;
                final double previewBottomPad = safeBottom > 0 ? safeBottom + 8.0 : 12.0;
```

---

## P3 — REPORTS TIME PERIOD SLOW UPDATE

**File:** `flutter_app/lib/features/reports/presentation/reports_page.dart`

Debounce the period filter with `Timer` to avoid multiple simultaneous requests:

```dart
Timer? _periodDebounce;

void _onPresetTap(_DatePreset preset) {
  if (_preset == preset) return;
  setState(() => _preset = preset);
  _periodDebounce?.cancel();
  _periodDebounce = Timer(const Duration(milliseconds: 150), () {
    _bumpInvalidate();  // trigger the actual refetch after brief debounce
  });
}
```

---

## P3 — BACKUP ZIP: PDF ONLY (NO CSV)

**File:** wherever the backup/export ZIP is generated (search for `ZipEncoder` or `zip` in codebase).

Change the backup to generate PDF files only:
```dart
// Only include PDF files in backup
if (fileName.endsWith('.pdf')) {
  archive.addFile(ArchiveFile(fileName, content.length, content));
}
// Skip .csv files entirely
```

---

## COMPLETE QA CHECKLIST — ALL MUST PASS

```
PROFIT CALCULATION:
[ ] SUGAR 50 KG (₹2750/bag buy, ₹2800/bag sell, 100 bags)
    → Profit = ₹5,000 (NOT ₹1,37,25,000)
[ ] Per-kg item (₹55/kg buy, ₹56/kg sell, 50kg)
    → Profit = ₹50 (per-kg rate × kgPerUnit correct)

TOASTS / SNACKBARS:
[ ] "Marked paid" → appears at TOP of screen
[ ] "Could not export PDF" → appears at TOP in RED
[ ] "Draft restored" → appears at TOP in GREEN
[ ] No toast covers any button
[ ] Toast is readable without any scrolling or action
[ ] Old person can read it comfortably

MARK DELIVERED:
[ ] Tap "Mark as Delivered" → UI updates INSTANTLY (< 100ms)
[ ] Toast shows "✅ Marked as delivered" at TOP immediately
[ ] Delivery card shows PENDING state with THICK ORANGE border
[ ] Delivery card shows DELIVERED state with green border

KEYBOARD:
[ ] Type "sura" in supplier field → suggestions appear
[ ] Scroll suggestion list → suggestions DO NOT close
[ ] Tap supplier → selected → broker field focused
[ ] Terms page Continue button → always visible above keyboard
[ ] Add item: qty field focused → all fields + buttons visible above keyboard

AUTO-REFRESH:
[ ] Switch from Home to History tab → list refreshes automatically
[ ] Switch from History to Reports → reports refresh automatically
[ ] Return from background → home dashboard refreshes (< 1 second)
[ ] No refresh icon tap needed for basic navigation

PDF EXPORT:
[ ] Tap PDF button → share sheet opens (not "Could not export")
[ ] PDF includes supplier name, date, purchase ID
[ ] PDF filename: "SURAG_15May2026_PUR-2026-0013.pdf"

REPORTS:
[ ] No "(weighted)" text anywhere in reports
[ ] No "avg" prefix on rates
[ ] Time period filter updates within 200ms of tap
[ ] Each item shows: total bags, total kg, last purchase rate

PURCHASE HISTORY:
[ ] Bag/kg numbers are TEAL + BOLD
[ ] Total amount is DARK + BOLD
[ ] Awaiting tab → sorted by MOST OVERDUE DAYS first
[ ] Overdue count badge is RED with white text
[ ] Each card shows supplier name, date, items summary, amount

PURCHASE DETAIL:
[ ] Amount, Weight, Profit all correct (verify with known test purchase)
[ ] Edit / Share / Print / PDF buttons all WORK (no silent failures)
[ ] Mark as Paid button visible and accessible (not covered by anything)
```

---

## DEVELOPER NOTES

### Profit Bug Severity
This shows wrong profit to business owners managing crore-level purchases.
The error is 500× the actual profit. **Fix this before anything else.**

### iOS PDF Fix
The `Printing.sharePdf` failure is likely an entitlements issue or network failure
loading the logo. The fallback to `Share.shareXFiles` will work on all iOS versions.
Also check `Info.plist` has `NSPhotoLibraryAddUsageDescription` if saving to photos.

### Snackbar Position
Flutter SnackBars with `SnackBarBehavior.floating` and a custom `margin.bottom` equal to
`screenHeight - statusBarHeight - snackbarHeight - 8` will appear at the TOP. This is the
correct pattern for ERP apps where the bottom is always occupied by action buttons.

### Mark Delivered UX
The visual distinction between "Pending Delivery" (orange border, thick, 2.5px) and
"Delivered" (green border, thin, 1px) gives old users an immediate clear signal without
needing to read text. This is critical for wholesale traders who mark dozens of orders.
