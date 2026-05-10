# PURCHASE ASSISTANT — SOLUTION TASK LIST
> Priority-ordered. Each task has: file, exact change, acceptance test.
> Cursor agent works top-to-bottom. Update checkbox when done.
> Last sync: 2026-05-10

**Completed this session (plan scope):** T-001–T-005, T-007, T-009, T-011, T-015, T-012, T-016, T-018 (already in code), T-020–T-022; backend scan `rate_context` wired (`ItemRow`, pipeline infer + confirm path, prompts, v3 fallback).

---

## ✅ PHASE 0 — CRITICAL BLOCKERS (Fix These First, ~3 hrs)

### T-001 · Fix HSN Blocking All Bag Line Saves ⚡ HIGHEST PRIORITY ✅ 2026-05-10
**File:** `flutter_app/lib/features/purchase/domain/purchase_draft.dart`
**Line:** ~502–507
- [x] ✅ 2026-05-10 Change: `if (tax > 0 || unitIsBag)` → `if (tax > 0)`
- [x] ✅ 2026-05-10 Remove the `unitIsBag` condition from HSN gate
- [x] ✅ 2026-05-10 Keep: HSN required only when `taxPercent > 0`
- [x] ✅ 2026-05-10 Update error message to: `'HSN code is required for taxed items (tax% > 0).'`
- [x] ✅ 2026-05-10 Run test: `flutter test test/purchase_draft_calc_test.dart`
- [ ] Manual test: create bag line with no HSN, zero tax → should SAVE
- [ ] Manual test: create bag line with tax 5% + no HSN → should BLOCK with clear message

### T-002 · Move Image Decode to Isolate ⚡ UI FREEZE FIX ✅ 2026-05-10
**File:** `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`
**Line:** ~66–72
- [x] ✅ 2026-05-10 Add `import 'package:flutter/foundation.dart' show compute;`
- [x] ✅ 2026-05-10 Create top-level static function `_compressIsolate(List<int> raw)` (NOT a class method — compute requires top-level or static)
- [x] ✅ 2026-05-10 Move all `img.decodeImage` + `img.copyResize` + `img.encodeJpg` code into `_compressIsolate`
- [x] ✅ 2026-05-10 Change `_compressForUpload` to: `return compute(_compressIsolate, raw);`
- [ ] Test: tap gallery pick on large photo → UI stays responsive during compression

### T-003 · Add `piece` Unit to Save Validation ✅ 2026-05-10
**File:** `flutter_app/lib/features/purchase/domain/purchase_draft.dart`
**Line:** ~460–520
- [x] ✅ 2026-05-10 Add: `bool _isPieceUnit(String unit) { final x = unit.trim().toLowerCase(); return x == 'piece' || x == 'pcs' || x == 'pieces'; }`
- [x] ✅ 2026-05-10 In `purchaseLineSaveBlockReason`: add `final unitIsPiece = _isPieceUnit(l.unit);`
- [x] ✅ 2026-05-10 Add `unitIsPiece` to the whole-number qty check: `if (unitIsBag || unitIsBox || unitIsTin || unitIsPiece)`
- [x] ✅ 2026-05-10 Add explicit piece path: `if (unitIsPiece) { if (l.landingCost <= 0) return 'Purchase rate must be > 0.'; return null; }`
- [x] ✅ 2026-05-10 Run: `flutter test test/purchase_draft_calc_test.dart`

### T-004 · Fix AI Scan Landing Cost Rate Heuristic ✅ 2026-05-10
**File:** `flutter_app/lib/features/purchase/mapping/ai_scan_purchase_draft_map.dart`
**Line:** ~140–155
- [x] ✅ 2026-05-10 Remove `final looksPerBag = pr >= 500;` heuristic entirely
- [x] ✅ 2026-05-10 Replace with: check `it['rate_context']?.toString() ?? 'per_bag'` from scan JSON
- [x] ✅ 2026-05-10 If `rate_context == 'per_kg'`: `landingCostPerKg = pr; landingCost = pr * wpu;`
- [x] ✅ 2026-05-10 Else (default `per_bag`): `landingCost = pr; landingCostPerKg = (wpu > 0) ? pr / wpu : null;`
- [x] ✅ 2026-05-10 Backend: `rate_context` on `ItemRow`, pipeline infer + confirm + prompts (`scanner_v2/types.py`, `pipeline.py`, `prompt.py`, `purchase_scan_ai.py`, `scanner_v3/pipeline.py` fallback)
- [x] ✅ 2026-05-10 Run: `flutter test test/ai_scan_purchase_draft_map_test.dart`

