import 'package:flutter/material.dart';

import '../theme/hexa_colors.dart';

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
    this.sellingCost,
    this.discount,
    this.taxPercent,
    this.catalogItemId,
    this.hsnCode,
    this.paymentDays,
    this.description,
  });

  final String id;
  final String itemName;
  final double qty;
  final String unit;
  final double landingCost;
  final double? sellingCost;
  final double? discount;
  final double? taxPercent;
  final String? catalogItemId;
  final String? hsnCode;
  final int? paymentDays;
  final String? description;

  factory TradePurchaseLine.fromJson(Map<String, dynamic> j) {
    return TradePurchaseLine(
      id: j['id']?.toString() ?? '',
      itemName: j['item_name']?.toString() ?? '',
      qty: (j['qty'] as num?)?.toDouble() ?? 0,
      unit: j['unit']?.toString() ?? '',
      landingCost: (j['landing_cost'] as num?)?.toDouble() ?? 0,
      sellingCost: (j['selling_cost'] as num?)?.toDouble(),
      discount: (j['discount'] as num?)?.toDouble(),
      taxPercent: (j['tax_percent'] as num?)?.toDouble(),
      catalogItemId: j['catalog_item_id']?.toString(),
      hsnCode: j['hsn_code']?.toString(),
      paymentDays: (j['payment_days'] as num?)?.toInt(),
      description: j['description']?.toString(),
    );
  }
}

class TradePurchase {
  TradePurchase({
    required this.id,
    required this.humanId,
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
    this.discount,
    this.commissionPercent,
    this.deliveredRate,
    this.billtyRate,
    this.freightAmount,
    this.freightType,
    this.lines = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String humanId;
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
  final double? discount;
  final double? commissionPercent;
  final double? deliveredRate;
  final double? billtyRate;
  final double? freightAmount;
  final String? freightType;
  final List<TradePurchaseLine> lines;
  final DateTime? createdAt;
  final DateTime? updatedAt;

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

    final pd = parseD('purchase_date') ?? DateTime.now();

    return TradePurchase(
      id: j['id']?.toString() ?? '',
      humanId: j['human_id']?.toString() ?? '',
      purchaseDate: pd,
      supplierId: j['supplier_id']?.toString(),
      brokerId: j['broker_id']?.toString(),
      paymentDays: (j['payment_days'] as num?)?.toInt(),
      dueDate: parseD('due_date'),
      paidAmount: (j['paid_amount'] as num?)?.toDouble() ?? 0,
      paidAt: parseD('paid_at'),
      totalAmount: (j['total_amount'] as num?)?.toDouble() ?? 0,
      storedStatus: j['status']?.toString() ?? 'confirmed',
      derivedStatus:
          j['derived_status']?.toString() ?? j['status']?.toString() ?? 'confirmed',
      remaining: (j['remaining'] as num?)?.toDouble() ??
          ((j['total_amount'] as num?)?.toDouble() ?? 0) -
              ((j['paid_amount'] as num?)?.toDouble() ?? 0),
      itemsCount: (j['items_count'] as num?)?.toInt() ?? lines.length,
      supplierName: j['supplier_name']?.toString(),
      brokerName: j['broker_name']?.toString(),
      supplierGst: j['supplier_gst']?.toString(),
      supplierAddress: j['supplier_address']?.toString(),
      supplierPhone: j['supplier_phone']?.toString(),
      supplierWhatsapp: j['supplier_whatsapp']?.toString(),
      brokerPhone: j['broker_phone']?.toString(),
      brokerLocation: j['broker_location']?.toString(),
      discount: (j['discount'] as num?)?.toDouble(),
      commissionPercent: (j['commission_percent'] as num?)?.toDouble(),
      deliveredRate: (j['delivered_rate'] as num?)?.toDouble(),
      billtyRate: (j['billty_rate'] as num?)?.toDouble(),
      freightAmount: (j['freight_amount'] as num?)?.toDouble(),
      freightType: j['freight_type']?.toString(),
      lines: lines,
      createdAt: parseD('created_at'),
      updatedAt: parseD('updated_at'),
    );
  }
}
