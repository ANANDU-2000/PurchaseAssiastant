# CURSOR AGENT MASTER PROMPT — Purchase Assistant Flutter App
> Paste this ENTIRE prompt into Cursor Composer (Agent mode, claude-sonnet or GPT-4o).
> DO NOT split. Agent works file-by-file, updates SOLUTION_TASKS.md checkboxes as it completes each task.
> No code comments needed unless logic is non-obvious. No new features — only fixes and improvements listed here.

---

## WHO YOU ARE

You are a senior Flutter/Dart engineer for the HexaStack PurchaseAssistant app. Stack: Flutter 3.x, Dart 3.3, Riverpod 2.6, GoRouter 14, Dio 5.7, Hive 2.2, FastAPI backend.

## GROUND RULES

1. **No code generation that isn't explicitly listed below.** Fix only what is in this prompt.
2. After EVERY completed task: update the checkbox in `SOLUTION_TASKS.md` with ✅ and today's date.
3. After EVERY file change: run `flutter analyze` and fix all NEW errors before moving on.
4. NEVER break existing tests. Run `flutter test` after each phase.
5. Do NOT add `print()` statements.
6. Do NOT change pubspec unless explicitly told to.
7. Use existing imports — do not add new packages without instruction.

---

## PHASE 0 — START HERE: CRITICAL BLOCKERS

Work through these in exact order. Each one unblocks real users.

---

### TASK 0-A: Fix HSN Blocking All Bag Saves

**File:** `flutter_app/lib/features/purchase/domain/purchase_draft.dart`

Find the function `purchaseLineSaveBlockReason`. Find this block near line 502:

```dart
final tax = l.taxPercent ?? 0;
if (tax > 0 || unitIsBag) {
  if ((l.hsnCode ?? '').trim().isEmpty) {
    return 'HSN is required when the line has tax or the unit is bag.';
  }
}
```

Change it to:

```dart
final tax = l.taxPercent ?? 0;
if (tax > 0) {
  if ((l.hsnCode ?? '').trim().isEmpty) {
    return 'HSN code is required for taxed items (tax% > 0).';
  }
}
```

That's the only change in this file. Save. Run:
```bash
cd flutter_app && flutter test test/purchase_draft_calc_test.dart
```

Update SOLUTION_TASKS.md: T-001 ✅

---

### TASK 0-B: Move Image Decode to Flutter Isolate

**File:** `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`

Step 1 — Add import at top of file (find the existing imports block):
```dart
import 'package:flutter/foundation.dart' show compute;
```

Step 2 — Find the `_compressForUpload` method inside `_ScanPurchaseV2PageState`. Extract its body to a **top-level** (outside any class) static function. Replace the class method with a call to `compute`:

```dart
// TOP-LEVEL function (outside all classes — place it above the class definition):
List<int> _compressImageIsolate(List<int> raw) {
  final decoded = img.decodeImage(Uint8List.fromList(raw));
  if (decoded == null) return raw;
  const maxW = 1600;
  final resized =
      decoded.width > maxW ? img.copyResize(decoded, width: maxW) : decoded;
  return List<int>.from(img.encodeJpg(resized, quality: 82));
}

// REPLACE the _compressForUpload method inside the class:
Future<List<int>> _compressForUpload(List<int> raw) async {
  return compute(_compressImageIsolate, raw);
}
```

Run: `flutter analyze`

Update SOLUTION_TASKS.md: T-002 ✅

---

### TASK 0-C: Add `piece` Unit to Save Validation

**File:** `flutter_app/lib/features/purchase/domain/purchase_draft.dart`

Step 1 — Find the three existing unit helper functions near the bottom of the file:
```dart
bool _isBagUnit(String unit) { ... }
bool _isBoxUnit(String unit) => ...
bool _isTinUnit(String unit) => ...
```

Add immediately after `_isTinUnit`:
```dart
bool _isPieceUnit(String unit) {
  final x = unit.trim().toLowerCase();
  return x == 'piece' || x == 'pcs' || x == 'pieces';
}
```

Step 2 — In `purchaseLineSaveBlockReason`, find:
```dart
final unitIsBox = _isBoxUnit(l.unit);
final unitIsTin = _isTinUnit(l.unit);
```

Add after:
```dart
final unitIsPiece = _isPieceUnit(l.unit);
```

