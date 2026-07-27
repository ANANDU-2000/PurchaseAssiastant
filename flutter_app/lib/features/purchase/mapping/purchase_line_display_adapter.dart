import '../../../core/models/trade_purchase_models.dart';
import '../domain/purchase_draft.dart';

/// Minimal [TradePurchaseLine] for label/rate display helpers (wizard recap, etc.).
TradePurchaseLine tradeLineForDisplay(
  PurchaseLineDraft d, {
  Map<String, dynamic>? rateContext,
}) {
  return TradePurchaseLine(
    id: '',
    itemName: d.itemName,
    qty: d.qty,
    unit: d.unit,
    landingCost: d.landingCost,
    sellingCost: d.sellingPrice,
    kgPerUnit: d.kgPerUnit,
    landingCostPerKg: d.landingCostPerKg,
    taxPercent: d.taxPercent,
    discount: d.lineDiscountPercent,
    boxMode: d.boxMode,
    itemsPerBox: d.itemsPerBox,
    weightPerItem: d.weightPerItem,
    kgPerBox: d.kgPerBox,
    weightPerTin: d.weightPerTin,
    rateContext: rateContext,
  );
}
