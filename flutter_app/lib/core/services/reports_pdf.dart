import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/business_profile.dart';

final _money = NumberFormat('#,##,##0.00', 'en_IN');
final _df = DateFormat('dd MMM yyyy');

String _rs(num n) => 'Rs. ${_money.format(n)}';

/// One-page summary for the Reports screen (ASCII money for font safety).
Future<void> shareReportsSummaryPdf({
  required BusinessProfile business,
  required DateTime from,
  required DateTime to,
  required String modeLabel,
  required double totalPurchase,
  required double totalProfit,
  required int purchaseCount,
  required List<Map<String, dynamic>> tableRows,
  required String Function(Map<String, dynamic> r) rowLabel,
  required num Function(Map<String, dynamic> r) rowMetricPurchase,
  required num Function(Map<String, dynamic> r) rowMetricProfit,
  /// Optional ASCII note (e.g. prior-window profit/spend % from Reports screen).
  String? priorPeriodNote,
}) async {
  final priorPdf = priorPeriodNote?.trim();
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            business.displayTitle,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF0E4F46),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Reports · $modeLabel',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            '${_df.format(from)} – ${_df.format(to)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          pw.Text('Purchases: $purchaseCount', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Total spend: ${_rs(totalPurchase)}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Total profit: ${_rs(totalProfit)}', style: const pw.TextStyle(fontSize: 10)),
          if (priorPdf != null && priorPdf.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Vs prior period (same-length window)',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              priorPdf,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Text(
            'Top rows (this view)',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          for (final r in tableRows.take(40)) ...[
            pw.Text(
              rowLabel(r),
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '  Spend ${_rs(rowMetricPurchase(r).toDouble())} · Profit ${_rs(rowMetricProfit(r).toDouble())}',
              style: const pw.TextStyle(fontSize: 8.8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 4),
          ],
        ],
      ),
    ),
  );
  final safe = modeLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'reports_${safe}_${_df.format(from)}.pdf',
  );
}
