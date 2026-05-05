# SPEC 12 — SUPPLIER DETAIL & LEDGER PAGE
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| Supplier detail header (bills, spend, unpaid) | ✅ Done |
| Add total weight + bags to header | ✅ Done |
| Purchase history rows — selling rate display fix | ✅ Done (shows S:₹/kg for bag-family) |
| Supplier ledger page — horizontal scroll | ✅ Done |
| Supplier ledger — card layout | ✅ Done |
| "Total spend" → "Total purchased" | ✅ Done |
| "New purchase" FAB context (pre-fills supplier) | ✅ Done |

---

## FILES TO EDIT
```
flutter_app/lib/features/contacts/presentation/supplier_detail_page.dart
flutter_app/lib/features/supplier/presentation/supplier_ledger_page.dart
```

---

## WHAT TO DO

### ❌ TASK 12-A: Add weight stats to supplier header

**File:** `supplier_detail_page.dart`

Find the summary row that shows `Bills | Total spend | Unpaid`.
Add weight total beside or below:

```dart
// Below the Bills/Total/Unpaid row:
Row(children: [
  _statTile('Est. weight', _fmtKg(supplier.totalWeightKg ?? 0)),
  _statTile('Total bags', _fmtNum(supplier.totalBags?.round() ?? 0)),
  if ((supplier.totalBoxes ?? 0) > 0)
    _statTile('Total boxes', _fmtNum(supplier.totalBoxes!.round())),
]),
```

If `totalWeightKg` / `totalBags` are not in the supplier model,
add them to the backend API response:

```python
# In supplier aggregate query, add:
total_weight_kg=sum(line.qty * line.kg_per_unit for p in purchases for line in p.lines if line.kg_per_unit),
total_bags=sum(line.qty for p in purchases for line in p.lines if line.unit in ('bag','sack')),
```

---

### ❌ TASK 12-B: Fix selling rate in purchase history rows

**File:** `supplier_detail_page.dart`

History rows show `S ₹1,350` for bag items. Should show `S ₹27/kg`.

Find where `S ₹X` is displayed in purchase history cards.
Replace with `formatLineRate()` from `lib/core/utils/line_display.dart`.

---

### ❌ TASK 12-C: Supplier ledger — card layout (no horizontal scroll)

**File:** `supplier_ledger_page.dart`

Replace any `DataTable` or horizontally scrolling widget with vertical cards:

```dart
Widget _buildLedgerCard(Map<String, dynamic> item) {
  final name = item['item_name']?.toString() ?? '—';
  final date = _fmtDate(item['purchase_date']);
  final purId = item['human_id']?.toString() ?? '';
  final qty = (item['qty'] as num?)?.toDouble() ?? 0;
  final unit = item['unit']?.toString() ?? 'kg';
  final kpu = (item['kg_per_unit'] as num?)?.toDouble();
  final pRate = (item['purchase_rate'] as num?)?.toDouble() ?? 0;
  final sRate = (item['selling_rate'] as num?)?.toDouble() ?? 0;
  final amount = (item['line_total'] as num?)?.toDouble() ?? 0;

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A1A))),
            Text('₹${_fmtAmt(amount)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A1A))),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$date  ·  $purId',
          style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
        ),
        const SizedBox(height: 4),
        // Weight display using line_display.dart
        Text(
          formatLineQtyWeight(qty: qty, unit: unit, kgPerUnit: kpu),
          style: const TextStyle(fontSize: 12, color: Color(0xFF555555), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(children: [
          _rateChip(formatLineRate(rate: pRate, rateType: 'purchase', unit: unit, kgPerUnit: kpu)),
          const SizedBox(width: 8),
          _rateChip(formatLineRate(rate: sRate, rateType: 'selling', unit: unit, kgPerUnit: kpu)),
        ]),
      ],
    ),
  );
}

Widget _rateChip(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: Colors.grey.shade100,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF333333), fontWeight: FontWeight.w600)),
);
```

---

## SPEC: Supplier Detail Layout

```
AppBar: "surag"   [✎]  [PDF]  [↑]

surag
📍 delhi
[📞 123456789]  [WhatsApp]

┌──────────┬─────────────┬────────────┐
│  5 Bills  │  ₹10,85,244 │  ₹8,10,244 │
│           │  Purchased  │  Unpaid    │
└──────────┴─────────────┴────────────┘

Est. weight: 20.0 t  |  200 bags  |  100 boxes

Linked broker →

[This Month] [3 Months ✓] [6 Months] [All]
Feb 5 – May 5, 2026

[Search by invoice, item…]

Purchase history  (5 bills)
──────────────────────────────────────
PUR-2026-0005  May 5, 2026  ₹1,30,000
  Basmathu · 100 bags · 5,000 kg
  P:₹26/kg · S:₹27/kg

PUR-2026-0004  May 5, 2026  ₹2,75,000
  SUGAR 50 KG · 5,000 bags · 2,50,000 kg
  P:₹55/kg · S:₹56/kg
...

[+ New purchase]  ← FAB, bottom right
```

---

## VALIDATION
- [ ] Supplier header shows total weight and bags
- [ ] History rows show "S ₹27/kg" not "S ₹1,350"
- [ ] Ledger page has NO horizontal scroll — all card layout
- [ ] Ledger shows "100 bags • 5,000 kg" not "250000 KG"
- [ ] "Total spend" replaced with "Purchased"