### T-005 · Fix Category Seed `default_unit` for Wholesale Items ✅ 2026-05-10
**File:** `data/files/categories_seed.json` + `backend/scripts/data/categories_seed.json`
- [x] ✅ 2026-05-10 `SUGAR` → `"default_unit": "bag"`
- [ ] `SUGAR` optional `"default_kg_per_bag": 50` (field not present in current seed schema)
- [ ] `SALT` optional `"default_kg_per_bag": 25`
- [x] ✅ 2026-05-10 `SALT` → `"default_unit": "bag"`
- [x] ✅ 2026-05-10 `EDIBLE OIL` → `"default_unit": "tin"`
- [x] ✅ 2026-05-10 `DALDA` → `"default_unit": "tin"`
- [x] ✅ 2026-05-10 `OIL` → `"default_unit": "tin"`
- [x] ✅ 2026-05-10 `KAAYAM` (asafoetida) → `"default_unit": "kg"`
- [ ] Re-seed DB if seed is used to populate catalog: `python scripts/seed_categories.py` or equivalent
- [ ] Verify: open app → catalog → SUGAR shows default unit as BAG

---

## 🔴 PHASE 1 — HIGH PRIORITY BUG FIXES (~4 hrs)

### T-006 · Add Idempotency Key to Purchase Save
**Files:** 
- `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`
- `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`
- [ ] Add `import 'package:uuid/uuid.dart';` (add `uuid: ^4.4.0` to pubspec if missing)
- [ ] In `_PurchaseEntryWizardV2State`: add `String _idempotencyKey = const Uuid().v4();`
- [ ] In `buildTradePurchaseBody()`: add `body['idempotency_key'] = _idempotencyKey;`
- [ ] After successful save in `_doSave()`: `_idempotencyKey = const Uuid().v4();`
- [ ] Ensure `_isSaving` guard is checked before EVERY save trigger (check FAB, keyboard submit, step advance)
- [ ] Backend task note: add `UNIQUE(business_id, idempotency_key)` index to `trade_purchases` table; on conflict return existing record

### T-007 · Fix `_isBagOrSackUnit` Missing SACK ✅ 2026-05-10
**File:** `flutter_app/lib/core/utils/unit_classifier.dart` line ~72
- [x] ✅ 2026-05-10 Change: `return effU == 'BAG';` → `return effU == 'BAG' || effU == 'SACK';`
- [x] ✅ 2026-05-10 Run: `flutter test test/bag_infer_from_name_test.dart`
- [x] ✅ 2026-05-10 Run: `flutter test test/package_rules_test.dart`

### T-008 · Fix FocusNode setState — Use ValueNotifier
**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`
- [ ] Add: `final _supplierFocusValue = ValueNotifier<bool>(false);`
- [ ] Add: `final _brokerFocusValue = ValueNotifier<bool>(false);`
- [ ] Change focus listeners to: `_partySupplierFocus.addListener(() { _supplierFocusValue.value = _partySupplierFocus.hasFocus; });`
- [ ] Remove `_partyFieldFocusNotify` method and its `setState(() {})` call
- [ ] Wrap the suggestion panels with `ValueListenableBuilder<bool>` on `_supplierFocusValue` / `_brokerFocusValue`
- [ ] Test: type in supplier field → confirm no full rebuild (use Flutter DevTools "Highlight repaints")

### T-009 · Add TTL to Contacts Hub KeepAlive Providers ✅ 2026-05-10
**File:** `flutter_app/lib/core/providers/contacts_hub_provider.dart`
- [x] ✅ 2026-05-10 After `ref.keepAlive();` in each of the 4 providers, add: `final link = ref.keepAlive(); Timer(const Duration(minutes: 30), link.close);`
- [x] ✅ 2026-05-10 Note: must remove bare `ref.keepAlive()` and use `link` variable instead
- [ ] Test: open app, navigate 4 screens, wait 30 min (or reduce to 1 min in debug) → providers dispose

### T-010 · Remove Legacy `dashboardProvider` — Migrate to `homeDashboardDataProvider`
**Files:** `lib/core/providers/dashboard_provider.dart` + all references
- [ ] Run: `grep -rn "dashboardProvider" flutter_app/lib/ --include="*.dart"` — list all usages
- [ ] For each usage: replace `ref.watch(dashboardProvider)` with `ref.watch(homeDashboardDataProvider)`
- [ ] Update data access: `DashboardData.totalPurchase` → `HomeDashboardDashState.snapshot.totalPurchase` (verify field names)
- [ ] After migration: delete `lib/core/providers/dashboard_provider.dart`
- [ ] Run: `flutter analyze` → confirm no dangling references

### T-011 · Fix Draft Hive Flush on App Background ✅ 2026-05-10
**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`
- [x] ✅ 2026-05-10 Add `with WidgetsBindingObserver` to wizard state (if not already)
- [x] ✅ 2026-05-10 In `initState`: `WidgetsBinding.instance.addObserver(this);`
- [x] ✅ 2026-05-10 In `dispose`: `WidgetsBinding.instance.removeObserver(this);`
- [x] ✅ 2026-05-10 On `AppLifecycleState.paused` when `_formDirty`: cancel draft debounce + `_flushDraftToPrefs()` (silent; same persistence path as debounced draft — prefs + `OfflineStore.putPurchaseWizardDraft`)
- [ ] Test: enter partial purchase, background app via home button, kill from task switcher, reopen → draft recovered

