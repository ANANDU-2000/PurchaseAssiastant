import 'package:flutter/material.dart';

import '../json_coerce.dart';
import '../strict_decimal.dart';
import '../theme/hexa_colors.dart';

double _decDouble(Object? value) {
  if (value == null) return 0;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return 0;
  }
}

double? _decNullableDouble(Object? value) {
  if (value == null) return null;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return null;
  }
}

Map<String, dynamic>? _mapFromDynamic(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

/// Mirrors backend lifecycle + [parsePurchaseStatus].
enum PurchaseStatus {
  draft,
  saved,
  confirmed,
  partiallyPaid,
  paid,
  overdue,
  dueSoon,
  cancelled,
  deleted,
  unknown,
}

extension PurchaseStatusX on PurchaseStatus {
  String get apiValue => switch (this) {
        PurchaseStatus.draft => 'draft',
        PurchaseStatus.saved => 'saved',
        PurchaseStatus.confirmed => 'confirmed',
        PurchaseStatus.partiallyPaid => 'partially_paid',
        PurchaseStatus.paid => 'paid',
        PurchaseStatus.overdue => 'overdue',
        PurchaseStatus.dueSoon => 'due_soon',
        PurchaseStatus.cancelled => 'cancelled',
        PurchaseStatus.deleted => 'deleted',
        PurchaseStatus.unknown => 'unknown',
      };

  String get label => switch (this) {
        PurchaseStatus.draft => 'Draft',
        PurchaseStatus.saved => 'Saved',
        PurchaseStatus.confirmed => 'Pending',
        PurchaseStatus.partiallyPaid => 'Partial',
        PurchaseStatus.paid => 'Paid',
        PurchaseStatus.overdue => 'Overdue',
        PurchaseStatus.dueSoon => 'Due soon',
        PurchaseStatus.cancelled => 'Cancelled',
        PurchaseStatus.deleted => 'Deleted',
        PurchaseStatus.unknown => '—',
      };

  Color get color => switch (this) {
        PurchaseStatus.paid => HexaColors.brandAccent,
        PurchaseStatus.overdue => HexaColors.loss,
        PurchaseStatus.dueSoon => const Color(0xFFF59E0B),
        PurchaseStatus.partiallyPaid => const Color(0xFFF59E0B),
        PurchaseStatus.draft => HexaColors.neutral,
        PurchaseStatus.saved => HexaColors.neutral,
        PurchaseStatus.confirmed => HexaColors.profit,
        PurchaseStatus.cancelled => HexaColors.loss,
        PurchaseStatus.deleted => HexaColors.neutral,
        PurchaseStatus.unknown => HexaColors.neutral,
      };

}

PurchaseStatus parsePurchaseStatus(String? raw) {
  final s = (raw ?? '').toLowerCase().trim();
  return switch (s) {
    'draft' => PurchaseStatus.draft,
    'saved' => PurchaseStatus.saved,
    'confirmed' => PurchaseStatus.confirmed,
    'partially_paid' => PurchaseStatus.partiallyPaid,
    'paid' => PurchaseStatus.paid,
    'overdue' => PurchaseStatus.overdue,
    'due_soon' => PurchaseStatus.dueSoon,
    'cancelled' => PurchaseStatus.cancelled,
    'deleted' => PurchaseStatus.deleted,
    _ => PurchaseStatus.unknown,
  };
}

class TradePurchaseLine {
  const TradePurchaseLine({
    required this.id,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.landingCost,
    this.purchaseRate,
    this.sellingRate,
    this.freightType,
    this.freightValue,
    this.deliveredRate,
    this.billtyRate,
    this.totalWeight,
    this.lineTotal,
    this.lineLandingGross,
    this.profit,
    this.sellingCost,
    this.discount,
    this.taxPercent,
    this.catalogItemId,
    this.hsnCode,
    this.itemCode,
    this.paymentDays,
    this.description,
    this.defaultUnit,
    this.defaultKgPerBag,
    this.defaultPurchaseUnit,
    this.kgPerUnit,
    this.landingCostPerKg,
    this.boxMode,
    this.itemsPerBox,
    this.weightPerItem,
    this.kgPerBox,
    this.weightPerTin,
    this.rateContext,
  });

  final String id;
  final String itemName;
  final double qty;
  final String unit;
  final double landingCost;
  final double? purchaseRate;
  final double? sellingRate;
  final String? freightType;
  final double? freightValue;
  final double? deliveredRate;
  final double? billtyRate;
  final double? totalWeight;
  /// Tax/discount-inclusive line purchase (API `line_total`); not pre-tax gross.
  final double? lineTotal;
  /// Pre-discount / pre-tax landing gross (API `line_landing_gross`).
  final double? lineLandingGross;
  final double? profit;
  /// When set, line was priced as qty × kg_per_unit × landing_cost_per_kg.
  final double? kgPerUnit;
  final double? landingCostPerKg;
  final double? sellingCost;
  final double? discount;
  final double? taxPercent;
  final String? catalogItemId;
  final String? hsnCode;
  final String? itemCode;
  final int? paymentDays;
  final String? description;
  /// From catalog when line is linked; used for BAG/kg display and edit wizard.
  final String? defaultUnit;
  final double? defaultKgPerBag;
  final String? defaultPurchaseUnit;
  final String? boxMode;
  final double? itemsPerBox;
  final double? weightPerItem;
  final double? kgPerBox;
  final double? weightPerTin;
  /// Server `rate_context` for labels (₹/bag vs ₹/kg); optional on older payloads.
  final Map<String, dynamic>? rateContext;

  factory TradePurchaseLine.fromJson(Map<String, dynamic> j) {
    return TradePurchaseLine(
      id: j['id']?.toString() ?? '',
      itemName: j['item_name']?.toString() ?? '',
      qty: _decDouble(j['qty']),
      unit: j['unit']?.toString() ?? '',
      landingCost: _decDouble(j['landing_cost'] ?? j['purchase_rate']),
      purchaseRate: _decNullableDouble(j['purchase_rate'] ?? j['landing_cost']),
      sellingRate: _decNullableDouble(j['selling_rate'] ?? j['selling_cost']),
      freightType: j['freight_type']?.toString(),
      freightValue: _decNullableDouble(j['freight_value'] ?? j['freight_amount']),
      deliveredRate: _decNullableDouble(j['delivered_rate']),
      billtyRate: _decNullableDouble(j['billty_rate']),
      totalWeight: _decNullableDouble(j['total_weight']),
      lineTotal: _decNullableDouble(j['line_total']),
      lineLandingGross: _decNullableDouble(j['line_landing_gross']),
      profit: _decNullableDouble(j['profit']),
      sellingCost: _decNullableDouble(j['selling_cost'] ?? j['selling_rate']),
      discount: _decNullableDouble(j['discount']),
      taxPercent: _decNullableDouble(j['tax_percent']),
      catalogItemId: j['catalog_item_id']?.toString(),
      hsnCode: j['hsn_code']?.toString(),
      itemCode: j['item_code']?.toString(),
      paymentDays: coerceToIntNullable(j['payment_days']),
      description: j['description']?.toString(),
      defaultUnit: j['default_unit']?.toString(),
      defaultKgPerBag: _decNullableDouble(j['default_kg_per_bag']),
      defaultPurchaseUnit: j['default_purchase_unit']?.toString(),
      kgPerUnit: _decNullableDouble(j['kg_per_unit'] ?? j['weight_per_unit']),
      landingCostPerKg: _decNullableDouble(j['landing_cost_per_kg']),
      boxMode: j['box_mode']?.toString(),
      itemsPerBox: _decNullableDouble(j['items_per_box']),
      weightPerItem: _decNullableDouble(j['weight_per_item']),
      kgPerBox: _decNullableDouble(j['kg_per_box']),
      weightPerTin: _decNullableDouble(j['weight_per_tin']),
      rateContext: _mapFromDynamic(j['rate_context']),
    );
  }

  /// Gross landing value for the line (pre-discount / pre-tax; matches backend `line_landing_gross`).
  double get landingGross {
    if (lineLandingGross != null) return lineLandingGross!;
    final landing = purchaseRate ?? landingCost;
    if (kgPerUnit != null &&
        landingCostPerKg != null &&
        kgPerUnit! > 0 &&
        landingCostPerKg! > 0) {
      final derived = kgPerUnit! * landingCostPerKg!;
      if ((derived - landing).abs() <= 0.05 + 1e-9) {
        return qty * kgPerUnit! * landingCostPerKg!;
      }
    }
    return qty * landing;
  }

  /// Gross selling when [sellingCost] is set (per-kg when weight line).
  double get sellingGross {
    final rate = sellingRate ?? sellingCost;
    if (rate == null) return 0;
    if (kgPerUnit != null &&
        landingCostPerKg != null &&
        kgPerUnit! > 0) {
      return qty * kgPerUnit! * rate;
    }
    return qty * rate;
  }

  /// Profit for this line when selling is recorded.
  double? get lineProfit {
    if (profit != null) return profit;
    if ((sellingRate ?? sellingCost) == null) return null;
    return sellingGross - landingGross;
  }
}

String _normTradePurchaseCommissionMode(String? raw) {
  final m = (raw ?? 'percent').trim().toLowerCase();
  switch (m) {
    case 'flat_invoice':
    case 'flat_kg':
    case 'flat_bag':
    case 'flat_box':
    case 'flat_tin':
      return m;
    default:
      return 'percent';
  }
}

class TradePurchase {
  TradePurchase({
    required this.id,
    required this.humanId,
    this.invoiceNumber,
    required this.purchaseDate,
    this.supplierId,
    this.brokerId,
    this.paymentDays,
    this.dueDate,
    required this.paidAmount,
    this.paidAt,
    required this.totalAmount,
    required this.storedStatus,
    required this.derivedStatus,
    required this.remaining,
    this.itemsCount = 0,
    this.supplierName,
    this.brokerName,
    this.supplierGst,
    this.supplierAddress,
    this.supplierPhone,
    this.supplierWhatsapp,
    this.brokerPhone,
    this.brokerLocation,
    this.brokerImageUrl,
    this.discount,
    this.commissionMode = 'percent',
    this.commissionPercent,
    this.commissionMoney,
    this.deliveredRate,
    this.billtyRate,
    this.freightAmount,
    this.freightType,
    this.lines = const [],
    this.createdAt,
    this.updatedAt,
    this.totalLandingSubtotal,
    this.totalSellingSubtotal,
    this.totalLineProfit,
    this.hasMissingDetails = false,
    this.isDelivered = false,
    this.deliveredAt,
    this.deliveryNotes,
  });

  final String id;
  final String humanId;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String? supplierId;
  final String? brokerId;
  final int? paymentDays;
  final DateTime? dueDate;
  final double paidAmount;
  final DateTime? paidAt;
  final double totalAmount;
  final String storedStatus;
  final String derivedStatus;
  final double remaining;
  final int itemsCount;
  final String? supplierName;
  final String? brokerName;
  final String? supplierGst;
  final String? supplierAddress;
  final String? supplierPhone;
  final String? supplierWhatsapp;
  final String? brokerPhone;
  final String? brokerLocation;
  final String? brokerImageUrl;
  final double? discount;
  final String commissionMode;
  final double? commissionPercent;
  final double? commissionMoney;
  final double? deliveredRate;
  final double? billtyRate;
  final double? freightAmount;
  final String? freightType;
  final List<TradePurchaseLine> lines;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double? totalLandingSubtotal;
  final double? totalSellingSubtotal;
  final double? totalLineProfit;
  final bool hasMissingDetails;
  final bool isDelivered;
  final DateTime? deliveredAt;
  final String? deliveryNotes;

  PurchaseStatus get statusEnum => parsePurchaseStatus(derivedStatus);

  String get itemsSummary {
    if (lines.isEmpty) return '';
    final names = lines.take(3).map((e) => e.itemName).join(', ');
    return lines.length > 3 ? '$names…' : names;
  }

  factory TradePurchase.fromJson(Map<String, dynamic> j) {
    DateTime? parseD(String? k) {
      final v = j[k]?.toString();
      if (v == null || v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    final linesRaw = j['lines'];
    final lines = <TradePurchaseLine>[];
    if (linesRaw is List) {
      for (final e in linesRaw) {
        if (e is Map) {
          lines.add(TradePurchaseLine.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    final pd = parseD('purchase_date') ??
        parseD('purchaseDate') ??
        DateTime.now();
    final cm = _normTradePurchaseCommissionMode(j['commission_mode']?.toString());
    final cPct = _decNullableDouble(j['commission_percent']);
    final cMoney = _decNullableDouble(j['commission_money']);

    return TradePurchase(
      id: j['id']?.toString() ?? '',
      humanId: j['human_id']?.toString() ?? j['humanId']?.toString() ?? '',
      invoiceNumber: j['invoice_number']?.toString(),
      purchaseDate: pd,
      supplierId: j['supplier_id']?.toString(),
      brokerId: j['broker_id']?.toString(),
      paymentDays: coerceToIntNullable(j['payment_days']),
      dueDate: parseD('due_date'),
      paidAmount: _decDouble(j['paid_amount']),
      paidAt: parseD('paid_at'),
      totalAmount: _decDouble(j['total_amount']),
      totalLandingSubtotal: _decNullableDouble(j['total_landing_subtotal']),
      totalSellingSubtotal: _decNullableDouble(j['total_selling_subtotal']),
      totalLineProfit: _decNullableDouble(j['total_line_profit']),
      storedStatus: j['status']?.toString() ?? 'confirmed',
      derivedStatus:
          j['derived_status']?.toString() ?? j['status']?.toString() ?? 'confirmed',
      remaining: _decNullableDouble(j['remaining']) ??
          _decDouble(j['total_amount']) - _decDouble(j['paid_amount']),
      itemsCount: coerceToInt(j['items_count'], fallback: lines.length),
      supplierName: j['supplier_name']?.toString() ?? j['supplierName']?.toString(),
      brokerName: j['broker_name']?.toString() ?? j['brokerName']?.toString(),
      supplierGst: j['supplier_gst']?.toString(),
      supplierAddress: j['supplier_address']?.toString(),
      supplierPhone: j['supplier_phone']?.toString(),
      supplierWhatsapp: j['supplier_whatsapp']?.toString(),
      brokerPhone: j['broker_phone']?.toString(),
      brokerLocation: j['broker_location']?.toString(),
      brokerImageUrl: j['broker_image_url']?.toString(),
      discount: _decNullableDouble(j['discount']),
      commissionMode: cm,
      commissionPercent: cm == 'percent' ? cPct : null,
      commissionMoney: cm != 'percent' ? cMoney : null,
      deliveredRate: _decNullableDouble(j['delivered_rate']),
      billtyRate: _decNullableDouble(j['billty_rate']),
      freightAmount: _decNullableDouble(j['freight_amount'] ?? j['freight_value']),
      freightType: j['freight_type']?.toString(),
      lines: lines,
      createdAt: parseD('created_at'),
      updatedAt: parseD('updated_at'),
      hasMissingDetails: j['has_missing_details'] == true ||
          j['has_missing_details']?.toString().toLowerCase() == 'true',
      isDelivered: (j['is_delivered'] as bool?) ?? false,
      deliveredAt: j['delivered_at'] != null
          ? DateTime.tryParse(j['delivered_at'].toString())
          : null,
      deliveryNotes: j['delivery_notes']?.toString(),
    );
  }
}

extension TradePurchaseOptimisticPatch on TradePurchase {
  /// Instant UI while [markPurchaseDelivered] round-trips.
  TradePurchase withOptimisticMarkedDelivered() {
    return TradePurchase(
      id: id,
      humanId: humanId,
      invoiceNumber: invoiceNumber,
      purchaseDate: purchaseDate,
      supplierId: supplierId,
      brokerId: brokerId,
      paymentDays: paymentDays,
      dueDate: dueDate,
      paidAmount: paidAmount,
      paidAt: paidAt,
      totalAmount: totalAmount,
      storedStatus: storedStatus,
      derivedStatus: derivedStatus,
      remaining: remaining,
      itemsCount: itemsCount,
      supplierName: supplierName,
      brokerName: brokerName,
      supplierGst: supplierGst,
      supplierAddress: supplierAddress,
      supplierPhone: supplierPhone,
      supplierWhatsapp: supplierWhatsapp,
      brokerPhone: brokerPhone,
      brokerLocation: brokerLocation,
      brokerImageUrl: brokerImageUrl,
      discount: discount,
      commissionMode: commissionMode,
      commissionPercent: commissionPercent,
      commissionMoney: commissionMoney,
      deliveredRate: deliveredRate,
      billtyRate: billtyRate,
      freightAmount: freightAmount,
      freightType: freightType,
      lines: lines,
      createdAt: createdAt,
      updatedAt: updatedAt,
      totalLandingSubtotal: totalLandingSubtotal,
      totalSellingSubtotal: totalSellingSubtotal,
      totalLineProfit: totalLineProfit,
      hasMissingDetails: hasMissingDetails,
      isDelivered: true,
      deliveredAt: deliveredAt ?? DateTime.now(),
      deliveryNotes: deliveryNotes,
    );
  }

  /// Instant UI while [markPurchasePaid] round-trips.
  TradePurchase withOptimisticMarkedPaid() {
    return TradePurchase(
      id: id,
      humanId: humanId,
      invoiceNumber: invoiceNumber,
      purchaseDate: purchaseDate,
      supplierId: supplierId,
      brokerId: brokerId,
      paymentDays: paymentDays,
      dueDate: dueDate,
      paidAmount: totalAmount,
      paidAt: paidAt ?? DateTime.now(),
      totalAmount: totalAmount,
      storedStatus: storedStatus,
      derivedStatus: 'paid',
      remaining: 0,
      itemsCount: itemsCount,
      supplierName: supplierName,
      brokerName: brokerName,
      supplierGst: supplierGst,
      supplierAddress: supplierAddress,
      supplierPhone: supplierPhone,
      supplierWhatsapp: supplierWhatsapp,
      brokerPhone: brokerPhone,
      brokerLocation: brokerLocation,
      brokerImageUrl: brokerImageUrl,
      discount: discount,
      commissionMode: commissionMode,
      commissionPercent: commissionPercent,
      commissionMoney: commissionMoney,
      deliveredRate: deliveredRate,
      billtyRate: billtyRate,
      freightAmount: freightAmount,
      freightType: freightType,
      lines: lines,
      createdAt: createdAt,
      updatedAt: updatedAt,
      totalLandingSubtotal: totalLandingSubtotal,
      totalSellingSubtotal: totalSellingSubtotal,
      totalLineProfit: totalLineProfit,
      hasMissingDetails: hasMissingDetails,
      isDelivered: isDelivered,
      deliveredAt: deliveredAt,
      deliveryNotes: deliveryNotes,
    );
  }

  /// Instant UI while [cancelPurchase] round-trips (detail/history actions).
  TradePurchase withOptimisticCancelled() {
    return TradePurchase(
      id: id,
      humanId: humanId,
      invoiceNumber: invoiceNumber,
      purchaseDate: purchaseDate,
      supplierId: supplierId,
      brokerId: brokerId,
      paymentDays: paymentDays,
      dueDate: dueDate,
      paidAmount: paidAmount,
      paidAt: paidAt,
      totalAmount: totalAmount,
      storedStatus: 'cancelled',
      derivedStatus: 'cancelled',
      remaining: remaining,
      itemsCount: itemsCount,
      supplierName: supplierName,
      brokerName: brokerName,
      supplierGst: supplierGst,
      supplierAddress: supplierAddress,
      supplierPhone: supplierPhone,
      supplierWhatsapp: supplierWhatsapp,
      brokerPhone: brokerPhone,
      brokerLocation: brokerLocation,
      brokerImageUrl: brokerImageUrl,
      discount: discount,
      commissionMode: commissionMode,
      commissionPercent: commissionPercent,
      commissionMoney: commissionMoney,
      deliveredRate: deliveredRate,
      billtyRate: billtyRate,
      freightAmount: freightAmount,
      freightType: freightType,
      lines: lines,
      createdAt: createdAt,
      updatedAt: updatedAt,
      totalLandingSubtotal: totalLandingSubtotal,
      totalSellingSubtotal: totalSellingSubtotal,
      totalLineProfit: totalLineProfit,
      hasMissingDetails: hasMissingDetails,
      isDelivered: isDelivered,
      deliveredAt: deliveredAt,
      deliveryNotes: deliveryNotes,
    );
  }
}
