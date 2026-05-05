# SPEC 02 — ITEM ENTRY (Add Item Sheet)
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| Item search suggestion tap fix (InkWell) | ✅ Done |
| ML auto-fill purchase rate from last trade | ✅ Done |
| ML auto-fill selling rate from last trade | ✅ Done |
| Auto-detect unit from item name (50 KG → bag) | ✅ Done |
| `kgPerBag` resolved from catalog `default_kg_per_bag` | ✅ Done |
| Dynamic qty field label ("No. of bags" for bag items) | ✅ Done |
| Live calc preview: bags × kg/bag = total kg | ✅ Done |
| `formatLineQtyWeight` helper used in preview | ✅ Done |
| Keyboard overlap in item entry bottom sheet | ✅ Done |
| Advanced section: delivered/billty/freight per item | ✅ Done |
| "Classified: weight bag" hint visible | ✅ Done |
| ₹/kg vs ₹/bag toggle for bag items | ✅ Done |

---

## FILES TO EDIT
```
flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart
flutter_app/lib/core/utils/line_display.dart   ← CREATE THIS NEW FILE
flutter_app/lib/features/purchase/presentation/widgets/add_item_entry_page.dart
```

---

## WHAT TO DO

### ❌ TASK 02-A: Dynamic qty label ("No. of bags" for bag items)

**File:** `purchase_item_entry_sheet.dart`

**Find the Qty `TextFormField`.** Its `labelText` currently says `'Qty *'` (or similar static string).

**Add this getter:**
```dart
String get _qtyFieldLabel {
  final u = _unitCtrl.text.trim().toLowerCase();
  if (u == 'bag' || u == 'sack') return 'Number of bags *';
  if (u == 'box') return 'Number of boxes *';
  if (u == 'tin') return 'Number of tins *';
  return 'Qty (kg) *';
}
```

**Replace** `labelText: 'Qty *'` with `labelText: _qtyFieldLabel`.

This label must update when the unit changes. Since unit changes call `setState`, the getter will re-evaluate automatically.

---

### ❌ TASK 02-B: Live calc preview — bags × kg = total

**File:** `purchase_item_entry_sheet.dart`

**Find `_buildCalcPreview()` or the teal calculation box** (the Container with green background showing qty × rate).

**Replace its content with:**
```dart
Widget _buildCalcPreview() {
  final qty = _parseD(_qtyCtrl.text) ?? 0;
  final kpu = _kgPer();           // kg per bag/box/tin — already computed
  final u = _unitCtrl.text.trim().toLowerCase();
  final isBagUnit = u == 'bag' || u == 'sack';
  final isBoxUnit = u == 'box';
  final isTinUnit = u == 'tin';
  final hasKpu = kpu != null && kpu > 0;

  // Total weight
  final totalKg = hasKpu ? qty * kpu! : qty;

  // Line 1: qty breakdown
  String line1;
  if (isBagUnit && hasKpu) {
    final qtyInt = qty == qty.roundToDouble() ? qty.round().toString() : qty.toStringAsFixed(1);
    final kpuStr = kpu! == kpu.roundToDouble() ? kpu.round().toString() : kpu.toStringAsFixed(1);
    final kgStr = totalKg >= 1000
        ? '${(totalKg / 1000).toStringAsFixed(2)} t'
        : '${totalKg.toStringAsFixed(0)} kg';
    line1 = '$qtyInt bags × $kpuStr kg/bag = $kgStr';
  } else if (isBoxUnit && hasKpu) {
    line1 = '${qty.toStringAsFixed(0)} boxes × ${kpu!.toStringAsFixed(1)} kg/box = ${totalKg.toStringAsFixed(0)} kg';
  } else {
    line1 = '${qty.toStringAsFixed(0)} ${u.isEmpty ? 'kg' : u}  •  ${totalKg.toStringAsFixed(0)} kg';
  }

  // Line 2: cost
  final rate = _parseD(_landingCtrl.text) ?? 0;
  final totalCost = _weightPricing ? totalKg * rate : qty * rate;

  // Line 3: profit
  final sellRate = _parseD(_sellingCtrl.text) ?? 0;
  final totalSell = _weightPricing ? totalKg * sellRate : qty * sellRate;
  final profit = totalSell - totalCost;

  final rateLabel = _weightPricing ? '₹${rate.toStringAsFixed(2)}/kg' : '₹${rate.toStringAsFixed(2)}/${u.isEmpty ? 'unit' : u}';

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F5E9),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFB2DFDB)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line1,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1B5E20)),
        ),
        const SizedBox(height: 3),
        Text(
          '${totalKg.toStringAsFixed(0)} kg × $rateLabel → ₹${totalCost.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
        const SizedBox(height: 3),
        Text(
          'Profit ₹${profit.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: profit >= 0 ? const Color(0xFF1B6B5A) : Colors.red.shade700,
          ),
        ),
      ],
    ),
  );
}
```

