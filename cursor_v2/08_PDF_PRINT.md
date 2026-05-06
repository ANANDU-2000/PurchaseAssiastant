# SPEC 08 — PDF, PRINT & BROKER STATEMENT

> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS


| Task                            | Status                                  |
| ------------------------------- | --------------------------------------- |
| Purchase invoice PDF generation | ✅ Done                                  |
| PDF shows purchase rate column  | ✅ Done (`P rate` column)                |
| PDF shows selling rate column   | ✅ Done (`S rate` + per-kg suffix fix)   |
| PDF shows total weight per item | ✅ Done (`Kg` column + qty/unit)        |
| Print button in detail page     | ✅ Done (AppBar + `printPurchasePdf`)    |
| Broker statement PDF            | ✅ Done (`shareBrokerStatementPdf` + broker history) |
| Supplier statement PDF          | ✅ Done (existing)                       |
| Item statement PDF              | ✅ Done (existing)                       |
| WhatsApp auto-report PDF        | ⚠️ MVP sheet exists, scheduling missing |


---

## FILES TO EDIT

```
flutter_app/lib/core/services/purchase_invoice_pdf_layout.dart
flutter_app/lib/core/services/purchase_pdf.dart
flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart
flutter_app/lib/core/services/broker_statement_pdf.dart   ← CREATE NEW
flutter_app/lib/features/broker/presentation/broker_history_page.dart
flutter_app/pubspec.yaml
```

---

## WHAT TO DO

### ❌ TASK 08-A: Add purchase rate + selling rate columns to PDF

**File:** `purchase_invoice_pdf_layout.dart`

Find the items table builder. Current columns likely: `#, Item, Qty, Unit, Amount`.

**Add columns: P-Rate, S-Rate** between Unit and Amount.

For bag items: show rate as `₹26/kg`, for kg items: `₹55/kg`.

```dart
// In _buildItemsTable(), add to header row:
pw.Text('P-Rate', style: headerStyle),
pw.Text('S-Rate', style: headerStyle),

// In each data row:
pw.Text(_displayRate(line.purchaseRate, line.unit, line.kgPerUnit)),
pw.Text(_displayRate(line.sellingRate, line.unit, line.kgPerUnit)),

String _displayRate(double rate, String unit, double? kpu) {
  final u = unit.toLowerCase();
  if ((u == 'bag' || u == 'sack') && kpu != null && kpu > 0) {
    return '₹${rate.toStringAsFixed(1)}/kg';
  }
  return '₹${rate.toStringAsFixed(1)}/${u.isEmpty ? 'unit' : u}';
}
```

**Also add to footer totals:**

```
Total weight: 5,000 kg · 100 bags
Total purchase: ₹1,30,000
```

---

### ❌ TASK 08-B: Print button in detail page

**File:** `purchase_detail_page.dart`

Add `printing` package usage. The package is likely already in `pubspec.yaml`
(check with `grep 'printing:' pubspec.yaml`). If not, add:

```yaml
printing: ^5.12.0
```

**Add print function:**

```dart
Future<void> _onPrint() async {
  try {
    final bytes = await ref.read(purchasePdfProvider(purchaseId).future);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'PUR-${purchase.humanId}',
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }
}
```

**Add to AppBar actions:**

```dart
IconButton(
  icon: const Icon(Icons.print_outlined, size: 22),
  tooltip: 'Print',
  onPressed: _onPrint,
),
```

---

### ❌ TASK 08-C: Create broker_statement_pdf.dart

**Create new file:** `lib/core/services/broker_statement_pdf.dart`

Model exactly after `supplier_statement_pdf.dart` but for broker context:

