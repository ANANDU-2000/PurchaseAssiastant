import 'package:intl/intl.dart';

import '../../../../../core/calc_engine.dart';

final _inr0 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _inr2 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

String _rupee(num n, {bool decimals = false}) =>
    decimals ? _inr2.format(n) : _inr0.format(n);

String _fmtQty(double q) {
  if ((q - q.roundToDouble()).abs() < 1e-6) return q.round().toString();
  return q.toStringAsFixed(q >= 100 ? 0 : 2);
}

/// Short trader-facing preview lines (no “taxable”, “normalized”, etc.).
List<String> buildTraderPurchasePreviewLines({
  required String qtySummaryLine,
  required TradeCalcLine line,
  required bool taxOn,
  required double qty,
  required String unitWord,
  required bool ratesPerKgEconomics,
  required bool rateFieldsPerKg,
  required double enteredPurchaseDisplay,
  required double? kgPer,
  required double? enteredSellingDisplay,
  required bool omitLineFreight,
  required double profitPreview,
}) {
  final u = unitWord.trim().isEmpty ? 'unit' : unitWord.trim();

  String purchaseLine;
  if (ratesPerKgEconomics) {
    final k = kgPer ?? 0;
    if (k > 0 && qty > 0) {
      final kgTot = qty * k;
      if (rateFieldsPerKg) {
        purchaseLine =
            '${_rupee(enteredPurchaseDisplay, decimals: true)}/kg × ${_fmtQty(kgTot)} kg';
      } else {
        purchaseLine =
            '${_rupee(enteredPurchaseDisplay, decimals: true)}/bag × ${_fmtQty(qty)} $u';
      }
    } else {
      purchaseLine =
          '${_rupee(enteredPurchaseDisplay, decimals: true)} × ${_fmtQty(qty)} $u';
    }
  } else {
    purchaseLine =
        '${_rupee(enteredPurchaseDisplay, decimals: true)} × ${_fmtQty(qty)} $u';
  }

  final gst = lineTaxAmount(line);
  final taxLine = !taxOn || gst <= 1e-6 ? 'Tax —' : 'Tax ${_rupee(gst, decimals: true)}';

  final total = lineMoney(line);
  final charges =
      omitLineFreight ? 0.0 : lineItemFreightCharges(line);
  final totalLine = charges > 1e-6
      ? 'Total ${_rupee(total, decimals: true)} (incl. line charges)'
      : 'Total ${_rupee(total, decimals: true)}';

  String profitLine;
  if (enteredSellingDisplay != null &&
      enteredSellingDisplay > 0 &&
      qty > 0) {
    profitLine = 'Profit ${_rupee(profitPreview, decimals: true)}';
  } else {
    profitLine = 'Profit — add selling';
  }

  return <String>[
    qtySummaryLine,
    purchaseLine,
    taxLine,
    totalLine,
    profitLine,
  ];
}
