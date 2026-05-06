# SPEC 05 — PURCHASE DETAIL PAGE

> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS


| Task                                              | Status                               |
| ------------------------------------------------- | ------------------------------------ |
| 3-column summary strip (Amount / Weight / Profit) | ✅ Done (`_buildSummaryStrip`)        |
| Correct bag weight display in line items          | ✅ Done (`formatLineQtyWeightFromTradeLine`) |
| Correct selling rate display (₹/kg not ₹/bag)     | ✅ Done (`tradePurchaseLineDisplaySellingRate`, tin aligned) |
| Remove "stored total differs" error box           | ✅ Done (removed from UI)             |
| Remove "Est. sell value"                          | ✅ Done (not present in page)         |
| Remove "Total spend" wording                      | ✅ Done (not present in page)       |
| Zero-value charges hidden (Freight: —)            | ✅ Shows "—"                          |
| Print button in AppBar                            | ✅ Done (`_runPrintPdf`)             |
| Better action buttons layout                      | ✅ Done (Mark paid + Edit/Share/Print/PDF) |
| "Complete details pending" banner — tap to edit   | ✅ Done                               |


---

## FILES TO EDIT

```
flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart
flutter_app/lib/core/services/purchase_pdf.dart
```

---

## WHAT TO DO

### ❌ TASK 05-A: 3-column summary strip

**File:** `purchase_detail_page.dart`

Find the top card/section that shows the total amount. Replace with a 3-column strip:

```dart
Widget _buildSummaryStrip(BuildContext context, PurchaseDetailData data) {
  final profit = data.totalSelling - data.totalPurchase;
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: IntrinsicHeight(
      child: Row(
        children: [
          _summaryCol('AMOUNT', '₹${_fmtAmount(data.finalTotal)}', Colors.black87),
          VerticalDivider(width: 1, color: Colors.grey.shade200),
          _summaryCol('WEIGHT', _buildWeightText(data), Colors.black87),
          VerticalDivider(width: 1, color: Colors.grey.shade200),
          _summaryCol(
            'PROFIT',
            '₹${_fmtAmount(profit)}',
            profit >= 0 ? const Color(0xFF1B6B5A) : Colors.red.shade700,
          ),
        ],
      ),
    ),
  );
}

Widget _summaryCol(String label, String value, Color valueColor) {
  return Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

String _buildWeightText(PurchaseDetailData data) {
  // e.g. "5,000 kg\n100 bags"
  final kg = _fmtKg(data.totalWeightKg);
  final bags = data.totalBags;
  final boxes = data.totalBoxes;
  final tins = data.totalTins;
  final parts = <String>[];
  if (bags > 0) parts.add('${_fmtNum(bags.round())} bags');
  if (boxes > 0) parts.add('${_fmtNum(boxes.round())} boxes');
  if (tins > 0) parts.add('${_fmtNum(tins.round())} tins');
  if (parts.isEmpty) return kg;
  return '$kg\n${parts.join(' · ')}';
}
```

---

### ❌ TASK 05-B: Remove "stored total differs" error box

**File:** `purchase_detail_page.dart`

Search for the widget that shows the mismatch error:

```
"Stored total ₹X,XX,XXX differs from calculated ₹X,XX,XXX"
```

**Remove the entire widget.** The root cause (calc mismatch) should be fixed in the
backend (see `10_PERFORMANCE.md` TASK 10-D for DB fix), not displayed to the user.

---

### ❌ TASK 05-C: Remove "Est. sell value"

**File:** `purchase_detail_page.dart`

Search for `est.*sell\|Est.*sell\|estimated.*sell` and remove the row entirely.
This value shows `5000 bags × ₹27/kg` as if `5000` is bags times kg-rate,
giving a misleading ₹67,50,000 — it's wrong and confusing.

---

### ❌ TASK 05-D: Fix selling rate display in line items

**File:** `purchase_detail_page.dart`

For bag items, the selling rate stored is per-kg. Display must show per-kg.

