import 'package:flutter/foundation.dart';

/// API-aligned: `included` or `separate`.
@immutable
class PurchaseDraft {
  const PurchaseDraft({
    this.supplierId,
    this.supplierName,
    this.brokerId,
    this.brokerName,
    this.brokerIdFromSupplier,
    this.purchaseDate,
    this.invoiceNumber,
    this.paymentDays,
    this.headerDiscountPercent,
    this.commissionPercent,
    this.deliveredRate,
    this.billtyRate,
    this.freightAmount,
    this.freightType = 'separate',
    this.lines = const <PurchaseLineDraft>[],
  });

  final String? supplierId;
  final String? supplierName;
  final String? brokerId;
  final String? brokerName;
  /// Set when default came from selected supplier; used for broker label only.
  final String? brokerIdFromSupplier;
  final DateTime? purchaseDate;
  final String? invoiceNumber;
  final int? paymentDays;
  final double? headerDiscountPercent;
  final double? commissionPercent;
  final double? deliveredRate;
  final double? billtyRate;
  final double? freightAmount;
  final String freightType;
  final List<PurchaseLineDraft> lines;

  static PurchaseDraft initial() => PurchaseDraft(
        purchaseDate: DateTime.now(),
        supplierId: null,
        supplierName: null,
        brokerId: null,
        brokerName: null,
        brokerIdFromSupplier: null,
        invoiceNumber: null,
        paymentDays: null,
        headerDiscountPercent: null,
        commissionPercent: null,
        deliveredRate: null,
        billtyRate: null,
        freightAmount: null,
        freightType: 'separate',
        lines: const [],
      );

  PurchaseDraft copyWith({
    String? supplierId,
    String? supplierName,
    bool clearSupplier = false,
    String? brokerId,
    String? brokerName,
    bool clearBroker = false,
    String? brokerIdFromSupplier,
    bool clearBrokerFromSupplier = false,
    DateTime? purchaseDate,
    String? invoiceNumber,
    bool clearInvoice = false,
    int? paymentDays,
    bool clearPaymentDays = false,
    double? headerDiscountPercent,
    bool clearHeaderDiscount = false,
    double? commissionPercent,
    bool clearCommission = false,
    double? deliveredRate,
    bool clearDelivered = false,
    double? billtyRate,
    bool clearBillty = false,
    double? freightAmount,
    bool clearFreight = false,
    String? freightType,
    List<PurchaseLineDraft>? lines,
  }) {
    return PurchaseDraft(
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName: clearSupplier ? null : (supplierName ?? this.supplierName),
      brokerId: clearBroker ? null : (brokerId ?? this.brokerId),
      brokerName: clearBroker ? null : (brokerName ?? this.brokerName),
      brokerIdFromSupplier: clearBrokerFromSupplier
          ? null
          : (brokerIdFromSupplier ?? this.brokerIdFromSupplier),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      invoiceNumber: clearInvoice ? null : (invoiceNumber ?? this.invoiceNumber),
      paymentDays: clearPaymentDays ? null : (paymentDays ?? this.paymentDays),
      headerDiscountPercent: clearHeaderDiscount
          ? null
          : (headerDiscountPercent ?? this.headerDiscountPercent),
      commissionPercent:
          clearCommission ? null : (commissionPercent ?? this.commissionPercent),
      deliveredRate: clearDelivered ? null : (deliveredRate ?? this.deliveredRate),
      billtyRate: clearBillty ? null : (billtyRate ?? this.billtyRate),
      freightAmount: clearFreight ? null : (freightAmount ?? this.freightAmount),
      freightType: freightType ?? this.freightType,
      lines: lines ?? this.lines,
    );
  }
}

@immutable
class PurchaseLineDraft {
  const PurchaseLineDraft({
    this.catalogItemId,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.landingCost,
    this.kgPerUnit,
    this.landingCostPerKg,
    this.sellingPrice,
    this.taxPercent,
    this.lineDiscountPercent,
    this.hsnCode,
  });

  final String? catalogItemId;
  final String itemName;
  final double qty;
  final String unit;
  /// Per *line* unit when not using explicit kg fields, or derived `kg_per_unit * landing_cost_per_kg` for weight lines.
  final double landingCost;
  /// Snapshot: kg per bag/sack when [unit] is bag/sack.
  final double? kgPerUnit;
  /// Rupees per kg when [kgPerUnit] is set.
  final double? landingCostPerKg;
  final double? sellingPrice;
  final double? taxPercent;
  final double? lineDiscountPercent;
  /// Carried for GST lines; from catalog or edited purchase line.
  final String? hsnCode;