---

## 🟡 PHASE 2 — PERFORMANCE (~3 hrs)

### T-012 · Add `select` to `purchaseTotalsProvider` ✅ 2026-05-10
**File:** `flutter_app/lib/features/purchase/state/purchase_draft_provider.dart`
- [x] ✅ 2026-05-10 `purchaseTotalsProvider` / `purchaseStrictBreakdownProvider`: `ref.watch(purchaseDraftProvider.select((d) => (lines: d.lines, headerDiscountPercent: …)))` then `ref.read(purchaseDraftProvider)` for compute (no `commissionBasisKey` on draft — omitted)
- [ ] Test: type supplier name → DevTools confirms no totals rebuild

### T-013 · Catalog Provider Stale-While-Revalidate (Skip Refetch Within 5 min)
**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`
- [ ] In `_bootstrap()`: before `ref.invalidate(catalogItemsListProvider)`, check last-fetch timestamp
- [ ] Add to `catalogItemsListProvider` body: save fetch timestamp to a `StateProvider<DateTime?>`
- [ ] In `_bootstrap()`: `if (lastFetch != null && DateTime.now().difference(lastFetch) < 5.min) return;`
- [ ] Test: open wizard → close → reopen within 3 min → no catalog refetch (check Dio request log)

### T-014 · Move PDF Generation to Isolate
**Files:** `lib/core/services/purchase_pdf.dart`, `purchase_invoice_pdf_layout.dart`, `reports_pdf.dart`
- [ ] Identify main PDF build function in each file
- [ ] Move the `pdf.Document()` build logic to a top-level function
- [ ] Wrap with `compute()`: `final bytes = await compute(_buildPurchasePdf, inputData);`
- [ ] Create `PdfBuildInput` value class to pass data (no BuildContext, no Riverpod)
- [ ] Test: generate PDF with 20-line purchase → no jank on main thread

### T-015 · Fix Report Aggregate KG Cap — Raise 200 → 500 ✅ 2026-05-10
**File:** `flutter_app/lib/core/reporting/trade_report_aggregate.dart` line ~55
- [x] ✅ 2026-05-10 Change: `if (v > 200) return null;` → `if (v > 500) return null;`
- [x] ✅ 2026-05-10 Run: `flutter test test/trade_report_aggregate_test.dart`

### T-016 · Dashboard Timer Double-Fire Guard ✅ 2026-05-10
**File:** `flutter_app/lib/features/home/presentation/home_page.dart`
- [x] ✅ 2026-05-10 In `_poll` Timer.periodic handler: skip when `_resumeRefreshDebounce?.isActive == true`
- [ ] Or: replace Timer.periodic with a single-event approach that reschedules after each successful completion

---

## 🟢 PHASE 3 — UX POLISH (~2 hrs)

### T-017 · Fix Spend Ring Edge Case (Zero Total)
**File:** `flutter_app/lib/features/home/presentation/home_spend_ring_diameter.dart`
- [ ] Find ring diameter calculation
- [ ] Add: `if (total <= 0 || data.isEmpty) return minDiameter;`
- [ ] Test: open dashboard with no purchases → ring shows correctly (empty state, not full ring)

### T-018 · Wizard Exit Guard — Skip Discard Dialog for Empty Form ✅ 2026-05-10 (verified)
**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`
- [x] ✅ 2026-05-10 Already implemented: `_handleWizardExitFromRoot()` pops when `!_formDirty` (non-edit mode)
- [ ] Test: open wizard → immediately press back → no dialog shown

### T-019 · Item Entry Sheet Scroll-to-Field Fix
**File:** `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart`
- [ ] Find `ensureVisible` or scroll-to-key call when `_kgPerBagKey` appears
- [ ] Change to use `Scrollable.ensureVisible(_kgPerBagKey.currentContext!, duration: Duration(milliseconds: 200))` with the correct `ScrollableState` ancestor
- [ ] Test on iPhone: select bag unit → kg per bag field scrolls into view cleanly

