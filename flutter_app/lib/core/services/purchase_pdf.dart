import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../calc_engine.dart' show lineMoney;
import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
import '../utils/trade_purchase_rate_display.dart';
import '../units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../config/app_config.dart';
import 'pdf_purchase_fonts.dart';
import 'purchase_invoice_amount_words.dart';
import 'purchase_invoice_pdf_layout.dart';
import 'pdf_text_safe.dart';

final _money = NumberFormat('#,##,##0.00', 'en_IN');
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
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final data = r.data;
    if (data == null || data.isEmpty) return null;
    return pw.MemoryImage(Uint8List.fromList(data));
  } catch (_) {
    return null;
  }
}

String _partyName(String? s) => (s == null || s.trim().isEmpty) ? '—' : safePdfText(s.trim());

String _pdfReceiptPurchase(TradePurchaseLine l) {
  final r = tradePurchaseLineDisplayPurchaseRate(l);
  return '${_inrPdf(r)}/${unit_lbl.purchaseRateSuffix(l)}';
}

String _pdfReceiptSelling(TradePurchaseLine l) {
  final r = tradePurchaseLineDisplaySellingRate(l);
  if (r == null) return '—';
  return '${_inrPdf(r)}/${unit_lbl.sellingRateSuffix(l)}';
}

/// One-page receipt: minimal lines (Unicode-safe when [pdfTheme] set).
Future<pw.Document> buildPurchaseReceiptDoc(
  TradePurchase p,
  BusinessProfile biz, {
  pw.ThemeData? pdfTheme,
}) async {
  final brokerAmt = purchaseBrokerCommissionForReceipt(p);
  final doc = pw.Document(theme: pdfTheme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: pdfTheme,
      build: (ctx) => [
        pw.Text(
          safePdfText(
            biz.displayTitle.trim().isNotEmpty ? biz.displayTitle : 'Business',
          ),
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (biz.address != null && biz.address!.trim().isNotEmpty)
          pw.Text(
            safePdfText(biz.address!.trim()),
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
            safePdfText(l.itemName),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            '  ${l.qty} ${l.unit}  ·  P ${_pdfReceiptPurchase(l)}  ·  S ${_pdfReceiptSelling(l)}  ·  ${_inrPdf(l.lineTotal ?? lineMoney(tradePurchaseLineToCalcLine(l)))}',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
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
        pw.SizedBox(height: 10),
        pw.Text(
          'Amount in words: ${amountInWordsInr(p.totalAmount)}',
          style: const pw.TextStyle(fontSize: 8, color: _muted, height: 1.2),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          safePdfText(AppConfig.appName),
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      ],
    ),
  );
  return doc;
}

/// Professional A4 purchase order; footer uses server [TradePurchase.totalAmount].
Future<pw.Document> buildPurchaseDoc(TradePurchase p, BusinessProfile biz) async {
  final logo = await _tryLogo(biz.logoUrl);
  final pdfTheme = await loadPurchasePdfTheme();
  final doc = await buildProfessionalPurchaseInvoiceDoc(
    purchase: p,
    business: biz,
    logo: logo,
    pdfTheme: pdfTheme,
  );
  return doc;
}

Future<void> sharePurchasePdf(TradePurchase p, BusinessProfile biz) async {
  final doc = await buildPurchaseDoc(p, biz);
  await Printing.sharePdf(bytes: await doc.save(), filename: '${p.humanId}.pdf');
}

Future<void> printPurchasePdf(TradePurchase p, BusinessProfile biz) async {
  final doc = await buildPurchaseDoc(p, biz);
  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}

Future<void> downloadPurchasePdf(TradePurchase p, BusinessProfile biz) async {
  final doc = await buildPurchaseDoc(p, biz);
  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}

Future<void> sharePurchaseFullInvoicePdf(
  TradePurchase p,
  BusinessProfile biz,
) async {
  final doc = await buildPurchaseDoc(p, biz);
  await Printing.sharePdf(bytes: await doc.save(), filename: '${p.humanId}_full.pdf');
}
