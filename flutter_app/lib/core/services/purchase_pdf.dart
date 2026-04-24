import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';

final _money = NumberFormat('#,##,##0.00', 'en_IN');

/// PDF default fonts often lack U+20B9; use ASCII for print/share reliability.
String _inrPdf(num n) => 'Rs. ${_money.format(n)}';
final _dateFmt = DateFormat('dd MMM yyyy');

const _muted = PdfColor.fromInt(0xFF475569);
const _border = PdfColor.fromInt(0xFFD1D5DB);

Future<pw.ImageProvider?> _tryLogo(String? url) async {
  final u = url?.trim();
  if (u == null || u.isEmpty) return null;
  try {
    final r = await Dio().get<List<int>>(
      u,
      options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 8)),
    );
    final data = r.data;
    if (data == null || data.isEmpty) return null;
    return pw.MemoryImage(Uint8List.fromList(data));
  } catch (_) {
    return null;
  }
}

String _twoDigitsBelow100(int n) {
  const units = [
    '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
    'seventeen', 'eighteen', 'nineteen',
  ];
  const tens = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
  ];
  if (n < 20) return units[n];
  final t = n ~/ 10;
  final u = n % 10;
  return u == 0 ? tens[t] : '${tens[t]} ${units[u]}';
}

String _belowThousand(int n) {
  if (n < 100) return _twoDigitsBelow100(n);
  final h = n ~/ 100;
  final rest = n % 100;
  final hs = '${_twoDigitsBelow100(h)} hundred';
  if (rest == 0) return hs;
  return '$hs ${_twoDigitsBelow100(rest)}';
}

/// Indian numbering (lakh / crore) for invoice amount in words.
String amountInWordsInr(double amount) {
  var n = amount.floor();
  final paise = ((amount - n) * 100).round().clamp(0, 99);
  if (n == 0 && paise == 0) return 'Zero rupees only';

  final parts = <String>[];
  if (n >= 10000000) {
    parts.add('${_belowThousand(n ~/ 10000000)} crore');
    n %= 10000000;
  }
  if (n >= 100000) {
    parts.add('${_belowThousand(n ~/ 100000)} lakh');
    n %= 100000;
  }
  if (n >= 1000) {
    parts.add('${_belowThousand(n ~/ 1000)} thousand');
    n %= 1000;
  }
  if (n > 0) {
    parts.add(_belowThousand(n));
  }
  var rupees = parts.join(' ').trim();
  if (rupees.isEmpty) rupees = 'zero';
  rupees = '${rupees[0].toUpperCase()}${rupees.substring(1)} rupees';
  if (paise > 0) {
    final p = _twoDigitsBelow100(paise);
    return '$rupees and ${_cap(p)} paise only';
  }
  return '$rupees only';
}

String _cap(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

pw.Widget _cell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  pw.FontWeight? weight,
  double fontSize = 8.5,
  PdfColor? color,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: weight ?? pw.FontWeight.normal,
        color: color ?? PdfColors.black,
      ),
    ),
  );
}