### T-020 · Trade Ledger Table — Fix Long Name Overflow ✅ 2026-05-10
**File:** `flutter_app/lib/features/contacts/presentation/trade_ledger_page.dart`
- [x] ✅ 2026-05-10 Ellipsis on entity title, supplier name, item lines, invoice id, phone; address `maxLines: 2`
- [x] ✅ 2026-05-10 Total amount column: removed `maxLines` / `overflow` so full ₹ shows
- [ ] Test on 375px screen with 25-char supplier name

### T-021 · Remove Fake Stage Timer From Scan Page ✅ 2026-05-10
**File:** `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`
- [x] ✅ 2026-05-10 Remove `_stageTimer` (was never scheduled; dead code)
- [x] ✅ 2026-05-10 Stage from server poll unchanged
- [x] ✅ 2026-05-10 `_ScanStage.extractingText` label → `'Reading bill…'`
- [ ] Test: scan a bill → progress accurately reflects server stages

### T-022 · Suppress `BagDefaultUnitHint` When KG Already Resolved ✅ 2026-05-10
**File:** `flutter_app/lib/shared/widgets/bag_default_unit_hint.dart` + catalog editors
- [x] ✅ 2026-05-10 `required bool kgAlreadySet`; `if (kgAlreadySet) return SizedBox.shrink();`
- [x] ✅ 2026-05-10 Wired in `catalog_item_detail_page.dart` (edit dialog) and `catalog_add_item_page.dart` via `parseOptionalKgPerBag` — purchase item sheet had no usages

---

## 🔵 PHASE 4 — SEED DATA & DATABASE (~1 hr)

### T-023 · Update Category Seed + Re-seed DB
*(See T-005 for specific unit changes)*
- [x] ✅ 2026-05-10 Update `categories_seed.json` (via `data/files/` + `backend/scripts/data/`)
- [ ] Update `products_by_category_seed.json` — verify all BAG items have HSN code
- [ ] Run seed migration script
- [ ] Verify in app: SUGAR default unit = BAG, auto-kg hint = 50 kg

### T-024 · Add Backend DB Index for Idempotency Key
*(Companion to T-006)*
**Backend:** `backend/app/`
- [ ] Migration: `ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS idempotency_key UUID;`
- [ ] Migration: `CREATE UNIQUE INDEX IF NOT EXISTS idx_tp_idempotency ON trade_purchases(business_id, idempotency_key) WHERE idempotency_key IS NOT NULL;`
- [ ] In purchase create endpoint: check for existing record with same `idempotency_key` → return existing if found (HTTP 200, not 409)
- [x] ✅ 2026-05-10 Add `rate_context: "per_bag" | "per_kg"` field to scanner item output (for T-004) — see `ItemRow.rate_context`, `scanner_v2/pipeline.py`, prompts

---

## ✅ DEFINITION OF DONE PER TASK

A task is DONE when:
1. All checkboxes checked
2. Relevant test file passes (`flutter test test/<relevant_test>.dart`)
3. `flutter analyze` shows zero new warnings
4. Feature tested manually on iOS simulator (iPhone 16 Pro)
5. This file updated with ✅ and date

---

## 🧪 REGRESSION TEST SUITE CHECKLIST

Run after Phase 0 + Phase 1 complete:

**Purchase Creation:**
- [ ] Create bag line (RICE 50 KG) → no HSN → save succeeds
- [ ] Create bag line with tax 5% + no HSN → blocked with clear message
- [ ] Create kg line → save succeeds
- [ ] Create box line → save succeeds
- [ ] Create tin line → save succeeds
- [ ] Create piece/PCS line → save succeeds
- [ ] Create purchase → navigate back and forward rapidly (no duplicate)
- [ ] Create purchase → kill app mid-save → reopen → no phantom purchase in list

**AI Scan:**
- [ ] Scan bag bill with rate ₹1,200/bag → parsed as per-bag rate correctly
- [ ] Scan bag bill with rate ₹24/kg → parsed as per-kg rate correctly
- [ ] Scan on large photo → UI stays smooth (no freeze)
- [ ] Scan result → proceed to wizard → all pre-filled fields editable

**Unit Engine:**
- [ ] SUGAR catalog item → default unit = BAG in item picker
- [ ] "RICE 50 KG" item name → unit hint = bag, kg = 50 shown
- [ ] SACK unit from old purchase → classified as weightBag correctly
- [ ] EDIBLE OIL → default unit = TIN

**Dashboard:**
- [ ] Pull to refresh → data updates
- [ ] Background app 5 min → resume → data refreshes once (not twice)
- [ ] Period chips (Today/Week/Month/Year) → chart updates

**Reports:**
- [ ] 200 KG bag item → appears in report kg totals (not dropped)
- [ ] Deleted purchase → NOT in report totals