Step 3 — Find the whole-number qty check:
```dart
if (unitIsBag || unitIsBox || unitIsTin) {
  if ((l.qty - l.qty.roundToDouble()).abs() > 1e-6) {
    return 'Use a whole number quantity for ${l.unit.trim()} lines (no decimals).';
  }
}
```

Change condition to include `|| unitIsPiece`.

Step 4 — Find the BOX/TIN early-return section:
```dart
if (unitIsBox || unitIsTin) {
  if (l.landingCost <= 0) {
    return 'Purchase rate must be greater than 0.';
  }
  return null;
}
```

Add a similar block immediately after (before the weightLine/bag checks):
```dart
if (unitIsPiece) {
  if (l.landingCost <= 0) {
    return 'Purchase rate must be greater than 0.';
  }
  return null;
}
```

Run: `flutter test test/purchase_draft_calc_test.dart`

Update SOLUTION_TASKS.md: T-003 ✅

---

### TASK 0-D: Fix AI Scan Landing Cost Rate Heuristic

**File:** `flutter_app/lib/features/purchase/mapping/ai_scan_purchase_draft_map.dart`

Find the BAG processing block inside `purchaseDraftFromScanResultJson` (around line 140):

```dart
if (ut.toUpperCase() == 'BAG' && wpu != null && wpu > 0) {
  kgPerUnit = wpu;
  final looksPerBag = pr >= 500;
  if (looksPerBag) {
    landingCost = pr;
    landingCostPerKg = pr / wpu;
  } else {
    landingCostPerKg = pr;
    landingCost = pr * wpu;
  }
}
```

Replace with:
```dart
if (ut.toUpperCase() == 'BAG' && wpu != null && wpu > 0) {
  kgPerUnit = wpu;
  // Use explicit rate_context from scanner if present.
  // Default: treat scanned purchase_rate as per-bag (most bill formats show per-bag price).
  final rateContext = it['rate_context']?.toString().trim().toLowerCase() ?? 'per_bag';
  if (rateContext == 'per_kg') {
    landingCostPerKg = pr;
    landingCost = pr > 0 && wpu > 0 ? pr * wpu : pr;
  } else {
    // per_bag (default)
    landingCost = pr;
    landingCostPerKg = pr > 0 && wpu > 0 ? pr / wpu : null;
  }
}
```

Run: `flutter test test/ai_scan_purchase_draft_map_test.dart`

Update SOLUTION_TASKS.md: T-004 ✅

---

### TASK 0-E: Fix Category Seed `default_unit` for Wholesale Items

**File:** Find the categories seed file. Check these locations in order:
1. `data/categories_seed.json`
2. `backend/app/data/categories_seed.json`
3. `scripts/categories_seed.json`

Find and update these specific entries (match by `"name"` field):

```json
// SUGAR: change "piece" → "bag"
{ "name": "SUGAR", "hsn": "17011400", "default_unit": "bag" }

// SALT: change "piece" → "bag"  
{ "name": "SALT", "hsn": "25010090", "default_unit": "bag" }

// EDIBLE OIL: change "piece" → "tin"
{ "name": "EDIBLE OIL", "hsn": "15091000", "default_unit": "tin" }

// DALDA: change "piece" → "tin"
{ "name": "DALDA", "hsn": "15161010", "default_unit": "tin" }

// OIL: change "piece" → "tin"
{ "name": "OIL", "hsn": "15091000", "default_unit": "tin" }

// KAAYAM: change "piece" → "kg"
{ "name": "KAAYAM", "hsn": "09099900", "default_unit": "kg" }
```

Also update `products_by_category_seed.json` if it exists. Run any seed migration scripts found in `scripts/`.

Update SOLUTION_TASKS.md: T-005 ✅

---

## PHASE 1 — HIGH PRIORITY BUG FIXES

Work through these after Phase 0 is complete and `flutter test` passes.

---

### TASK 1-A: Fix `_isBagOrSackUnit` Missing SACK

**File:** `flutter_app/lib/core/utils/unit_classifier.dart`

Find:
```dart
static bool _isBagOrSackUnit(String effU) {
  return effU == 'BAG';
}
```

Change to:
```dart
static bool _isBagOrSackUnit(String effU) {
  return effU == 'BAG' || effU == 'SACK';
}
```

