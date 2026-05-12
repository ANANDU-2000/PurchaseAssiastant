import 'package:intl/intl.dart';

import '../../../core/calc_engine.dart';
import '../domain/purchase_draft.dart' show RateTaxBasis;

final _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String _money(num n) => _inr2.format(n);

/// Trader-readable breakdown for the add-item preview (mirrors [lineMoney] / [lineTaxAmount]).
class PurchaseLinePreviewModel {
  const PurchaseLinePreviewModel({
    required this.enteredPurchaseLine,
    required this.taxableLine,
    required this.gstLine,
    required this.linePurchaseLine,
    this.chargesLine,
    this.sellingLine,
    this.profitLine,
  });

  final String enteredPurchaseLine;
  final String taxableLine;
  final String gstLine;
  final String linePurchaseLine;
  final String? chargesLine;
  final String? sellingLine;
  final String? profitLine;
}

String _basisLabel(RateTaxBasis b) =>
    b == RateTaxBasis.includesTax ? 'GST included' : 'GST extra';

PurchaseLinePreviewModel buildPurchaseLinePreviewModel({
  required TradeCalcLine line,
  required String unitLabel,
  required double qty,
  required double enteredPurchaseDisplay,
  required RateTaxBasis purchaseBasis,
  required double? enteredSellingDisplay,
  required RateTaxBasis sellBasis,
  required bool omitLineFreight,
  required double profitPreview,
  required bool hasSelling,
}) {
  final taxable = lineTaxableAfterLineDisc(line);
  final gst = lineTaxAmount(line);
  final purchaseIncl = lineMoney(line);
  final charges =
      omitLineFreight ? 0.0 : lineItemFreightCharges(line);

  final taxPct = line.taxPercent;
  final t = taxPct;
  final gstPctStr = (t != null && t > 0)
      ? '${t.toStringAsFixed(t == t.roundToDouble() ? 0 : 2)}%'
      : '—';

  final u = unitLabel.trim().isEmpty ? 'unit' : unitLabel.trim();
  final enteredPurchaseLine =
      '${_fmtQty(qty)} $u × ${_money(enteredPurchaseDisplay)} (${_basisLabel(purchaseBasis)})';

  String? sellingLine;
  if (hasSelling && enteredSellingDisplay != null) {
    sellingLine =
        'Selling ${_money(enteredSellingDisplay)} (${_basisLabel(sellBasis)}) — normalized like purchase for save';
  }

  String? profitLine;
  if (hasSelling && qty > 0) {
    profitLine = 'Profit (estimate) ${_money(profitPreview)}';
  } else {
    profitLine = 'Profit — enter selling to see margin';
  }

  final gstLine = gst > 1e-9
      ? 'GST $gstPctStr on line = ${_money(gst)}'
      : (t != null && t > 0
          ? 'GST $gstPctStr on line = ${_money(0)}'
          : 'GST — enter Tax % or set GST mode');

  String? chargesLine;
  if (!omitLineFreight && charges > 1e-9) {
    chargesLine =
        'Freight / delivered / billty on this line = ${_money(charges)}';
  }

  return PurchaseLinePreviewModel(
    enteredPurchaseLine: enteredPurchaseLine,
    taxableLine:
        'Taxable (after line discount) ${_money(taxable)}',
    gstLine: gstLine,
    linePurchaseLine:
        'Line purchase (incl. GST) ${_money(purchaseIncl)}',
    chargesLine: chargesLine,
    sellingLine: sellingLine,
    profitLine: profitLine,
  );
}

String _fmtQty(double q) {
  if ((q - q.roundToDouble()).abs() < 1e-6) return q.round().toString();
  return q.toStringAsFixed(q >= 100 ? 0 : 2);
}
