import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
import '../utils/trade_purchase_commission.dart';

final _money = NumberFormat('#,##,##0', 'en_IN');
final _df = DateFormat('dd MMM yyyy');

const _statementTitleInk = PdfColor.fromInt(0xFF0F172A);
const _statementTeal = PdfColor.fromInt(0xFF17A8A7);

String _rs(num n) => 'Rs. ${_money.format(n)}';

String _safe(String? s) =>
    (s == null || s.trim().isEmpty) ? '—' : s.trim();

String _brokerStatementFilename(String brokerName) =>
    'broker_statement_${brokerName.replaceAll(RegExp(r'[^\w\-]+'), '_')}.pdf';

pw.Document _buildBrokerStatementDocument({
  required BusinessProfile business,
  required String brokerName,
  String? brokerPhone,
  required List<TradePurchase> purchases,
  required DateTime fromDate,
  required DateTime toDate,
}) {
  final doc = pw.Document();
  var commissionSum = 0.0;
  for (final p in purchases) {
    commissionSum += tradePurchaseCommissionInr(p);
  }

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
            'BROKER COMMISSION STATEMENT',
            style: pw.TextStyle(
              fontSize: 11,
              color: _statementTeal,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Broker: ${_safe(brokerName)}',
              style: const pw.TextStyle(fontSize: 10)),
          if (brokerPhone != null && brokerPhone.trim().isNotEmpty)
            pw.Text('Phone: ${_safe(brokerPhone)}',
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
            0: const pw.FlexColumnWidth(1.2),
            1: const pw.FlexColumnWidth(1.1),
            2: const pw.FlexColumnWidth(1.6),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(0.95),
            5: const pw.FlexColumnWidth(0.95),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _pcell('Date', bold: true),
                _pcell('Bill', bold: true),
                _pcell('Supplier', bold: true),
                _pcell('Items', bold: true),
                _pcell('Bill ₹', bold: true, right: true),
                _pcell('Comm. ₹', bold: true, right: true),
              ],
            ),
            for (final p in purchases) ...[
              for (var i = 0; i < p.lines.length; i++) ...[
                pw.TableRow(
                  children: [
                    _pcell(i == 0 ? _df.format(p.purchaseDate) : ''),
                    _pcell(i == 0 ? p.humanId : ''),
                    _pcell(i == 0 ? _safe(p.supplierName) : ''),
                    _pcell(_safe(p.lines[i].itemName)),
                    _pcell(i == 0 ? _rs(p.totalAmount) : '', right: true),
                    _pcell(
                      i == 0
                          ? _rs(tradePurchaseCommissionInr(p))
                          : '',
                      right: true,
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          '${purchases.length} bill(s) · Commission total ${_rs(commissionSum)}',
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

  return doc;
}

/// Broker commission statement for [purchases] (already date-filtered).
Future<void> shareBrokerStatementPdf({
  required BusinessProfile business,
  required String brokerName,
  String? brokerPhone,
  required List<TradePurchase> purchases,
  required DateTime fromDate,
  required DateTime toDate,
}) async {
  final doc = _buildBrokerStatementDocument(
    business: business,
    brokerName: brokerName,
    brokerPhone: brokerPhone,
    purchases: purchases,
    fromDate: fromDate,
    toDate: toDate,
  );
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: _brokerStatementFilename(brokerName),
  );
}

/// Same PDF via system share sheet (pick WhatsApp, Drive, etc.).
Future<void> shareBrokerStatementPdfForChat({
  required BusinessProfile business,
  required String brokerName,
  String? brokerPhone,
  required List<TradePurchase> purchases,
  required DateTime fromDate,
  required DateTime toDate,
}) async {
  final doc = _buildBrokerStatementDocument(
    business: business,
    brokerName: brokerName,
    brokerPhone: brokerPhone,
    purchases: purchases,
    fromDate: fromDate,
    toDate: toDate,
  );
  final bytes = await doc.save();
  final fn = _brokerStatementFilename(brokerName);
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: fn,
      ),
    ],
    text: 'Broker commission statement · $brokerName',
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
