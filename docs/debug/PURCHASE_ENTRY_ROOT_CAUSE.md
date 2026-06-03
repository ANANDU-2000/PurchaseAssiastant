# Purchase Entry — Root Cause Analysis

**Date:** 2026-06-02

## Symptoms reported

- Save button appears blocked or save fails for new items (e.g. "30kg bag")
- New catalog items not available in purchase dropdown immediately
- Validation errors without clear path to fix

## Root causes

### 1. Quick-add catalog gated on stale empty catalog (fixed)

**Location:** `purchase_entry_wizard_v2.dart` — `navigateCatalogQuickAddItem`

**Bug:** Callback was `null` when `session == null || catalog.isEmpty`. Wizard already reloads catalog into `catalogForSheet` before opening the item sheet, but the **initial** `catalog` watch could still be empty while async load completed. Users could not open "New catalog item…" during that window.

**Fix:** Only gate on `session == null`. Quick-add remains available once session exists; return from `/catalog/quick-add` invalidates `catalogItemsListProvider`.

### 2. Save blocked without `catalog_item_id` (by design, UX gap)

**Location:** `purchase_draft.dart` — `purchaseLineSaveBlockReason`

**Behavior:** Free-typed item names cannot save until user picks a catalog row or completes quick-add. Message: *"Pick the item from the list (free-typed items cannot be saved)."*

**Mitigation already in UI:** Item entry sheet requires catalog pick; quick-add path sets `catalog_item_id` on return.

### 3. Bag lines require `kg_per_unit` (expected validation)

**Location:** `purchase_item_entry_sheet.dart` + `purchaseLineSaveBlockReason`

**Behavior:** Unit `bag` needs kg per bag > 0. Auto-seed from name ("30 KG") and catalog `default_kg_per_bag`.

**Not a bug** if user skips kg field and name has no weight hint — inline `_errKgPerBag` and wizard `purchaseStepBlockReasonsProvider` surface the block.

## Verification

1. Open purchase wizard with slow catalog load → "New catalog item…" visible when logged in.
2. Quick-add item → return → select item → enter qty, rate, kg/bag → Save line → wizard Save enabled when supplier + valid lines.
3. Backend: existing `test_trade_purchases` suite passes (create/update payloads unchanged).

## Files changed (this recovery)

- `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`
