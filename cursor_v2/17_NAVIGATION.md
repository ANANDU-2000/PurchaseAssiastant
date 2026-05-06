# 17 — NAVIGATION & BACK BUTTON BUGS

> `@.cursor/00_STATUS.md` first

---

## STATUS


| Task                                                    | Status                                          |
| ------------------------------------------------------- | ----------------------------------------------- |
| Back button broken on catalog/category page             | ✅ Done (dialogs/sheets: `context.pop` app-wide) |
| Wizard flow Party → Terms → Items → Review              | ✅ Matches `purchase_entry_wizard_v2.dart`       |
| Purchase history: hide bottom nav + FAB (full viewport) | ✅ Done (`ShellScreen` `loc == '/purchase'`)     |
| Purchase history: Home from AppBar                      | ✅ Done (`purchase_home_page` leading)           |
| Item entry unit field — dropdown                        | ✅ Done (`purchase_item_entry_sheet`)            |
| Terms "Continue" → Review                               | ✅ Step order verified in code                   |


---

## FILES TO EDIT

```
flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart
flutter_app/lib/features/purchase/presentation/wizard/purchase_terms_only_step.dart
flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart
flutter_app/lib/core/router/app_router.dart
```

---

## BUG C6: Back button broken on some pages

**Symptom:** Tapping ← back on catalog page / category page does nothing or causes blank screen.

**Root cause:** GoRouter `pop()` called but the route was pushed with `push()` onto a shell route
that doesn't support deep pop. On iOS, the system back gesture may conflict with GoRouter.

**Fix — ensure all detail pages use `context.pop()` not `Navigator.pop()`:**

```dart
// Check every page AppBar leading:
// WRONG:
leading: IconButton(onPressed: () => Navigator.of(context).pop(), ...)
// RIGHT:
leading: IconButton(onPressed: () => context.pop(), ...)
```

**Also ensure all routes that need back support are defined as `GoRoute` not `ShellRoute` sub-routes.**

**In `app_router.dart`**, check that catalog, category, broker detail, supplier detail pages
are defined as top-level `GoRoute` entries (not nested inside a `ShellRoute` that eats back events).

---

## BUG P4: After Terms "Continue →" shows item list instead of Review

**Status:** ✅ Resolved — step indices in code must stay as below.

**File:** `purchase_entry_wizard_v2.dart` — `_wizBody` + `_wizNext`.

**Verified flow:**

```
_wizStep 0 → Party (`PurchasePartyStep`)
_wizStep 1 → Terms (`PurchaseTermsOnlyStep`)  — Continue → `_wizStep = 2`
_wizStep 2 → Items (`PurchaseFastItemsStep`) — Continue → `_wizStep = 3`
_wizStep 3 → Review (`PurchaseReviewTallyStep`)
```

`_wizNext`: from step **1**, terms validation then `setState(() => _wizStep = 2)`; from step **2**, line gates then `setState(() => _wizStep = 3)`. Review is only step **3**.

---

## FIX: Item unit field — show dropdown picker

**Status:** ✅ Done (`purchase_item_entry_sheet.dart` — `DropdownButtonFormField` + `initialValue` / `KeyedSubtree` per Flutter 3.33+).

**Reference (pattern):**

**File:** `purchase_item_entry_sheet.dart`

**Replace with `DropdownButtonFormField`:**

```dart
DropdownButtonFormField<String>(
  value: _unitCtrl.text.isEmpty ? 'kg' : _unitCtrl.text,
  decoration: InputDecoration(
    labelText: 'Unit *',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  ),
  items: const [
    DropdownMenuItem(value: 'kg', child: Text('kg')),
    DropdownMenuItem(value: 'bag', child: Text('bag')),
    DropdownMenuItem(value: 'box', child: Text('box')),
    DropdownMenuItem(value: 'tin', child: Text('tin')),
    DropdownMenuItem(value: 'piece', child: Text('piece')),
  ],
  onChanged: (v) {
    if (v == null) return;
    setState(() {
      _unitCtrl.text = v;
      // Auto-show kg-per-unit field when bag/box selected
      _showKgPerUnit = v == 'bag' || v == 'box';
    });
    _onUnitChanged(v);
  },
),
```

**Auto-select unit when item picked:**
When a catalog item is selected, set unit from `catalogItem.default_unit`:

```dart
void _onItemSelected(String id, String name) {
  final item = _findCatalogItem(id);
  if (item != null) {
    final defaultUnit = item['default_unit']?.toString() ?? 'kg';
    setState(() {
      _unitCtrl.text = defaultUnit;
      _showKgPerUnit = defaultUnit == 'bag' || defaultUnit == 'box';
      if (item['default_kg_per_bag'] != null) {
        _kgPerBagCtrl.text = item['default_kg_per_bag'].toString();
      }
    });
  }
}
```

---

## FIX: Purchase history — full viewport (hide nav)

**Status:** ✅ Done — `ShellScreen` hides bottom bar + FAB when `loc == '/purchase'`; `purchase_home_page` AppBar leading goes Home.

**File:** `purchase_home_page.dart` (History / purchase list)

The History tab should hide the shell's AppBar to maximise vertical space.

**Find the shell configuration.** If using a `StatefulShellRoute`:

```dart
// In the History tab page scaffold:
@override
Widget build(BuildContext context) {
  return Scaffold(
    // No AppBar on history page — shell provides back if needed
    // OR use a minimal AppBar:
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(0), // hidden
      child: const SizedBox.shrink(),
    ),
    body: _buildHistoryContent(),
  );
}
```

**OR** give the History page its own compact AppBar with search:

```dart
appBar: AppBar(
  toolbarHeight: 48,
  title: TextField(
    controller: _searchCtrl,
    decoration: InputDecoration(
      hintText: 'Search supplier, PUR ID, item...',
      prefixIcon: const Icon(Icons.search, size: 18),
      border: InputBorder.none,
    ),
  ),
  actions: [
    IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilter),
  ],
),
```

---

## VALIDATION

- Tapping ← back on any page returns to previous (no blank screen)
- Terms "Continue →" goes to **Items** (step 2); Items "Continue →" goes to **Review** (step 3)
- Review "Save Purchase" saves and redirects home
- Unit field shows dropdown: kg / bag / box / tin / piece
- Select "SUGAR 50 KG" → unit auto-sets to "bag"
- History tab uses full screen (minimal nav chrome)

