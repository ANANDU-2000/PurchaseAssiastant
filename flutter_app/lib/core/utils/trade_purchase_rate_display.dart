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
  // For bag-family lines, wire selling rate is frequently stored as per-bag.
  // Display must be per-kg when we have kg-per-unit, to avoid showing S ₹1350
  // instead of S ₹27/kg.
  if ((u == 'bag' || u == 'sack' || u == 'box' || u == 'tin') &&
      l.kgPerUnit != null &&
      l.kgPerUnit! > 0) {
    return sp / l.kgPerUnit!;
  }
  return sp;
}

/// UI suffix for [tradePurchaseLineDisplaySellingRate] (e.g. `/kg` vs `/bag`).
bool tradePurchaseLineDisplaySellingRateIsPerKg(TradePurchaseLine l) {
  if (tradePurchaseLineIsWeightPriced(l)) return true;
  final u = l.unit.trim().toLowerCase();
  if (u == 'kg' || u == 'kgs') return true;
  if ((u == 'bag' || u == 'sack' || u == 'box' || u == 'tin') &&
      l.kgPerUnit != null &&
      l.kgPerUnit! > 0) {
    return true;
  }
  return false;
}

/// UI qualifier for ledger / intel lines (e.g. `/kg`, `/bag`).
String ledgerPurchaseRateDisplayDim(TradePurchaseLine l) {
  final u = l.unit.trim().toLowerCase();
  final kpu = l.kgPerUnit;
  final lck = l.landingCostPerKg;
  final weightPriced = kpu != null &&
      kpu > 0 &&
      lck != null &&
      lck > 0;
  if (weightPriced || u == 'kg' || u == 'kgs') return 'kg';
  if (u.isNotEmpty) return u;
  return '';
}

String ledgerSellingRateDisplayDim(TradePurchaseLine l) {
  if (tradePurchaseLineDisplaySellingRateIsPerKg(l)) return 'kg';
  final u = l.unit.trim().toLowerCase();
  if (u.isNotEmpty) return u;
  return '';
}
