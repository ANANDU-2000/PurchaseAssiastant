import '../calc_engine.dart';
import '../models/trade_purchase_models.dart';

/// Single line rupees (tax-inclusive), same as wizard / reports line math.
double tradePurchaseLineSumForLine(TradePurchaseLine l) {
  return lineMoney(
    TradeCalcLine(
      qty: l.qty,
      landingCost: l.landingCost,
      kgPerUnit: l.kgPerUnit,
      landingCostPerKg: l.landingCostPerKg,
      taxPercent: l.taxPercent,
      discountPercent: l.discount,
    ),
  );
}

/// Commission amount matching backend [compute_totals] / PDF footer:
/// applies header discount to line sum, then `commission_percent` of that base.
double tradePurchaseCommissionInr(TradePurchase p) {
  final c = p.commissionPercent;
  if (c == null || c <= 0) return 0;
  var linesTotal = 0.0;
  for (final l in p.lines) {
    linesTotal += tradePurchaseLineSumForLine(l);
  }
  var hd = p.discount ?? 0;
  if (hd > 100) hd = 100;
  final afterHeader = linesTotal * (1.0 - hd / 100.0);
  var cp = c;
  if (cp > 100) cp = 100;
  return afterHeader * cp / 100.0;
}

/// Allocates header [tradePurchaseCommissionInr] across lines by each line's
/// tax-inclusive amount share (weights match [tradePurchaseLineSumForLine]).
double tradePurchaseLineCommissionInr(TradePurchase p, TradePurchaseLine l) {
  final total = tradePurchaseCommissionInr(p);
  if (total <= 0) return 0;
  var sum = 0.0;
  for (final x in p.lines) {
    sum += tradePurchaseLineSumForLine(x);
  }
  if (sum <= 0) return 0;
  final share = tradePurchaseLineSumForLine(l) / sum;
  return total * share;
}
