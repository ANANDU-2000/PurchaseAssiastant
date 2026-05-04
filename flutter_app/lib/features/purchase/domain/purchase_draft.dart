import 'package:flutter/foundation.dart';

import '../../../core/strict_decimal.dart';

double _decimalToDouble(Object? value) {
  if (value == null) return 0;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return 0;
  }
}

double? _decimalToNullableDouble(Object? value) {
  if (value == null) return null;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return null;
  }
}

String _fixed(Object value, int scale) =>
    StrictDecimal.fromObject(value).format(scale);

/// API `commission_mode` values (broker header).
const String kPurchaseCommissionModePercent = 'percent';
const String kPurchaseCommissionModeFlatInvoice = 'flat_invoice';
const String kPurchaseCommissionModeFlatKg = 'flat_kg';
const String kPurchaseCommissionModeFlatBag = 'flat_bag';
const String kPurchaseCommissionModeFlatTin = 'flat_tin';

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
    this.commissionMode = kPurchaseCommissionModePercent,
    this.commissionPercent,
    this.commissionMoney,
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
  final String commissionMode;
  final double? commissionPercent;
  final double? commissionMoney;
  final double? deliveredRate;
  final double? billtyRate;
  final double? freightAmount;
  final String freightType;
  final List<PurchaseLineDraft> lines;

  static String normalizeCommissionMode(String? raw) {
    final m = (raw ?? kPurchaseCommissionModePercent).trim().toLowerCase();
    switch (m) {
      case kPurchaseCommissionModeFlatInvoice:
      case kPurchaseCommissionModeFlatKg:
      case kPurchaseCommissionModeFlatBag:
      case kPurchaseCommissionModeFlatTin:
        return m;
      default:
        return kPurchaseCommissionModePercent;
    }
  }

  /// Replaces broker commission header fields (null-safe for API modes).
  PurchaseDraft withCommissionHeader({
    required String mode,
    double? percent,
    double? money,
  }) {
    final m = normalizeCommissionMode(mode);
    return PurchaseDraft(
      supplierId: supplierId,
      supplierName: supplierName,
      brokerId: brokerId,
      brokerName: brokerName,
      brokerIdFromSupplier: brokerIdFromSupplier,
      purchaseDate: purchaseDate,
      invoiceNumber: invoiceNumber,
      paymentDays: paymentDays,
      headerDiscountPercent: headerDiscountPercent,
      commissionMode: m,
      commissionPercent: m == kPurchaseCommissionModePercent ? percent : null,
      commissionMoney: m == kPurchaseCommissionModePercent ? null : money,
      deliveredRate: deliveredRate,
      billtyRate: billtyRate,
      freightAmount: freightAmount,
      freightType: freightType,
      lines: lines,
    );
  }

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
        commissionMode: kPurchaseCommissionModePercent,
        commissionPercent: null,
        commissionMoney: null,
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
    String? commissionMode,
    double? commissionPercent,
    bool clearCommission = false,
    double? commissionMoney,
    bool clearCommissionMoney = false,
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
      commissionMode: clearCommission
          ? kPurchaseCommissionModePercent
          : (commissionMode ?? this.commissionMode),
      commissionPercent:
          clearCommission ? null : (commissionPercent ?? this.commissionPercent),
      commissionMoney: clearCommission || clearCommissionMoney
          ? null
          : (commissionMoney ?? this.commissionMoney),
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
    this.freightType,
    this.freightValue,
    this.deliveredRate,
    this.billtyRate,
    this.boxMode,
    this.itemsPerBox,
    this.weightPerItem,
    this.kgPerBox,
    this.weightPerTin,
    this.hsnCode,
    this.itemCode,
    this.description,
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
  final String? freightType;
  final double? freightValue;
  final double? deliveredRate;
  final double? billtyRate;
  final String? boxMode;
  final double? itemsPerBox;
  final double? weightPerItem;
  final double? kgPerBox;
  final double? weightPerTin;
  /// Carried for GST lines; from catalog or edited purchase line.
  final String? hsnCode;
  final String? itemCode;
  final String? description;

  Map<String, dynamic> toLineMap() {
    final m = <String, dynamic>{
      'item_name': itemName,
      'qty': _fixed(qty, 3),
      'unit': unit,
      'purchase_rate': _fixed(landingCost, 2),
      'landing_cost': _fixed(landingCost, 2),
    };
    if (catalogItemId != null && catalogItemId!.isNotEmpty) {
      m['catalog_item_id'] = catalogItemId;
    }
    if (kgPerUnit != null) {
      m['weight_per_unit'] = _fixed(kgPerUnit!, 3);
      m['kg_per_unit'] = _fixed(kgPerUnit!, 3);
    }
    if (landingCostPerKg != null) {
      m['landing_cost_per_kg'] = _fixed(landingCostPerKg!, 2);
    }
    if (sellingPrice != null) {
      m['selling_rate'] = _fixed(sellingPrice!, 2);
      m['selling_cost'] = _fixed(sellingPrice!, 2);
    }
    if (freightType == 'included' || freightType == 'separate') {
      m['freight_type'] = freightType;
    }
    if (freightValue != null) m['freight_value'] = _fixed(freightValue!, 2);
    if (deliveredRate != null) m['delivered_rate'] = _fixed(deliveredRate!, 2);
    if (billtyRate != null) m['billty_rate'] = _fixed(billtyRate!, 2);
    if (boxMode != null && boxMode!.trim().isNotEmpty) m['box_mode'] = boxMode;
    if (itemsPerBox != null) m['items_per_box'] = _fixed(itemsPerBox!, 3);
    if (weightPerItem != null) m['weight_per_item'] = _fixed(weightPerItem!, 3);
    if (kgPerBox != null) m['kg_per_box'] = _fixed(kgPerBox!, 3);
    if (weightPerTin != null) m['weight_per_tin'] = _fixed(weightPerTin!, 3);
    if (taxPercent != null) m['tax_percent'] = _fixed(taxPercent!, 2);
    if (lineDiscountPercent != null) {
      m['discount'] = _fixed(lineDiscountPercent!, 2);
    }
    if (hsnCode != null && hsnCode!.trim().isNotEmpty) {
      m['hsn_code'] = hsnCode!.trim();
    }
    if (itemCode != null && itemCode!.trim().isNotEmpty) {
      m['item_code'] = itemCode!.trim();
    }
    final descOut = description?.trim() ?? '';
    if (descOut.isNotEmpty) m['description'] = descOut;
    return m;
  }

  static PurchaseLineDraft fromLineMap(Map<String, dynamic> e) {
    final rawHsn = e['hsn_code']?.toString().trim() ?? '';
    final rawIc = e['item_code']?.toString().trim() ?? '';
    final rawDesc = e['description']?.toString().trim() ?? '';
    return PurchaseLineDraft(
      catalogItemId: e['catalog_item_id']?.toString(),
      itemName: e['item_name']?.toString() ?? '',
      qty: _decimalToDouble(e['qty']),
      unit: e['unit']?.toString() ?? 'kg',
      landingCost: _decimalToDouble(e['purchase_rate'] ?? e['landing_cost']),
      kgPerUnit: _decimalToNullableDouble(e['weight_per_unit'] ?? e['kg_per_unit']),
      landingCostPerKg: _decimalToNullableDouble(e['landing_cost_per_kg']),
      sellingPrice: _decimalToNullableDouble(e['selling_rate'] ?? e['selling_cost']),
      taxPercent: _decimalToNullableDouble(e['tax_percent']),
      lineDiscountPercent: _decimalToNullableDouble(e['discount']),
      freightType: e['freight_type']?.toString(),
      freightValue: _decimalToNullableDouble(e['freight_value'] ?? e['freight_amount']),
      deliveredRate: _decimalToNullableDouble(e['delivered_rate']),
      billtyRate: _decimalToNullableDouble(e['billty_rate']),
      boxMode: e['box_mode']?.toString(),
      itemsPerBox: _decimalToNullableDouble(e['items_per_box']),
      weightPerItem: _decimalToNullableDouble(e['weight_per_item']),
      kgPerBox: _decimalToNullableDouble(e['kg_per_box']),
      weightPerTin: _decimalToNullableDouble(e['weight_per_tin']),
      hsnCode: rawHsn.isEmpty ? null : rawHsn,
      itemCode: rawIc.isEmpty ? null : rawIc,
      description: rawDesc.isEmpty ? null : rawDesc,
    );
  }
}

bool _isBagOrSackUnit(String unit) {
  final x = unit.trim().toLowerCase();
  return x == 'bag' || x == 'sack';
}

bool _isBoxUnit(String unit) => unit.trim().toLowerCase() == 'box';
bool _isTinUnit(String unit) => unit.trim().toLowerCase() == 'tin';

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
  final unitIsBox = _isBoxUnit(l.unit);
  final unitIsTin = _isTinUnit(l.unit);
  if (unitIsBox) {
    final hasItemsBox = (l.itemsPerBox ?? 0) > 0 && (l.weightPerItem ?? 0) > 0;
    final hasFixedBox = (l.kgPerBox ?? 0) > 0 || (l.kgPerUnit ?? 0) > 0;
    if (!hasItemsBox && !hasFixedBox) {
      return 'Add items per box + item weight, or fixed kg per box.';
    }
  }
  if (unitIsTin && !((l.weightPerTin ?? 0) > 0 || (l.kgPerUnit ?? 0) > 0)) {
    return 'Add weight per tin.';
  }
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