---

### ❌ TASK 02-C: Create `line_display.dart` utility

**Create new file:** `lib/core/utils/line_display.dart`

```dart
/// Shared display helpers for purchase line quantities and rates.
/// Used in: purchase_detail_page, trade_purchase_ledger_cards,
///          supplier_detail_page, supplier_ledger_page, item_history_page
library line_display;

/// Returns a human-readable qty + weight string for a purchase line.
///
/// Examples:
///   bag, qty=100, kgPerUnit=50  → "100 bags • 5,000 kg"
///   kg,  qty=5000               → "5,000 kg"
///   box, qty=50, kgPerUnit=20   → "50 boxes • 1,000 kg"
///   tin, qty=200                → "200 tins"
String formatLineQtyWeight({
  required double qty,
  required String unit,
  double? kgPerUnit,
}) {
  final u = unit.trim().toLowerCase();
  final isBag = u == 'bag' || u == 'sack';
  final isBox = u == 'box';
  final isTin = u == 'tin';
  final hasKpu = kgPerUnit != null && kgPerUnit > 0;

  final qtyStr = qty == qty.roundToDouble()
      ? _fmtNum(qty.round())
      : qty.toStringAsFixed(1);

  if ((isBag || isBox) && hasKpu) {
    final totalKg = qty * kgPerUnit!;
    final kgStr = _fmtKg(totalKg);
    final unitWord = isBag ? (qty == 1 ? 'bag' : 'bags') : (qty == 1 ? 'box' : 'boxes');
    return '$qtyStr $unitWord • $kgStr';
  }

  if (isTin) {
    final tinWord = qty == 1 ? 'tin' : 'tins';
    if (hasKpu) {
      return '$qtyStr $tinWord • ${_fmtKg(qty * kgPerUnit!)}';
    }
    return '$qtyStr $tinWord';
  }

  // kg or unknown
  return '${_fmtKg(qty)}';
}

/// Returns rate display for a line.
/// For bag items: shows ₹/kg (not ₹/bag).
String formatLineRate({
  required double rate,
  required String rateType, // 'purchase' or 'selling'
  required String unit,
  double? kgPerUnit,
}) {
  final u = unit.trim().toLowerCase();
  final isBag = u == 'bag' || u == 'sack';
  final hasKpu = kgPerUnit != null && kgPerUnit > 0;
  final prefix = rateType == 'purchase' ? 'P' : 'S';

  if (isBag && hasKpu) {
    // Rate stored as per-kg — display as per-kg
    return '$prefix ₹${rate.toStringAsFixed(1)}/kg';
  }
  return '$prefix ₹${rate.toStringAsFixed(1)}/${u.isEmpty ? 'unit' : u}';
}

String _fmtKg(double kg) {
  if (kg >= 100000) return '${(kg / 1000).toStringAsFixed(1)} t';
  if (kg >= 1000) {
    final s = kg.toStringAsFixed(0);
    // Insert comma: 5000 → 5,000
    return _addComma(s) + ' kg';
  }
  return '${kg.toStringAsFixed(0)} kg';
}

String _fmtNum(int n) {
  if (n >= 1000) return _addComma(n.toString());
  return n.toString();
}

String _addComma(String s) {
  // Simple Indian numbering: last 3, then 2s
  if (s.length <= 3) return s;
  final buf = StringBuffer();
  final chars = s.characters.toList();
  final len = chars.length;
  for (var i = 0; i < len; i++) {
    if (i > 0) {
      final remaining = len - i;
      if (remaining == 3 || (remaining < 3 && (len - 3 - i) % 2 == 0)) {
        buf.write(',');
      }
    }
    buf.write(chars[i]);
  }
  return buf.toString();
}
```

