import '../../../core/models/trade_purchase_models.dart';
import '../domain/purchase_draft.dart';

/// Party/terms header from a list or detail row — lines may be empty when
/// `include_lines=false` on history API; full edit still fetches lines.
PurchaseDraft purchaseDraftHeaderFromTradePurchase(TradePurchase p) {
  final cm = PurchaseDraft.normalizeCommissionMode(p.commissionMode);
  final lines = <PurchaseLineDraft>[
    for (final l in p.lines)
      PurchaseLineDraft(
        catalogItemId: l.catalogItemId,
        itemName: l.itemName,
        qty: l.qty,
        unit: l.unit,
        landingCost: l.purchaseRate ?? l.landingCost,
        kgPerUnit: l.kgPerUnit,
        landingCostPerKg: l.landingCostPerKg,
        sellingPrice: l.sellingRate ?? l.sellingCost,
        taxPercent: l.taxPercent,
        lineDiscountPercent: l.discount,
        freightType: l.freightType,
        freightValue: l.freightValue,
        deliveredRate: l.deliveredRate,
        billtyRate: l.billtyRate,
        boxMode: l.boxMode,
        itemsPerBox: l.itemsPerBox,
        weightPerItem: l.weightPerItem,
        kgPerBox: l.kgPerBox,
        weightPerTin: l.weightPerTin,
        hsnCode: l.hsnCode,
        itemCode: l.itemCode,
        description: l.description,
      ),
  ];
  var ft = 'separate';
  final sft = p.freightType?.trim().toLowerCase();
  if (sft == 'included' || sft == 'separate') ft = sft!;

  return PurchaseDraft(
    supplierId: p.supplierId,
    supplierName: p.supplierName,
    brokerId: p.brokerId,
    brokerName: p.brokerName,
    brokerIdFromSupplier: p.brokerId,
    purchaseDate: p.purchaseDate,
    invoiceNumber: p.invoiceNumber,
    paymentDays: p.paymentDays,
    headerDiscountPercent: p.discount,
    commissionMode: cm,
    commissionPercent: cm == kPurchaseCommissionModePercent ? p.commissionPercent : null,
    commissionMoney: cm != kPurchaseCommissionModePercent ? p.commissionMoney : null,
    deliveredRate: p.deliveredRate,
    billtyRate: p.billtyRate,
    freightAmount: p.freightAmount,
    freightType: ft,
    lines: lines,
  );
}