pw.Widget _headerBlock(BusinessProfile biz, pw.ImageProvider? logo) {
  final title = biz.displayTitle.trim().isNotEmpty
      ? biz.displayTitle
      : 'NEW HARISREE AGENCY';
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 0),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
          bottom: pw.BorderSide(color: _border, width: 1.5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 10),
            child:
                pw.Image(logo, width: 44, height: 44, fit: pw.BoxFit.cover),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(
                  color: PdfColors.black,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (biz.address != null && biz.address!.isNotEmpty)
                pw.Text(
                  biz.address!,
                  style: const pw.TextStyle(
                      color: _muted, fontSize: 8.5, height: 1.35),
                ),
              pw.SizedBox(height: 3),
              pw.Row(
                children: [
                  if (biz.phone != null && biz.phone!.isNotEmpty)
                    pw.Text('Phone: ${biz.phone}',
                        style: const pw.TextStyle(
                            color: _muted, fontSize: 8.5)),
                  if (biz.phone != null &&
                      biz.phone!.isNotEmpty &&
                      biz.gstNumber != null)
                    pw.SizedBox(width: 14),
                  if (biz.gstNumber != null && biz.gstNumber!.isNotEmpty)
                    pw.Text('GSTIN: ${biz.gstNumber}',
                        style: const pw.TextStyle(
                            color: _muted, fontSize: 8.5)),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _partyRow(TradePurchase p) {
  String s(String? x) => (x == null || x.trim().isEmpty) ? '—' : x.trim();
  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.8),
    columnWidths: {
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(1),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
        children: [
          _cell('Supplier', weight: pw.FontWeight.bold),
          _cell('Broker', weight: pw.FontWeight.bold),
        ],
      ),
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(s(p.supplierName), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                if (p.supplierGst != null && p.supplierGst!.trim().isNotEmpty)
                  pw.Text(
                    'Supplier GST: ${p.supplierGst}',
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                if (p.supplierAddress != null && p.supplierAddress!.trim().isNotEmpty)
                  pw.Text(p.supplierAddress!, style: const pw.TextStyle(fontSize: 8, color: _muted, height: 1.2)),
                pw.Text('Phone: ${s(p.supplierPhone)}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('GSTIN: ${s(p.supplierGst)}', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(s(p.brokerName), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('Phone: ${s(p.brokerPhone)}', style: const pw.TextStyle(fontSize: 8)),
                if (p.brokerLocation != null && p.brokerLocation!.trim().isNotEmpty)
                  pw.Text(p.brokerLocation!, style: const pw.TextStyle(fontSize: 8, color: _muted, height: 1.2)),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _lineTableHeader() {
  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.6),
    columnWidths: {
      0: const pw.FixedColumnWidth(22),
      1: const pw.FlexColumnWidth(3.2),
      2: const pw.FixedColumnWidth(40),
      3: const pw.FixedColumnWidth(34),
      4: const pw.FixedColumnWidth(30),
      5: const pw.FixedColumnWidth(52),
      6: const pw.FixedColumnWidth(58),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
        children: [
          _cell('Sl', weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('Particulars', weight: pw.FontWeight.bold),
          _cell('HSN', weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('Qty', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('Unit', weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('Rate', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('Amount', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    ],
  );
}

pw.Widget _particularsCell(TradePurchaseLine l) {
  final kpu = l.kgPerUnit;
  final lcpk = l.landingCostPerKg;
  final isWeightLine = kpu != null && kpu > 0 && lcpk != null && lcpk > 0;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(l.itemName, style: const pw.TextStyle(fontSize: 8.5)),
        if (isWeightLine)
          pw.Text(
            '${l.qty} ${l.unit} × $kpu kg × ${_inrPdf(lcpk)}/kg',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          )
        else if (l.defaultKgPerBag != null &&
            l.defaultKgPerBag! > 0 &&
            l.unit.toLowerCase().contains('bag'))
          pw.Text(
            '${l.qty} bag(s) × ${l.defaultKgPerBag} kg/bag',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
      ],
    ),
  );
}

double _lineAmt(TradePurchaseLine l) {
  final kpu = l.kgPerUnit;
  final lcpk = l.landingCostPerKg;
  if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
    return l.qty * kpu * lcpk;
  }
  return l.qty * l.landingCost;
}

pw.Widget _lineRow(int index, TradePurchaseLine l) {
  final amt = _lineAmt(l);
  return pw.Table(
    border: const pw.TableBorder(
      left: pw.BorderSide(color: _border, width: 0.6),
      right: pw.BorderSide(color: _border, width: 0.6),
      bottom: pw.BorderSide(color: _border, width: 0.6),
    ),
    columnWidths: {
      0: const pw.FixedColumnWidth(22),
      1: const pw.FlexColumnWidth(3.2),
      2: const pw.FixedColumnWidth(40),
      3: const pw.FixedColumnWidth(34),
      4: const pw.FixedColumnWidth(30),
      5: const pw.FixedColumnWidth(52),
      6: const pw.FixedColumnWidth(58),
    },
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(
          color: index.isOdd ? const PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white,
        ),
        children: [
          _cell('$index', align: pw.TextAlign.center, fontSize: 8.5),
          _particularsCell(l),
          _cell(l.hsnCode?.trim().isNotEmpty == true ? l.hsnCode! : '—', align: pw.TextAlign.center, fontSize: 8),
          _cell(_money.format(l.qty), align: pw.TextAlign.right, fontSize: 8.5),
          _cell(l.unit, align: pw.TextAlign.center, fontSize: 8),
          _cell(_inrPdf(l.landingCost), align: pw.TextAlign.right, fontSize: 8.5),
          _cell(_inrPdf(amt), align: pw.TextAlign.right, fontSize: 8.5),
        ],
      ),
    ],
  );
}

double _lineSum(TradePurchase p) {
  var s = 0.0;
  for (final l in p.lines) {
    s += _lineAmt(l);
  }
  return s;
}

double _headerDiscountAmount(TradePurchase p) {
  final disc = p.discount ?? 0;
  if (disc <= 0) return 0;
  return _lineSum(p) * disc / 100.0;
}

double _brokerCommissionAmount(TradePurchase p) {
  final pct = p.commissionPercent ?? 0;
  if (pct <= 0) return 0;
  final base = _lineSum(p) - _headerDiscountAmount(p);
  return base * (pct / 100.0);
}

String _partyName(String? s) => (s == null || s.trim().isEmpty) ? '—' : s.trim();

/// One-page receipt: ASCII money, minimal lines — reliable fonts, easy to read.
Future<pw.Document> buildPurchaseReceiptDoc(
  TradePurchase p,
  BusinessProfile biz,
) async {
  final brokerAmt = _brokerCommissionAmount(p);
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text(
          biz.displayTitle.trim().isNotEmpty
              ? biz.displayTitle
              : 'NEW HARISREE AGENCY',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (biz.address != null && biz.address!.trim().isNotEmpty)
          pw.Text(
            biz.address!.trim(),
            style: const pw.TextStyle(fontSize: 9, color: _muted, height: 1.35),
          ),
        if (biz.phone != null && biz.phone!.trim().isNotEmpty)
          pw.Text(
            'Phone: ${biz.phone!.trim()}',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Purchase ${p.humanId}',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Supplier: ${_partyName(p.supplierName)}',
          style: const pw.TextStyle(fontSize: 10.5),
        ),
        if (p.brokerName != null && p.brokerName!.trim().isNotEmpty)
          pw.Text(
            'Broker: ${_partyName(p.brokerName)}',
            style: const pw.TextStyle(fontSize: 10.5),
          ),
        pw.Text(
          'Date: ${_dateFmt.format(p.purchaseDate)}',
          style: const pw.TextStyle(fontSize: 10.5),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Items',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        for (final l in p.lines) ...[
          pw.Text(
            l.itemName,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            '  ${l.qty} ${l.unit} x ${_inrPdf(l.landingCost)} = ${_inrPdf(l.qty * l.landingCost)}',
            style: const pw.TextStyle(fontSize: 9.5, color: _muted),
          ),
          pw.SizedBox(height: 6),
        ],
        pw.Container(height: 1, color: _border),
        pw.SizedBox(height: 8),
        pw.Text(
          'Total: ${_inrPdf(p.totalAmount)}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        if (brokerAmt > 0)
          pw.Text(
            'Broker commission: ${_inrPdf(brokerAmt)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Paid ${_inrPdf(p.paidAmount)}  ·  Balance ${_inrPdf(p.remaining)}',
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Generated by Harisree Exp&Pur',
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      ],
    ),
  );
  return doc;
}

pw.Widget _totalsAndPayment(TradePurchase p) {
  final sub = _lineSum(p);
  final disc = p.discount ?? 0;
  final freight = (p.freightType == 'included') ? 0.0 : (p.freightAmount ?? 0);
  final commPct = p.commissionPercent ?? 0;
  final commAmt = commPct > 0 ? sub * commPct / 100.0 : 0.0;
  final billty = p.billtyRate ?? 0;
  final delivered = p.deliveredRate ?? 0;

  pw.TableRow moneyRow(String label, String value, {bool bold = false}) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ),
      ],
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Table(
        border: pw.TableBorder.all(color: _border),
        columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
        children: [
          moneyRow('Subtotal (items)', _inrPdf(sub)),
          if (disc > 0) moneyRow('Discount (%)', '- ${_inrPdf(sub * disc / 100)}'),
          if (freight > 0) moneyRow('Freight', '+ ${_inrPdf(freight)}'),
          if (commAmt > 0) moneyRow('Commission (${commPct.toStringAsFixed(1)}%)', '+ ${_inrPdf(commAmt)}'),
          if (billty > 0) moneyRow('Billty / charges', '+ ${_inrPdf(billty)}'),
          if (delivered > 0) moneyRow('Delivered rate', '+ ${_inrPdf(delivered)}'),
          moneyRow('GRAND TOTAL', _inrPdf(p.totalAmount), bold: true),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        ),
        child: pw.Text(
          'Amount in words: ${amountInWordsInr(p.totalAmount)}',
          style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: _muted),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Paid: ${_inrPdf(p.paidAmount)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text('Balance: ${_inrPdf(p.remaining)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          if (p.dueDate != null)
            pw.Text('Due: ${_dateFmt.format(p.dueDate!)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    ],
  );
}

pw.Widget _footerSignatory(BusinessProfile biz) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 12),
      pw.Text(
        'Declaration: Goods received in good condition.',
        style: const pw.TextStyle(fontSize: 8, color: _muted),
      ),
      pw.SizedBox(height: 28),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by Harisree Exp&Pur',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('For ${biz.displayTitle}',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Authorised Signatory',
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        ],
      ),
    ],
  );
}

PdfColor _statusPdfColor(PurchaseStatus st) {
  switch (st) {
    case PurchaseStatus.paid:
      return const PdfColor.fromInt(0xFF159A8A);
    case PurchaseStatus.overdue:
      return const PdfColor.fromInt(0xFFE53935);
    case PurchaseStatus.partiallyPaid:
      return const PdfColor.fromInt(0xFFF59E0B);
    case PurchaseStatus.cancelled:
      return const PdfColor.fromInt(0xFFE53935);
    case PurchaseStatus.draft:
    case PurchaseStatus.saved:
      return const PdfColor.fromInt(0xFF64748B);
    case PurchaseStatus.unknown:
      return const PdfColor.fromInt(0xFF64748B);
    default:
      return const PdfColor.fromInt(0xFF16A34A);
  }
}

/// Builds the full A4 purchase invoice (Kerala wholesale style).
Future<pw.Document> buildPurchaseDoc(TradePurchase p, BusinessProfile biz) async {
  final logo = await _tryLogo(biz.logoUrl);
  final st = p.statusEnum;
  final statusColor = _statusPdfColor(st);

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      build: (ctx) => [
        _headerBlock(biz, logo),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(
            'PURCHASE INVOICE',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Invoice No: ${p.humanId}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: statusColor,
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Text(
                    st.label,
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Date: ${_dateFmt.format(p.purchaseDate)}', style: const pw.TextStyle(fontSize: 9.5)),
                pw.Text('UID: ${p.id}', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        _partyRow(p),
        pw.SizedBox(height: 10),
        _lineTableHeader(),
        for (var i = 0; i < p.lines.length; i++) _lineRow(i + 1, p.lines[i]),
        pw.SizedBox(height: 10),
        _totalsAndPayment(p),
        _footerSignatory(biz),
      ],
    ),
  );
  return doc;
}

Future<void> sharePurchasePdf(TradePurchase p, BusinessProfile biz) async {
  final doc = await buildPurchaseReceiptDoc(p, biz);
  await Printing.sharePdf(bytes: await doc.save(), filename: '${p.humanId}.pdf');
}

Future<void> printPurchasePdf(TradePurchase p, BusinessProfile biz) async {
  final doc = await buildPurchaseReceiptDoc(p, biz);
  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}

/// Opens OS print / save dialog (on web, typically download).
Future<void> downloadPurchasePdf(TradePurchase p, BusinessProfile biz) async {
  final doc = await buildPurchaseReceiptDoc(p, biz);
  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}

/// Full tax-style invoice (extra columns). Use when you need HSN / party blocks.
Future<void> sharePurchaseFullInvoicePdf(
  TradePurchase p,
  BusinessProfile biz,
) async {
  final doc = await buildPurchaseDoc(p, biz);
  await Printing.sharePdf(bytes: await doc.save(), filename: '${p.humanId}_full.pdf');
}