Find where line items are rendered and showing `S ₹1,350`. Replace with:

```dart
// Import: lib/core/utils/line_display.dart
String _lineRateDisplay(Map<String, dynamic> line) {
  return formatLineRate(
    rate: (line['selling_rate'] ?? line['selling_cost'] as num?)?.toDouble() ?? 0,
    rateType: 'selling',
    unit: line['unit']?.toString() ?? 'kg',
    kgPerUnit: (line['kg_per_unit'] as num?)?.toDouble(),
  );
}
// Shows: "S ₹27.0/kg" for bag items instead of "S ₹1,350"
```

Same fix for purchase rate display.

---

### ❌ TASK 05-E: Print button in AppBar

**File:** `purchase_detail_page.dart`

Add a print icon to the AppBar actions:

```dart
IconButton(
  icon: const Icon(Icons.print_outlined, size: 22),
  tooltip: 'Print',
  onPressed: () async {
    final bytes = await generatePurchasePdf(purchase);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  },
),
```

Ensure `printing` package is in `pubspec.yaml` (it likely already is as `pdf` and `printing` are used for PDF generation).

---

### ❌ TASK 05-F: Better action buttons

**File:** `purchase_detail_page.dart`

Current: 2×2 grid with [Mark paid, Share, Edit, Download].

Replace with cleaner layout:

```dart
// Primary action full width:
if (!isPaid)
  _primaryBtn('Mark as Paid', Icons.check_circle_outline, _onMarkPaid),

const SizedBox(height: 8),

// Secondary actions row:
Row(children: [
  Expanded(child: _outlineBtn('Edit', Icons.edit_outlined, _onEdit)),
  const SizedBox(width: 8),
  Expanded(child: _outlineBtn('Share', Icons.share_outlined, _onShare)),
  const SizedBox(width: 8),
  Expanded(child: _outlineBtn('Print', Icons.print_outlined, _onPrint)),
  const SizedBox(width: 8),
  Expanded(child: _outlineBtn('PDF', Icons.download_outlined, _onDownloadPdf)),
]),
```

---

## SPEC: Full Detail Page Layout

```
AppBar: "PUR-2026-0005"    [✎ edit]  [↑ share]  [PDF]  [🖨 print]  [⋮]
──────────────────────────────────────────────────────────────

surag                                              [Pending chip]
Broker: kkkk
5 May 2026  |  Payment: 1 day  |  Due: 6 May 2026

┌─────────────┬─────────────┬─────────────┐
│   AMOUNT    │   WEIGHT    │   PROFIT    │
│  ₹1,37,800  │  5,000 kg   │  ₹5,000    │
│             │  100 bags   │             │
└─────────────┴─────────────┴─────────────┘

Items
┌──────────────────────────────────────────────────────────┐
│ 1. Basmathu                                              │
│    100 bags · 5,000 kg                                   │
│    P: ₹26/kg · S: ₹27/kg                                │
│    Line total: ₹1,30,000    Profit: ₹5,000              │
└──────────────────────────────────────────────────────────┘

Charges & balance          [expand ▾]
  Lines (incl. tax/disc)       ₹1,30,000
  Commission                    ₹7,800
  Freight                           —
  Billty                            —
  Delivered                         —
  ───────────────────────────────────
  FINAL TOTAL                 ₹1,37,800

Paid: ₹0.00    Balance: ₹1,37,800    Due: 6 May 2026

──────────────────────────────────────────────────────────
[         Mark as Paid         ]   ← full width, green
[  Edit  ]  [  Share  ]  [  Print  ]  [  PDF  ]
```

---

## VALIDATION

- "100 bags • 5,000 kg" shown in weight column (not "250000 kg")
- "S ₹27/kg" shown (not "S ₹1,350")
- No "Stored total differs" text anywhere
- No "Est. sell value" anywhere
- No "Total spend" text
- Print button opens system print dialog
- 3-column summary renders correctly on 393pt wide screen