  Map<String, dynamic> toLineMap() {
    final m = <String, dynamic>{
      'item_name': itemName,
      'qty': qty,
      'unit': unit,
      'landing_cost': landingCost,
    };
    if (catalogItemId != null && catalogItemId!.isNotEmpty) {
      m['catalog_item_id'] = catalogItemId;
    }
    if (kgPerUnit != null) m['kg_per_unit'] = kgPerUnit;
    if (landingCostPerKg != null) m['landing_cost_per_kg'] = landingCostPerKg;
    if (sellingPrice != null) m['selling_cost'] = sellingPrice;
    if (taxPercent != null) m['tax_percent'] = taxPercent;
    if (lineDiscountPercent != null) m['discount'] = lineDiscountPercent;
    if (hsnCode != null && hsnCode!.trim().isNotEmpty) {
      m['hsn_code'] = hsnCode!.trim();
    }
    return m;
  }

  static PurchaseLineDraft fromLineMap(Map<String, dynamic> e) {
    final rawHsn = e['hsn_code']?.toString().trim() ?? '';
    return PurchaseLineDraft(
      catalogItemId: e['catalog_item_id']?.toString(),
      itemName: e['item_name']?.toString() ?? '',
      qty: (e['qty'] as num?)?.toDouble() ?? 0,
      unit: e['unit']?.toString() ?? 'kg',
      landingCost: (e['landing_cost'] as num?)?.toDouble() ?? 0,
      kgPerUnit: (e['kg_per_unit'] as num?)?.toDouble(),
      landingCostPerKg: (e['landing_cost_per_kg'] as num?)?.toDouble(),
      sellingPrice: (e['selling_cost'] as num?)?.toDouble(),
      taxPercent: (e['tax_percent'] as num?)?.toDouble(),
      lineDiscountPercent: (e['discount'] as num?)?.toDouble(),
      hsnCode: rawHsn.isEmpty ? null : rawHsn,
    );
  }
}

bool _isBagOrSackUnit(String unit) {
  final x = unit.trim().toLowerCase();
  return x == 'bag' || x == 'sack';
}

/// First validation failure for [l] that would also fail API line rules, or null
/// when the line is save-ready (aligned with [TradePurchase] create/update).
String? purchaseLineSaveBlockReason(PurchaseLineDraft l) {
  if ((l.catalogItemId ?? '').trim().isEmpty) {
    return 'Pick the item from the list (free-typed items cannot be saved).';
  }
  if (l.itemName.trim().isEmpty) {
    return 'Item name is required.';
  }
  if (l.unit.trim().isEmpty) {
    return 'Unit is required.';
  }
  if (l.qty <= 0) {
    return 'Quantity must be greater than 0.';
  }
  final kpu = l.kgPerUnit;
  final pk = l.landingCostPerKg;
  final weightLine = kpu != null || pk != null;
  final unitIsBagSack = _isBagOrSackUnit(l.unit);
  if (weightLine || unitIsBagSack) {
    if (kpu == null || kpu <= 0) {
      return unitIsBagSack
          ? 'Kg per bag/sack is required for this unit.'
          : 'Kg per unit must be greater than 0.';
    }
    if (pk == null || pk <= 0) {
      return 'Per-kg cost must be greater than 0.';
    }
  } else if (l.landingCost <= 0) {
    return 'Landing cost must be greater than 0.';
  }
  final tax = l.taxPercent ?? 0;
  if (tax > 0 || unitIsBagSack) {
    if ((l.hsnCode ?? '').trim().isEmpty) {
      return 'HSN is required when the line has tax or the unit is bag/sack.';
    }
  }
  return null;
}

/// True when qty, name, unit, and money inputs match API rules for saved lines.
bool purchaseLineIsValidForSave(PurchaseLineDraft l) =>
    purchaseLineSaveBlockReason(l) == null;

/// Strict footer / invoice-style row breakdown (mirrors prior wizard `\_strictFooterBreakdown`).
@immutable
class PurchaseStrictBreakdown {
  const PurchaseStrictBreakdown({
    required this.subtotalGross,
    required this.taxTotal,
    required this.discountTotal,
    required this.freight,
    required this.commission,
    required this.grand,
  });
  final double subtotalGross;
  final double taxTotal;
  final double discountTotal;
  final double freight;
  final double commission;
  final double grand;
}
