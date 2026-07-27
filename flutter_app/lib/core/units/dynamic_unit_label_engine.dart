import '../models/trade_purchase_models.dart';

bool lineFieldsWeightPricedGross(
  TradePurchaseLine line,
) {
  final kpu = line.kgPerUnit;
  final lcpk = line.landingCostPerKg;
  if (kpu == null || lcpk == null || kpu <= 0 || lcpk <= 0) return false;
  final derived = kpu * lcpk;
  final landing = line.landingCost;
  return (derived - landing).abs() <= 0.05 + 1e-9;
}

/// Server [rate_context] when present; else same fallbacks as [effectiveRateContext].
Map<String, dynamic> effectiveRateContextFields({
  Map<String, dynamic>? rateContext,
  required String unit,
  double? kgPerUnit,
  double? landingCostPerKg,
}) {
  if (rateContext != null && rateContext.isNotEmpty) {
    return Map<String, dynamic>.from(rateContext);
  }
  final u = unit.trim().toLowerCase();
  String dim;
  if (u == 'bag' || u == 'sack') {
    dim = 'bag';
  } else if (u == 'kg' || u == 'kgs') {
    dim = 'kg';
  } else if (u == 'box') {
    dim = 'box';
  } else if (u == 'tin') {
    dim = 'tin';
  } else if (u == 'pcs' || u == 'piece' || u == 'pkt' || u == 'packet') {
    dim = 'pcs';
  } else {
    dim = u.isEmpty ? 'unit' : u;
  }
  final wp = kgPerUnit != null &&
      landingCostPerKg != null &&
      kgPerUnit > 0 &&
      landingCostPerKg > 0;
  return <String, dynamic>{
    'purchase_rate_dim': dim,
    'selling_rate_dim': dim,
    'qty_dim': dim,
    'weight_priced_gross': wp,
    'line_unit': unit,
  };
}

/// Server [rate_context] + fallbacks for user-visible unit strings (no money math).
Map<String, dynamic> effectiveRateContext(TradePurchaseLine line) {
  return effectiveRateContextFields(
    rateContext: line.rateContext,
    unit: line.unit,
    kgPerUnit: line.kgPerUnit,
    landingCostPerKg: line.landingCostPerKg,
  );
}

String _dimPretty(String dim) {
  switch (dim) {
    case 'bag':
      return 'bag';
    case 'kg':
      return 'kg';
    case 'box':
      return 'box';
    case 'tin':
      return 'tin';
    case 'pcs':
      return 'pcs';
    default:
      return dim;
  }
}

/// UI chip text for a rate dimension (e.g. `₹/bag`).
String rupeePerDimChipLabel(String dim) => '₹/${_dimPretty(dim)}';

String purchaseRateSuffix(TradePurchaseLine line) =>
    _dimPretty(effectiveRateContext(line)['purchase_rate_dim']?.toString() ?? 'unit');

String sellingRateSuffix(TradePurchaseLine line) =>
    _dimPretty(effectiveRateContext(line)['selling_rate_dim']?.toString() ?? 'unit');

String qtySuffix(TradePurchaseLine line) =>
    _dimPretty(effectiveRateContext(line)['qty_dim']?.toString() ?? line.unit);

String purchaseRateFieldLabel(TradePurchaseLine line) =>
    'Purchase Rate (₹/${purchaseRateSuffix(line)})';

String sellingRateFieldLabel(TradePurchaseLine line) =>
    'Selling Rate (₹/${sellingRateSuffix(line)})';

String weightSummaryLabel(TradePurchaseLine line) {
  final rc = effectiveRateContext(line);
  final gross = rc['weight_priced_gross'] == true || lineFieldsWeightPricedGross(line);
  if (gross && line.kgPerUnit != null && line.kgPerUnit! > 0) {
    return 'Weight (kg)';
  }
  return 'Weight';
}

String profitFieldLabel() => 'Profit (₹)';