Run: `flutter test test/bag_infer_from_name_test.dart && flutter test test/package_rules_test.dart`

Update SOLUTION_TASKS.md: T-007 ✅

---

### TASK 1-B: Fix Draft Hive Flush on App Background

**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

Find `_PurchaseEntryWizardV2State`. Check if it already has `with WidgetsBindingObserver`. If NOT:
- Add `with WidgetsBindingObserver` to the class declaration
- In `initState()`: add `WidgetsBinding.instance.addObserver(this);`
- In `dispose()`: add `WidgetsBinding.instance.removeObserver(this);`

Then add this method to the state class:
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  if (state == AppLifecycleState.paused && _formDirty) {
    // Immediately persist any debounced draft changes before OS may kill the process.
    _draftDebounce?.cancel();
    _saveDraftNow();
  }
}
```

Find the existing `_saveDraft()` or debounce-save method. Create or update `_saveDraftNow()` to call it synchronously (without debounce):
```dart
void _saveDraftNow() {
  // Call the same Hive/prefs write that _draftDebounce calls, but immediately.
  // Find the existing persist logic (search for 'toPrefsMap' or 'saveWip') and call it here.
}
```

Update SOLUTION_TASKS.md: T-011 ✅

---

### TASK 1-C: Add TTL to Contacts Hub KeepAlive Providers

**File:** `flutter_app/lib/core/providers/contacts_hub_provider.dart`

For each of the 4 providers in this file that uses `ref.keepAlive()`:

Find the pattern:
```dart
ref.keepAlive();
```

Replace with:
```dart
final _keepAliveLink = ref.keepAlive();
Timer(const Duration(minutes: 30), _keepAliveLink.close);
```

Make sure `import 'dart:async';` is at the top of the file.

Update SOLUTION_TASKS.md: T-009 ✅

---

### TASK 1-D: Fix Report Aggregate KG Cap

**File:** `flutter_app/lib/core/reporting/trade_report_aggregate.dart`

Find:
```dart
if (v > 200) return null;
```

Change to:
```dart
if (v > 500) return null;
```

Run: `flutter test test/trade_report_aggregate_test.dart && flutter test test/trade_report_totals_reconciliation_test.dart`

Update SOLUTION_TASKS.md: T-015 ✅

---

## PHASE 2 — PERFORMANCE IMPROVEMENTS

Run after Phase 1 passes all tests.

---

### TASK 2-A: Add `select` to purchaseTotalsProvider

**File:** `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`

Find `purchaseTotalsProvider`. Currently:
```dart
final purchaseTotalsProvider = Provider<TradeCalcTotals>((ref) {
  return computePurchaseTotals(ref.watch(purchaseDraftProvider));
});
```

Replace with:
```dart
// A record capturing only the fields that affect totals calculation.
// Changing supplier name, invoice number, or date does NOT rebuild totals.
typedef _TotalsKey = ({
  List<PurchaseLineDraft> lines,
  double? headerDiscountPercent,
  String commissionMode,
  double? commissionPercent,
  double? commissionMoney,
  double? freightAmount,
  String freightType,
  double? billtyRate,
  double? deliveredRate,
});

