import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/business_profile.dart';

final _money = NumberFormat('#,##,##0', 'en_IN');
final _df = DateFormat('dd MMM yyyy');
final _genDf = DateFormat('dd MMM yyyy, h:mm a');

String _rs(num n) => 'Rs. ${_money.format(n)}';

const _border = PdfColor.fromInt(0xFFD1D5DB);
const _muted = PdfColor.fromInt(0xFF475569);
const _headerBg = PdfColor.fromInt(0xFFF1F5F9);

pw.Widget _hdr(String t) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 0),
      child: pw.Text(t,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black)),
    );

pw.Widget _kv(String k, String v, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.Text(v,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );

pw.Widget _divider() => pw.Container(
      height: 0.5,
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: const pw.BoxDecoration(color: _border),
    );

pw.Widget _tableSection({
  required List<String> headers,
  required List<List<String>> rows,
  List<pw.FlexColumnWidth>? widths,
}) {
  final cols = headers.length;
  final cw = widths ??
      List.generate(cols, (i) => pw.FlexColumnWidth(i == 0 ? 3 : 1));
  pw.Widget cell(String t,
          {bool bold = false, bool right = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          t,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black),
        ),
      );
  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.5),
    columnWidths: {for (var i = 0; i < cols; i++) i: cw[i]},
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          for (var i = 0; i < headers.length; i++)
            cell(headers[i], bold: true, right: i == headers.length - 1),
        ],
      ),
      for (final row in rows)
        pw.TableRow(children: [
          for (var i = 0; i < row.length; i++)
            cell(row[i],
                right: i == row.length - 1,
                bold: i == row.length - 1,
                color: i == row.length - 1
                    ? const PdfColor.fromInt(0xFF0E4F46)
                    : null),
        ]),
    ],
  );
}

/// Summary for the Reports screen — white/black, no colours, clean tables.
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
  String? priorPeriodNote,
  // Optional unit totals (kg / bag / box / tin).
  double? totalKg,
  double? totalBags,
  double? totalBoxes,
  double? totalTins,
  // Optional per-category rows: [{category_name, total_purchase}]
  List<Map<String, dynamic>>? categoryRows,
  // Optional per-supplier rows: [{supplier_name, purchase_count, total_purchase}]
  List<Map<String, dynamic>>? supplierRows,
}) async {
  final bizTitle = business.displayTitle.trim().isNotEmpty
      ? business.displayTitle
      : 'NEW HARISREE AGENCY';

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        // ── HEADER ────────────────────────────────────────────────────────
        pw.Text(bizTitle.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.Text('Purchase Report · $modeLabel',
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          '${_df.format(from)} - ${_df.format(to)}',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Total purchases is the sum of trade line amounts for deals in this range (same method as the in-app reports). A single purchase PDF invoice total can differ because it includes header terms (discount, freight, etc.).',
          style: const pw.TextStyle(
              fontSize: 7.2, color: _muted, height: 1.3),
        ),
        _divider(),

        // ── SUMMARY BLOCK ─────────────────────────────────────────────────
        _hdr('Summary'),
        _kv('Total purchases', _rs(totalPurchase), bold: true),
        _kv('Number of deals', '$purchaseCount'),
        if (totalKg != null && totalKg > 0)
          _kv('Total kg', '${totalKg.toStringAsFixed(0)} kg'),
        if (totalBags != null && totalBags > 0)
          _kv('Total bags', '${totalBags.toStringAsFixed(0)} bag'),
        if (totalBoxes != null && totalBoxes > 0)
          _kv('Total boxes', '${totalBoxes.toStringAsFixed(0)} box'),
        if (totalTins != null && totalTins > 0)
          _kv('Total tins', '${totalTins.toStringAsFixed(0)} tin'),
        _divider(),

        // ── MAIN TABLE ────────────────────────────────────────────────────
        _hdr('By $modeLabel'),
        pw.SizedBox(height: 4),
        if (tableRows.isEmpty)
          pw.Text('No data for this period.',
              style: const pw.TextStyle(fontSize: 9, color: _muted))
        else
          _tableSection(
            headers: ['Item', 'Total ₹'],
            widths: [
              const pw.FlexColumnWidth(4),
              const pw.FlexColumnWidth(2),
            ],
            rows: tableRows
                .take(50)
                .map((r) => [
                      rowLabel(r),
                      _rs(rowMetricPurchase(r)),
                    ])
                .toList(),
          ),
        _divider(),

        // ── CATEGORY SUMMARY ──────────────────────────────────────────────
        if (categoryRows != null && categoryRows.isNotEmpty) ...[
          _hdr('Category summary'),
          pw.SizedBox(height: 4),
          _tableSection(
            headers: ['Category', 'Total ₹'],
            rows: categoryRows
                .take(30)
                .map((r) => [
                      r['category_name']?.toString() ?? '—',
                      _rs(
                          (r['total_purchase'] as num?)?.toDouble() ?? 0),
                    ])
                .toList(),
          ),
          _divider(),
        ],

        // ── SUPPLIER SUMMARY ──────────────────────────────────────────────
        if (supplierRows != null && supplierRows.isNotEmpty) ...[
          _hdr('Supplier summary'),
          pw.SizedBox(height: 4),
          _tableSection(
            headers: ['Supplier', 'Deals', 'Total ₹'],
            widths: [
              const pw.FlexColumnWidth(3),
              const pw.FlexColumnWidth(1),
              const pw.FlexColumnWidth(2),
            ],
            rows: supplierRows
                .take(30)
                .map((r) => [
                      r['supplier_name']?.toString() ?? '—',
                      '${(r['purchase_count'] as num?)?.toInt() ?? 0}',
                      _rs(
                          (r['total_purchase'] as num?)?.toDouble() ?? 0),
                    ])
                .toList(),
          ),
          _divider(),
        ],

        // ── FOOTER ────────────────────────────────────────────────────────
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Period: ${_df.format(from)} – ${_df.format(to)}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
            pw.SizedBox(height: 3),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated by Harisree Exp&Pur',
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                ),
                pw.Text(
                  'Generated on: ${_genDf.format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  final safe =
      modeLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'report_${safe}_${_df.format(from)}.pdf',
  );
}

