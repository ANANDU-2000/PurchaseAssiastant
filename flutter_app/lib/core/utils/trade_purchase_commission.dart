import '../calc_engine.dart';
import '../models/trade_purchase_models.dart';
import '../strict_decimal.dart';

/// Single line rupees (tax-inclusive) plus line freight/delivered/billty when
/// [lineTotal] is absent (matches backend roll-up for commission basis).
double tradePurchaseLineSumForLine(TradePurchaseLine l) {
  if (l.lineTotal != null) return l.lineTotal!;
  final li = TradeCalcLine(
    qty: l.qty,
    landingCost: l.landingCost,
    kgPerUnit: l.kgPerUnit,
    landingCostPerKg: l.landingCostPerKg,
    taxPercent: l.taxPercent,
    discountPercent: l.discount,
    freightType: l.freightType,
    freightValue: l.freightValue,
    deliveredRate: l.deliveredRate,
    billtyRate: l.billtyRate,
  );
  return lineMoney(li) + lineItemFreightCharges(li);
}

TradeCommissionLine _tradeLineToCommissionBasis(TradePurchaseLine l) {
  return TradeCommissionLine(
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    kgPerUnit: l.kgPerUnit,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  );
}

/// Broker commission rupees (matches backend `compute_totals` / [computeTradeTotals]).
double tradePurchaseCommissionInr(TradePurchase p) {
  var linesTotal = 0.0;
  for (final l in p.lines) {
    linesTotal += tradePurchaseLineSumForLine(l);
  }
  var hd = p.discount ?? 0;
  if (hd > 100) hd = 100;
  final afterHeader = linesTotal * (1.0 - hd / 100.0);
  return headerCommissionAddOnDecimal(
    commissionMode: p.commissionMode,
    afterHeader: StrictDecimal.fromObject(afterHeader),
    commissionPercent: p.commissionPercent != null
        ? StrictDecimal.fromObject(p.commissionPercent!)
        : null,
    commissionMoney: p.commissionMoney != null
        ? StrictDecimal.fromObject(p.commissionMoney!)
        : null,
    basisLines: [for (final l in p.lines) _tradeLineToCommissionBasis(l)],
  ).toDouble();
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
