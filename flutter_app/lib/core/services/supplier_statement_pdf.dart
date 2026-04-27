import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
final _money = NumberFormat('#,##,##0', 'en_IN');
final _df = DateFormat('dd MMM yyyy');

const _statementTitleInk = PdfColor.fromInt(0xFF0F172A);
const _statementTeal = PdfColor.fromInt(0xFF17A8A7);

String _rs(num n) => 'Rs. ${_money.format(n)}';

String _safe(String? s) =>
    (s == null || s.trim().isEmpty) ? '—' : s.trim();

/// Share a supplier PUR statement for [purchases] (already date-filtered).
Future<void> shareSupplierStatementPdf({
  required BusinessProfile business,
  required String supplierName,
  String? supplierAddress,
  String? supplierGst,
  String? supplierPhone,
  required List<TradePurchase> purchases,
  required DateTime fromDate,
  required DateTime toDate,
}) async {
  final doc = pw.Document();
  final total = purchases.fold<double>(0, (s, p) => s + p.totalAmount);
  final outstanding =
      purchases.fold<double>(0, (s, p) => s + p.remaining);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _safe(business.displayTitle.isNotEmpty
                ? business.displayTitle
                : business.legalName),
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _statementTitleInk,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'SUPPLIER ACCOUNT STATEMENT',
            style: pw.TextStyle(
              fontSize: 11,
              color: _statementTeal,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Supplier: ${_safe(supplierName)}',
              style: const pw.TextStyle(fontSize: 10)),
          if (supplierAddress != null && supplierAddress.trim().isNotEmpty)
            pw.Text('Address: ${_safe(supplierAddress)}',
                style: const pw.TextStyle(fontSize: 9)),
          if (supplierPhone != null && supplierPhone.trim().isNotEmpty)
            pw.Text('Phone: ${_safe(supplierPhone)}',
                style: const pw.TextStyle(fontSize: 9)),
          if (supplierGst != null && supplierGst.trim().isNotEmpty)
            pw.Text('GSTIN: ${_safe(supplierGst)}',
                style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            'Period: ${_df.format(fromDate)} – ${_df.format(toDate)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        ],
      ),
      footer: (ctx) => pw.Text(
        'Page ${ctx.pageNumber} of ${ctx.pagesCount} · Generated ${_df.format(DateTime.now())}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      build: (ctx) => [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(0.9),
            4: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _pcell('Date', bold: true),
                _pcell('Invoice', bold: true),
                _pcell('Items', bold: true),
                _pcell('Qty', bold: true, right: true),
                _pcell('Bill', bold: true, right: true),
              ],
            ),
            for (final p in purchases) ...[
              for (var i = 0; i < p.lines.length; i++) ...[
                pw.TableRow(
                  children: [
                    _pcell(i == 0 ? _df.format(p.purchaseDate) : ''),
                    _pcell(i == 0 ? p.humanId : ''),
                    _pcell(_safe(p.lines[i].itemName)),
                    _pcell(
                      '${p.lines[i].qty % 1 == 0 ? p.lines[i].qty.toInt() : p.lines[i].qty.toStringAsFixed(1)} ${p.lines[i].unit}',
                      right: true,
                    ),
                    _pcell(i == 0 ? _rs(p.totalAmount) : '', right: true),
                  ],
                ),
              ],
            ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          '${purchases.length} bill(s) · Total ${_rs(total)} · Outstanding ${_rs(outstanding)}',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'This is a computer-generated statement.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await doc.save(),
    filename:
        'supplier_statement_${supplierName.replaceAll(RegExp(r'[^\w\-]+'), '_')}.pdf',
  );
}

pw.Widget _pcell(String t, {bool bold = false, bool right = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        t,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