/// Sanitize for PDF default fonts (WinAnsi) — avoid rupee, en-dash, and emoji.
String _pdfAscii(String s) {
  return s
      .replaceAll('₹', 'Rs. ')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-');
}

/// Item purchase statement from trade rows (black/white tables, ASCII-friendly).
Future<void> shareItemPurchaseTradeHistoryPdf({
  required BusinessProfile business,
  required String itemName,
  required List<List<String>> rows,
  DateTime? periodFrom,
  DateTime? periodTo,
  String? periodDescription,
  String? totalLineLabel,
}) async {
  if (rows.isEmpty) return;
  final periodParts = <String>[];
  if (periodDescription != null && periodDescription.isNotEmpty) {
    periodParts.add(periodDescription);
  }
  if (periodFrom != null && periodTo != null) {
    // Hyphen, not en-dash, so default PDF font encodes it.
    periodParts
        .add('${_df.format(periodFrom)} - ${_df.format(periodTo)}');
  }
  final periodLine = periodParts.isEmpty
      ? 'All available lines in export'
      : periodParts.join(' | ');
  final cleanItem = _pdfAscii(itemName);
  const headers = <String>[
    'Date',
    'Supplier',
    'Broker',
    'Qty',
    'Rate',
    'Landing',
    'Selling',
    'Line total',
  ];
  if (rows.any((r) => r.length != headers.length)) {
    throw ArgumentError(
      'Item statement rows must have ${headers.length} columns, '
      'got ${rows.map((r) => r.length).toSet()}',
    );
  }
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text(
          _pdfAscii(
            business.legalName.trim().isNotEmpty
                ? business.legalName.trim()
                : (business.displayTitle.trim().isNotEmpty
                    ? business.displayTitle.trim()
                    : 'NEW HARISREE AGENCY'),
          ),
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Item statement - $cleanItem',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
        pw.SizedBox(height: 4),
        pw.Text('Period: ${_pdfAscii(periodLine)}',
            style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: _border, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(1.4),
            5: const pw.FlexColumnWidth(1.2),
            6: const pw.FlexColumnWidth(1.1),
            7: const pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _headerBg),
              children: [
                for (final h in headers)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(h,
                        style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black)),
                  ),
              ],
            ),
            for (final r in rows)
              pw.TableRow(
                children: [
                  for (var i = 0; i < r.length; i++)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(
                        _pdfAscii(r[i]),
                        textAlign:
                            i == r.length - 1 ? pw.TextAlign.right : pw.TextAlign.left,
                        style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.black),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (totalLineLabel != null && totalLineLabel.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              _pdfAscii(totalLineLabel),
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by Harisree Exp&Pur',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            pw.Text('Generated on: ${_genDf.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          ],
        ),
      ],
    ),
  );
  final safe = itemName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'item_statement_$safe.pdf',
  );
}