**After creating this file, import and use `formatLineQtyWeight` in:**
1. `purchase_detail_page.dart` — line item qty display
2. `trade_purchase_ledger_cards.dart` — history card weight
3. `supplier_detail_page.dart` — purchase history rows
4. `supplier_ledger_page.dart` — ledger row qty

---

### ❌ TASK 02-D: Fix keyboard overlap in item entry bottom sheet

**File:** `purchase_item_entry_sheet.dart` (or `add_item_entry_page.dart`)

The sheet is opened as `showModalBottomSheet`. Inside its build, the content must
pad itself for the keyboard.

**Find the root widget of the sheet build method. Wrap with:**
```dart
@override
Widget build(BuildContext context) {
  final kb = MediaQuery.viewInsetsOf(context).bottom;
  return Padding(
    padding: EdgeInsets.only(bottom: kb),
    child: // existing content
  );
}
```

**Also ensure the showModalBottomSheet call has:**
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,  // must be true
  useSafeArea: true,
  builder: (ctx) => const PurchaseItemEntrySheet(/* ... */),
);
```

---

## SPEC: Item Entry Form Layout (iPhone 16 Pro)

```
┌─────────────────────────────────────────────────────────┐
│ AppBar: "← Add item"                    [+ New item]   │
├─────────────────────────────────────────────────────────┤
│  [📦 Search catalog item...]                            │  h=52
│  ↓ inline suggestions (max 6, InkWell tiles)            │
│                                                         │
│  "Filled from last purchase · rate ₹26/kg · surag"     │  ← teal hint
│  "Classified: 50 kg bag"                               │  ← green chip
│                                                         │
│  [Number of bags *]     [Unit: bag(50kg) ▾]            │  h=52 each
│                                                         │
│  [✓ ₹/kg]  [₹/bag]    ← toggle for bag items only     │
│  [Purchase Rate (₹/kg)*]  [Selling Rate (₹/kg)]        │  h=52 each
│                                                         │
│  ┌──── LIVE PREVIEW ──────────────────────────────┐    │
│  │ 100 bags × 50 kg/bag = 5,000 kg               │    │
│  │ 5,000 kg × ₹26.00/kg → ₹1,30,000             │    │
│  │ Profit ₹5,000.00                              │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  Advanced ▼                                             │
│    Tax %  [_]    Discount %  [_]                       │
│    Delivered rate [_]    Billty rate [_]               │
│    Freight [_]  [type: Separate ▾]                     │
│    Notes [___________________________]                  │
│                                                         │
│  HSN: 1120202020    Item code: 1227                    │  ← small gray
├─────────────────────────────────────────────────────────┤
│  [Save & add more]        [Save]                       │
└─────────────────────────────────────────────────────────┘
```

---

## VALIDATION
- [ ] Select "SUGAR 50 KG" → qty label shows "Number of bags *"
- [ ] Enter qty=100 → preview shows "100 bags × 50 kg/bag = 5,000 kg"
- [ ] Enter purchase rate ₹26 → preview shows "5,000 kg × ₹26.00/kg → ₹1,30,000"
- [ ] Keyboard open → "Save" button stays above keyboard
- [ ] Select kg item → qty label shows "Qty (kg) *"
- [ ] Select box item → qty label shows "Number of boxes *"