final purchaseTotalsProvider = Provider<TradeCalcTotals>((ref) {
  final key = ref.watch(purchaseDraftProvider.select((d) => (
    lines: d.lines,
    headerDiscountPercent: d.headerDiscountPercent,
    commissionMode: d.commissionMode,
    commissionPercent: d.commissionPercent,
    commissionMoney: d.commissionMoney,
    freightAmount: d.freightAmount,
    freightType: d.freightType,
    billtyRate: d.billtyRate,
    deliveredRate: d.deliveredRate,
  ) as _TotalsKey));
  // Rebuild a minimal draft to feed into existing computePurchaseTotals:
  final d = ref.read(purchaseDraftProvider);
  return computePurchaseTotals(d);
});
```

Note: `record` equality in Dart requires all fields to support `==`. `List<PurchaseLineDraft>` uses reference equality — add `@override bool operator ==(Object other)` to `PurchaseLineDraft` if tests fail, or use a hash of the list.

Run: `flutter analyze`

Update SOLUTION_TASKS.md: T-012 ✅

---

### TASK 2-B: Fix Dashboard Timer Double-Fire

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Find the `_poll = Timer.periodic(...)` handler. Update it to skip if `_resumeRefreshDebounce` is active:

```dart
_poll = Timer.periodic(const Duration(minutes: 10), (_) {
  if (!mounted) return;
  // Skip if app-resume refresh is already pending to avoid double invalidation.
  if (_resumeRefreshDebounce?.isActive == true) return;
  invalidateTradePurchaseCaches(ref);
});
```

Update SOLUTION_TASKS.md: T-016 ✅

---

## PHASE 3 — UX POLISH

Run after Phase 2.

---

### TASK 3-A: Wizard Exit — Skip Discard Dialog for Empty Form

**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

Find `_handleWizardExitFromRoot()` method. At the very beginning of the method, before any dialog:

```dart
Future<void> _handleWizardExitFromRoot() async {
  // NEW: skip dialog entirely if form is untouched
  if (!_formDirty) {
    if (mounted) context.pop();
    return;
  }
  // ... existing dialog logic below ...
}
```

Update SOLUTION_TASKS.md: T-018 ✅

---

### TASK 3-B: Fix Trade Ledger Long Name Overflow

**File:** `flutter_app/lib/features/contacts/presentation/trade_ledger_page.dart`

Search for `Text(` calls inside table row builders (look for `supplierName`, `itemName`, `brokerName`). For each name/text column, add `overflow` and `maxLines`:

```dart
Text(
  supplierName,
  overflow: TextOverflow.ellipsis,
  maxLines: 1,
  style: ...,
)
```

For numeric columns (amount, qty, rate): ensure there is NO `overflow` or `maxLines` restriction.

Update SOLUTION_TASKS.md: T-020 ✅

---

### TASK 3-C: Remove Fake Scan Stage Timer

**File:** `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`

1. Find `_stageTimer` declaration and all usages
2. Cancel and remove the fake progression timer calls (keep `_pollTimer` for real server stage polling)
3. Find where stage display strings are defined. Change `_ScanStage.extractingText` label from `'Extracting text…'` to `'Reading bill…'`

Update SOLUTION_TASKS.md: T-021 ✅

---

### TASK 3-D: Fix `BagDefaultUnitHint` Widget

**File:** `flutter_app/lib/shared/widgets/bag_default_unit_hint.dart`

1. Find the widget build method
2. Add a named parameter: `final bool kgAlreadySet;`
3. Add constructor parameter: `required this.kgAlreadySet`
4. Wrap the hint widget: `if (kgAlreadySet) return const SizedBox.shrink();`

Find all usages of `BagDefaultUnitHint(` in the purchase item entry sheet and pass `kgAlreadySet: _kgPerUnit != null && _kgPerUnit! > 0`.

Update SOLUTION_TASKS.md: T-022 ✅

---

## FINAL STEPS

After all phases complete:

```bash
cd flutter_app

# 1. Run all tests
flutter test

# 2. Analyze
flutter analyze

# 3. Check for any remaining issues
flutter test --reporter expanded 2>&1 | tail -30
```

Fix any test failures before committing.

Then commit:
```bash
git add .
git commit -m "fix: HSN bag block, image isolate, piece unit, AI scan rate, sack classifier, UX polish"
```

Update `CURRENT_CONTEXT.md`:
- Date: today
- Active task: complete
- Latest touchpoints: list all changed files

Update `SOLUTION_TASKS.md`: mark overall progress table with completion counts.

---

## WHAT NOT TO DO

- Do NOT add `print()` or `debugPrint()` anywhere
- Do NOT change the overall wizard step structure
- Do NOT refactor the calc engine — it is correct
- Do NOT change `StrictDecimal` — it is correct  
- Do NOT add new packages to `pubspec.yaml` (except `uuid` for T-006 if needed)
- Do NOT modify any `_test.dart` files
- Do NOT touch the auth flow or GoRouter routes
- Do NOT change PDF font files or assets

---

## CONTEXT FILES TO READ FIRST

Before making any change, read these files for context:
- `CURRENT_CONTEXT.md` — latest state
- `BUGS.md` — known issues  
- `ARCHITECTURE_STATE.md` — architecture decisions
- `MATCH_ENGINE.md` — OCR matching rules

These files explain WHY the code is shaped as it is. Do not fight these decisions.