```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a broker commission statement PDF.
/// Shows all purchases where this broker is linked, with commission details.
Future<Uint8List> generateBrokerStatement({
  required String brokerName,
  required String brokerPhone,
  required String businessName,
  required DateTimeRange dateRange,
  required List<Map<String, dynamic>> purchases,
}) async {
  final pdf = pw.Document();
  
  // Load fonts (reuse existing font helpers from pdf_purchase_fonts.dart)
  final fonts = await loadPurchaseFonts();
  
  // Calculate totals
  double totalCommission = 0;
  for (final p in purchases) {
    totalCommission += (p['commission_amount'] as num?)?.toDouble() ?? 0;
  }
  
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        // Header
        _buildHeader(businessName, brokerName, brokerPhone, dateRange, fonts),
        pw.SizedBox(height: 20),
        
        // Table
        _buildPurchaseTable(purchases, fonts),
        pw.SizedBox(height: 16),
        
        // Totals
        _buildTotals(totalCommission, purchases.length, fonts),
      ],
    ),
  );
  
  return pdf.save();
}

pw.Widget _buildHeader(String business, String broker, String phone,
    DateTimeRange range, PurchaseFonts fonts) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(business, style: pw.TextStyle(font: fonts.bold, fontSize: 18)),
      pw.SizedBox(height: 8),
      pw.Text('BROKER COMMISSION STATEMENT',
          style: pw.TextStyle(font: fonts.bold, fontSize: 13, letterSpacing: 1)),
      pw.SizedBox(height: 8),
      pw.Row(children: [
        pw.Text('Broker: $broker  $phone', style: pw.TextStyle(font: fonts.regular)),
        pw.Spacer(),
        pw.Text(
          '${_fmtDate(range.start)} – ${_fmtDate(range.end)}',
          style: pw.TextStyle(font: fonts.regular),
        ),
      ]),
      pw.Divider(),
    ],
  );
}

pw.Widget _buildPurchaseTable(List<Map<String, dynamic>> purchases, PurchaseFonts fonts) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: {
      0: const pw.FlexColumnWidth(1.2),  // Date
      1: const pw.FlexColumnWidth(1.5),  // PUR ID
      2: const pw.FlexColumnWidth(2),    // Supplier
      3: const pw.FlexColumnWidth(2),    // Items
      4: const pw.FlexColumnWidth(1.5),  // Total
      5: const pw.FlexColumnWidth(1.5),  // Commission
    },
    children: [
      // Header
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: ['Date', 'PUR ID', 'Supplier', 'Items', 'Total', 'Commission']
            .map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(h, style: pw.TextStyle(font: fonts.bold, fontSize: 9)),
                ))
            .toList(),
      ),
      // Data rows
      for (final p in purchases)
        pw.TableRow(
          children: [
            _cell(_fmtDate(p['purchase_date']), fonts),
            _cell(p['human_id']?.toString() ?? '', fonts),
            _cell(p['supplier_name']?.toString() ?? '', fonts),
            _cell(_itemsSummary(p), fonts),
            _cell('₹${_fmtAmt(p['total_amount'])}', fonts),
            _cell('₹${_fmtAmt(p['commission_amount'])}', fonts),
          ],
        ),
    ],
  );
}

pw.Widget _buildTotals(double totalComm, int count, PurchaseFonts fonts) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('$count purchases', style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Total Commission: ₹${_fmtAmt(totalComm)}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 13),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _cell(String text, PurchaseFonts fonts) => pw.Padding(
  padding: const pw.EdgeInsets.all(5),
  child: pw.Text(text, style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
);

String _itemsSummary(Map<String, dynamic> p) {
  final lines = (p['lines'] as List?)?.cast<Map>() ?? [];
  if (lines.isEmpty) return '—';
  final first = lines.first['item_name']?.toString() ?? '—';
  return lines.length > 1 ? '$first +${lines.length - 1}' : first;
}

String _fmtDate(dynamic d) {
  if (d == null) return '—';
  final dt = d is DateTime ? d : DateTime.tryParse(d.toString());
  if (dt == null) return '—';
  return DateFormat('dd/MM/yy').format(dt);
}

String _fmtAmt(dynamic v) {
  final n = (v as num?)?.toDouble() ?? 0;
  return n.toStringAsFixed(2);
}
```

**Add broker statement download button** in `broker_detail_page.dart` or `broker_history_page.dart`:

```dart
IconButton(
  icon: const Icon(Icons.receipt_long_outlined),
  tooltip: 'Commission statement',
  onPressed: _downloadBrokerStatement,
),
```

---

## VALIDATION

- Purchase PDF has P-Rate and S-Rate columns
- Purchase PDF bag items show "₹26/kg" not "₹1,300/bag"
- PDF shows "100 bags • 5,000 kg" not "250000 kg"
- Print button opens iOS system print dialog
- Broker statement PDF downloads with correct commission totals
- Broker statement table shows all purchases in date range

