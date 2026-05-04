import '../models/trade_purchase_models.dart';

/// Document title string for purchase PDFs (single source for tests + layout).
const String kPurchaseOrderPdfTitle = 'PURCHASE ORDER';

/// Weight-priced line: qty × kg_per_unit × landing_cost_per_kg.
bool tradePurchaseLineIsWeightPriced(TradePurchaseLine l) {
  final a = l.kgPerUnit;
  final b = l.landingCostPerKg;
  return a != null && b != null && a > 0 && b > 0;
}

/// Purchase rate for display: ₹/kg when weight-priced, else per line unit.
double tradePurchaseLineDisplayPurchaseRate(TradePurchaseLine l) {
  if (tradePurchaseLineIsWeightPriced(l)) {
    return l.landingCostPerKg!;
  }
  return l.landingCost;
}

/// Selling rate for display (per kg when weight-priced bag/sack math applies;
/// wire `selling_rate` / `selling_cost` may be per physical unit — divide by kg per unit).
/// For plain [unit] == kg lines, stored rate is per kg.
double? tradePurchaseLineDisplaySellingRate(TradePurchaseLine l) {
  final sp = l.sellingRate ?? l.sellingCost;
  if (sp == null || sp <= 0) return null;
  if (tradePurchaseLineIsWeightPriced(l)) {
    return sp / l.kgPerUnit!;
  }
  final u = l.unit.trim().toLowerCase();
  if (u == 'kg') return sp;
  return sp;
}
