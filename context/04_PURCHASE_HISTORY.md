# SPEC 04 — PURCHASE HISTORY LIST

> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS


| Task                                               | Status                          |
| -------------------------------------------------- | ------------------------------- |
| "Total spend" text removed                         | ✅ Done (no matches in `lib/`)   |
| "Complete details pending" removed from list cards | ✅ Done (not present in UI code) |
| Compact card layout (72–80pt height)               | ⚠️ Implemented (verify)         |
| Weight display: bags • kg (not just kg)            | ⚠️ Implemented (verify)         |
| Zero values hidden (0 bags, 0 box, 0 tin)          | ✅ Done                          |
| History page full viewport (hide top nav)          | ⚠️ Implemented (verify)         |
| Draft WIP card shown at top of list                | ✅ Banner exists on home         |
| Filter chips (All / Draft / Due soon)              | ✅ Done                          |
| Search by supplier / item                          | ✅ Done                          |
| Pull-to-refresh                                    | ✅ Done                          |


---

## FILES TO EDIT

```
flutter_app/lib/shared/widgets/trade_purchase_ledger_cards.dart
flutter_app/lib/features/purchase/presentation/purchase_home_page.dart
```

---

## WHAT TO DO

### ❌ TASK 04-A: Compact history card layout

**File:** `trade_purchase_ledger_cards.dart`

Find the main card builder function (likely `buildTradePurchaseCard` or similar).
Replace the card content with this compact layout.

**Target height per card: 76–84pt**

```dart
// Compact card — max height ~80pt
Widget buildCompactHistoryCard({
  required Map<String, dynamic> p,   // purchase map
  required VoidCallback onTap,
}) {
  final supplier = p['supplier_name']?.toString() ?? '—';
  
  // Items summary — first item name + total weight
  final lines = (p['lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final firstLine = lines.isNotEmpty ? lines.first : null;
  final itemName = firstLine?['item_name']?.toString() ?? '—';
  final qty = (firstLine?['qty'] as num?)?.toDouble() ?? 0;
  final unit = firstLine?['unit']?.toString() ?? 'kg';
  final kpu = (firstLine?['kg_per_unit'] as num?)?.toDouble();
  // Use formatLineQtyWeight from lib/core/utils/line_display.dart:
  final weightStr = formatLineQtyWeight(qty: qty, unit: unit, kgPerUnit: kpu);
  
  // Extra items count
  final moreCount = lines.length > 1 ? ' +${lines.length - 1}' : '';
  
  // Amount — prefer total_amount, fallback to stored_bill_total
  final amount = _fmtAmount(
    p['total_amount'] ?? p['stored_bill_total'] ?? 0);
  
  // Payment status
  final status = (p['payment_status']?.toString() ?? 'pending').toLowerCase();
  
  // PUR ID + date
  final purId = p['human_id']?.toString() ?? '';
  final rawDate = p['purchase_date']?.toString() ?? '';
  final dateStr = _fmtDate(rawDate);
  
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: text info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  supplier,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$itemName$moreCount  •  $weightStr',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$purId  ·  $dateStr',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Right: amount + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '₹$amount',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              _StatusChip(status: status),
            ],
          ),
        ],
      ),
    ),
  );
}

// Compact status chip
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'paid':
        bg = const Color(0xFFE8F5E9); fg = const Color(0xFF2E7D32);
        label = 'Paid'; break;
      case 'overdue':
        bg = const Color(0xFFFFEBEE); fg = const Color(0xFFC62828);
        label = 'Overdue'; break;
      case 'draft':
        bg = const Color(0xFFFFF8E1); fg = const Color(0xFFE65100);
        label = 'Draft'; break;
      default:
        bg = const Color(0xFFFFF3E0); fg = const Color(0xFFE65100);
        label = 'Pending'; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
```

**REMOVE from card:**

- "Complete details pending" warning text and icon
- "Mark paid" inline quick action button
- "Rem ₹X.XX" balance text (shown in detail only)
- "Overdue by X day(s)" text (status chip is enough)
- "0 bags", "0 box", "0 tin" when value is zero

---

### ❌ TASK 04-B: Remove "total spend" wording everywhere

**Global search:** Find all instances of these strings in `lib/`:

```
"total spend"
"Total spend"  
"totalSpend"
"total_spend"
```

Replace with:

- In list cards: "Amount"
- In detail page: "Total"
- In supplier summary: "Total purchased"
- In reports: "Purchase amount"

---

### ❌ TASK 04-C: History page — full viewport (hide nav chrome)

**File:** `purchase_home_page.dart`

The history / purchase list page currently shows the shell's top navigation bar
AND the tab bar, eating ~100pt of vertical space.

When the user is ON the history tab (PurchaseHomePage), the shell should hide
the top navigation bar. This is already done on some pages via `hideBottomNav`.

Check if `PurchaseHomePage` uses a `Scaffold` inside the shell.
If so, the AppBar on `PurchaseHomePage` competes with the shell's AppBar.

**Solution:** Give `PurchaseHomePage` its own AppBar with search and filter chips.
Set the shell's `showAppBar: false` when history tab is active.
OR remove the shell AppBar from history tab using an existing shell feature flag.

---

## VALIDATION

- Each card height is ≤84pt (measure on device)
- "Complete details pending" NOT shown in list
- "Total spend" text NOT found anywhere in UI
- "100 bags • 5,000 kg" shown for bag items (not "250000 kg")
- Zero values not shown ("0 bags" never appears)
- Status chips show correct color: paid=green, pending=orange, overdue=red

