import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../json_coerce.dart';
import 'pdf_actions.dart';
import 'pdf_text_safe.dart';

/// Simple warehouse stock list PDF (current filter snapshot).
Future<Uint8List> buildStockListPdf({
  required String businessName,
  required List<Map<String, dynamic>> rows,
  String? filterSummary,
}) async {
  final doc = pw.Document();
  final gen = DateFormat('dd MMM yyyy, h:mm a').format(DateTime.now());

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            safePdfText(businessName),
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            safePdfText('Stock statement | $gen'),
            style: const pw.TextStyle(fontSize: 10),
          ),
          if (filterSummary != null && filterSummary.trim().isNotEmpty)
            pw.Text(
              safePdfText(filterSummary),
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.SizedBox(height: 8),
        ],
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: const [
            'Item',
            'Code',
            'Barcode',
            'Stock',
            'Unit',
            'Status',
          ],
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 8),
          data: [
            for (final r in rows)
              [
                safePdfText(r['name']?.toString() ?? ''),
                safePdfText(r['item_code']?.toString() ?? ''),
                safePdfText(r['barcode']?.toString() ?? ''),
                _fmtQty(coerceToDouble(r['current_stock'])),
                safePdfText(
                  (r['stock_unit'] ?? r['unit'])?.toString() ?? '',
                ),
                safePdfText(r['stock_status']?.toString() ?? ''),
              ],
          ],
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3),
        ),
      ],
    ),
  );
  return doc.save();
}

String _fmtQty(double n) {
  if (!n.isFinite) return pdfEmpty;
  final r = n.roundToDouble();
  if ((n - r).abs() < 0.001) return r.round().toString();
  return n.toStringAsFixed(1);
}

Future<PdfActionResult> shareStockListPdf({
  required Uint8List bytes,
  String filename = 'harisree_stock_statement.pdf',
}) {
  return sharePdfBytes(
    buildBytes: () async => bytes,
    filename: filename,
    subject: 'Harisree stock statement',
    source: 'stock_list_pdf',
  );
}
