import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/calc_engine.dart';
import '../../../core/auth/session_notifier.dart';
import '../domain/purchase_draft.dart';

// --- Parity with legacy `purchase_entry_wizard_v2.dart` (same math as _strictFooter / computeTradeTotals) ---

double _wizLineGross(TradeCalcLine li) => lineGrossBase(li);

double _wizLineAfterLineDisc(TradeCalcLine li) {
  final base = _wizLineGross(li);
  final ld = li.discountPercent != null ? li.discountPercent! : 0.0;
  final d = ld > 100 ? 100.0 : ld;
  return base * (1.0 - d / 100.0);
}

double _wizLineTaxAmount(TradeCalcLine li) {
  final ad = _wizLineAfterLineDisc(li);
  final tax = li.taxPercent != null ? li.taxPercent! : 0.0;
  final t = tax > 1000 ? 1000.0 : tax;
  return ad * (t / 100.0);
}

TradeCalcLine _lineToCalc(PurchaseLineDraft l) {
  return TradeCalcLine(
    qty: l.qty,
    landingCost: l.landingCost,
    kgPerUnit: l.kgPerUnit,
    landingCostPerKg: l.landingCostPerKg,
    taxPercent: l.taxPercent,
    discountPercent: l.lineDiscountPercent,
  );
}

/// Maps draft lines to [computeTradeTotals] request (unchanged from legacy `\_computeTotals`).
TradeCalcRequest draftToCalcRequest(PurchaseDraft d) {
  return TradeCalcRequest(
    headerDiscountPercent: d.headerDiscountPercent,
    commissionPercent: d.commissionPercent,
    freightAmount: d.freightAmount,
    freightType: d.freightType,
    billtyRate: d.billtyRate,
    deliveredRate: d.deliveredRate,
    lines: [for (final l in d.lines) _lineToCalc(l)],
  );
}

TradeCalcTotals computePurchaseTotals(PurchaseDraft d) =>
    computeTradeTotals(draftToCalcRequest(d));

PurchaseStrictBreakdown strictFooterBreakdown(PurchaseDraft d) {
  var subtotalGross = 0.0;
  var lineDiscountTotal = 0.0;
  var taxTotal = 0.0;
  var linesTotal = 0.0;
  for (final line in d.lines) {
    final li = _lineToCalc(line);
    final g = _wizLineGross(li);
    final ad = _wizLineAfterLineDisc(li);
    subtotalGross += g;
    lineDiscountTotal += (g - ad);
    taxTotal += _wizLineTaxAmount(li);
    linesTotal += lineMoney(li);
  }
  final headerDisc = d.headerDiscountPercent ?? 0.0;
  final hd = headerDisc > 100 ? 100.0 : headerDisc;
  final afterHeader = linesTotal * (1.0 - hd / 100.0);
  final headerDiscountAmt = linesTotal - afterHeader;
  final discountTotal = lineDiscountTotal + headerDiscountAmt;
  var freight = d.freightAmount ?? 0.0;
  if (d.freightType == 'included') freight = 0.0;
  final comm = d.commissionPercent ?? 0.0;
  final c = comm > 100 ? 100.0 : comm;
  final commission = comm > 0 ? afterHeader * c / 100.0 : 0.0;
  final totals = computePurchaseTotals(d);
  return PurchaseStrictBreakdown(
    subtotalGross: subtotalGross,
    taxTotal: taxTotal,
    discountTotal: discountTotal,
    freight: freight,
    commission: commission,
    grand: totals.amountSum,
  );
}

final purchaseTotalsProvider = Provider<TradeCalcTotals>((ref) {
  return computePurchaseTotals(ref.watch(purchaseDraftProvider));
});

final purchaseStrictBreakdownProvider = Provider<PurchaseStrictBreakdown>((ref) {
  return strictFooterBreakdown(ref.watch(purchaseDraftProvider));
});

/// Rolled-up physical quantities for Summary (kg + counts by unit).
@immutable
class PurchaseQuantityTotals {
  const PurchaseQuantityTotals({
    required this.totalKg,
    required this.qtyByUnit,
  });

  /// Total mass in kg from all lines that contribute kg (bag/sack lines + plain kg).
  final double totalKg;
  /// e.g. {'bag': 100.0, 'piece': 3.0}
  final Map<String, double> qtyByUnit;
}

final purchaseQuantityTotalsProvider =
    Provider<PurchaseQuantityTotals>((ref) {
  final d = ref.watch(purchaseDraftProvider);
  var totalKg = 0.0;
  final byUnit = <String, double>{};
  for (final l in d.lines) {
    final u = l.unit.trim().toLowerCase();
    if (u.isEmpty) continue;
    byUnit[u] = (byUnit[u] ?? 0) + l.qty;
    final kpu = l.kgPerUnit;
    if (kpu != null && kpu > 0 && (u == 'bag' || u == 'sack')) {
      totalKg += l.qty * kpu;
    } else if (u == 'kg') {
      totalKg += l.qty;
    }
  }
  return PurchaseQuantityTotals(totalKg: totalKg, qtyByUnit: byUnit);
});

class PurchaseSaveValidation {
  const PurchaseSaveValidation({this.errorMessage, this.lineIndex});
  final String? errorMessage;
  final int? lineIndex;
  bool get isOk => errorMessage == null;
}

/// fromStep0, fromStep1, fromStep2, fromStep3: may press Next to the following step.
final purchaseStepGatesProvider =
    Provider<({bool from0, bool from1, bool from2, bool from3})>((ref) {
  final d = ref.watch(purchaseDraftProvider);
  final hasS = d.supplierId != null && d.supplierId!.isNotEmpty;
  if (!hasS) {
    return (from0: false, from1: false, from2: false, from3: false);
  }
  var validLines = d.lines.isNotEmpty;
  if (validLines) {
    for (final l in d.lines) {
      if (!purchaseLineIsValidForSave(l)) {
        validLines = false;
        break;
      }
    }
  } else {
    validLines = false;
  }
  // Supplier → terms → items (always) → summary/save (need lines).
  return (from0: hasS, from1: hasS, from2: validLines, from3: validLines);
});

final purchaseSaveValidationProvider = Provider<PurchaseSaveValidation>((ref) {
  final d = ref.watch(purchaseDraftProvider);
  if (d.supplierId == null || d.supplierId!.isEmpty) {
    return const PurchaseSaveValidation(errorMessage: 'Select a supplier.');
  }
  if (d.lines.isEmpty) {
    return const PurchaseSaveValidation(
      errorMessage: 'Add at least one item.',
    );
  }
  for (var i = 0; i < d.lines.length; i++) {
    final it = d.lines[i];
    final lineReason = purchaseLineSaveBlockReason(it);
    if (lineReason != null) {
      return PurchaseSaveValidation(
        errorMessage: 'Line ${i + 1}: $lineReason',
        lineIndex: i,
      );
    }
  }
  return const PurchaseSaveValidation();
});

class PurchaseDraftNotifier extends Notifier<PurchaseDraft> {
  /// Tracked manually because Riverpod 2.6 lacks `ref.mounted` on
  /// `NotifierProviderRef`. Guards post-await `state = ...` assignments.
  bool _disposed = false;

  @override
  PurchaseDraft build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return PurchaseDraft.initial();
  }

  void reset() {
    state = PurchaseDraft.initial();
  }

  void setPurchaseDate(DateTime d) {
    state = state.copyWith(purchaseDate: d);
  }

  void setInvoiceText(String t) {
    final s = t.trim();
    if (s.isEmpty) {
      state = state.copyWith(clearInvoice: true);
    } else {
      state = state.copyWith(invoiceNumber: s);
    }
  }

  void setHeaderDiscountFromText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearHeaderDiscount: true);
      return;
    }
    final p = double.tryParse(v);
    state = state.copyWith(headerDiscountPercent: p);
  }

  void setSupplierFromMap(Map<String, dynamic> row, String id, String name) {
    String? bFrom;
    final br = row['broker_id']?.toString();
    if (br != null && br.isNotEmpty) bFrom = br;

    int? pay;
    final pd = row['default_payment_days'];
    if (pd is num) pay = pd.toInt();

    double? del;
    final dr = row['default_delivered_rate'];
    if (dr is num && dr > 0) del = dr.toDouble();

    double? bill;
    final brR = row['default_billty_rate'];
    if (brR is num && brR > 0) bill = brR.toDouble();

    var ft = state.freightType;
    final sft = row['freight_type']?.toString();
    if (sft == 'included' || sft == 'separate') ft = sft!;

    state = state.copyWith(
      supplierId: id,
      supplierName: name,
      brokerId: bFrom,
      // Never carry over a label from a previous broker; resolved after fetch in wizard.
      brokerName: bFrom == null ? null : null,
      brokerIdFromSupplier: bFrom,
      clearBroker: bFrom == null,
      clearPaymentDays: pay == null,
      paymentDays: pay,
      clearDelivered: del == null,
      deliveredRate: del,
      clearBillty: bill == null,
      billtyRate: bill,
      freightType: ft,
    );
  }

  /// Clears terms tied to the previous supplier, then applies [row] (fresh API or list).
  /// Does not change line items — avoids reusing payment/delivered/billty/freight/broker
  /// from an earlier selection when the user picks a new supplier.
  void applySupplierSelection(Map<String, dynamic> row, String id, String name) {
    state = state.copyWith(
      clearPaymentDays: true,
      clearDelivered: true,
      clearBillty: true,
      clearFreight: true,
      clearBroker: true,
    );
    setSupplierFromMap(row, id, name);
  }

  void setSupplierNameOnly(String? name) {
    state = state.copyWith(supplierName: name);
  }

  void clearSupplier() {
    state = state.copyWith(
      clearSupplier: true,
      clearBroker: true,
      clearPaymentDays: true,
      clearHeaderDiscount: true,
      clearCommission: true,
      clearDelivered: true,
      clearBillty: true,
      clearFreight: true,
    );
    state = state.copyWith(
      freightType: 'separate',
    );
  }

  /// [fromSupplier] when true sets [PurchaseDraft.brokerIdFromSupplier] so UI
  /// can show "From supplier" vs manual.
  void setBroker(String? id, String? name, {bool fromSupplier = false}) {
    if (id == null || id.isEmpty) {
      state = state.copyWith(
        clearBroker: true,
        clearBrokerFromSupplier: true,
      );
      return;
    }
    if (fromSupplier) {
      state = state.copyWith(
        brokerId: id,
        brokerName: name,
        clearBrokerFromSupplier: false,
        brokerIdFromSupplier: id,
      );
    } else {
      state = state.copyWith(
        brokerId: id,
        brokerName: name,
        clearBrokerFromSupplier: true,
      );
    }
  }

  void setPaymentDaysText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearPaymentDays: true);
      return;
    }
    state = state.copyWith(paymentDays: int.tryParse(v));
  }

  void setDeliveredText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearDelivered: true);
      return;
    }
    state = state.copyWith(deliveredRate: double.tryParse(v));
  }

  void setBilltyText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearBillty: true);
      return;
    }
    state = state.copyWith(billtyRate: double.tryParse(v));
  }

  void setFreightText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearFreight: true);
      return;
    }
    state = state.copyWith(freightAmount: double.tryParse(v));
  }

  void setFreightType(String t) {
    if (t != 'included' && t != 'separate') return;
    state = state.copyWith(freightType: t);
  }

  void setCommissionText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearCommission: true);
      return;
    }
    state = state.copyWith(commissionPercent: double.tryParse(v));
  }

  void addOrReplaceLine(PurchaseLineDraft line, {int? editIndex}) {
    if (editIndex != null) {
      final l = List<PurchaseLineDraft>.from(state.lines);
      l[editIndex] = line;
      state = state.copyWith(lines: l);
    } else {
      state = state.copyWith(lines: [...state.lines, line]);
    }
  }

  void removeLineAt(int i) {
    if (i < 0 || i >= state.lines.length) return;
    final l = List<PurchaseLineDraft>.from(state.lines)..removeAt(i);
    state = state.copyWith(lines: l);
  }

  void setLinesFromMaps(List<Map<String, dynamic>> maps) {
    state = state.copyWith(
      lines: [for (final e in maps) PurchaseLineDraft.fromLineMap(e)],
    );
  }

  void syncAllLinesFromControllerMaps(List<Map<String, dynamic>> items) {
    setLinesFromMaps([for (final e in items) Map<String, dynamic>.from(e)]);
  }

  Map<String, dynamic> buildTradePurchaseBody() {
    final d = state;
    final lines = <Map<String, dynamic>>[
      for (final l in d.lines) l.toLineMap(),
    ];
    final body = <String, dynamic>{
      'purchase_date': DateFormat('yyyy-MM-dd').format(d.purchaseDate ?? DateTime.now()),
      'status': 'confirmed',
      'lines': lines,
      'freight_type': d.freightType,
    };
    final inv = d.invoiceNumber?.trim() ?? '';
    if (inv.isNotEmpty) body['invoice_number'] = inv;
    if (d.supplierId != null && d.supplierId!.isNotEmpty) {
      body['supplier_id'] = d.supplierId;
    }
    if (d.brokerId != null && d.brokerId!.isNotEmpty) {
      body['broker_id'] = d.brokerId;
    }
    final pd = d.paymentDays;
    if (pd != null && pd >= 0) body['payment_days'] = pd;
    final hd = d.headerDiscountPercent;
    if (hd != null && hd > 0) body['discount'] = hd;
    final comm = d.commissionPercent;
    if (comm != null && comm > 0) body['commission_percent'] = comm;
    final dlr = d.deliveredRate;
    if (dlr != null && dlr >= 0) body['delivered_rate'] = dlr;
    final brt = d.billtyRate;
    if (brt != null && brt >= 0) body['billty_rate'] = brt;
    final fa = d.freightAmount;
    if (fa != null && fa > 0) body['freight_amount'] = fa;
    return body;
  }

  void applyFromPrefsMap(Map<String, dynamic> m) {
    final pd = m['purchaseDate']?.toString();
    var date = state.purchaseDate;
    if (pd != null && pd.isNotEmpty) {
      date = DateTime.tryParse(pd) ?? date;
    }
    var ft = m['freightType']?.toString();
    if (ft != 'included' && ft != 'separate') ft = state.freightType;
    final lines = <Map<String, dynamic>>[];
    final li = m['items'];
    if (li is List) {
      for (final e in li) {
        if (e is Map) lines.add(Map<String, dynamic>.from(e));
      }
    }
    state = PurchaseDraft(
      supplierId: m['supplierId']?.toString(),
      supplierName: m['supplierName']?.toString(),
      brokerId: m['brokerId']?.toString(),
      brokerName: m['brokerName']?.toString(),
      brokerIdFromSupplier: m['brokerIdFromSupplier']?.toString(),
      purchaseDate: date,
      invoiceNumber: m['invoice']?.toString(),
      paymentDays: int.tryParse(m['paymentDays']?.toString() ?? ''),
      headerDiscountPercent: double.tryParse(m['headerDisc']?.toString() ?? ''),
      commissionPercent: double.tryParse(m['commission']?.toString() ?? ''),
      deliveredRate: double.tryParse(m['delivered']?.toString() ?? ''),
      billtyRate: double.tryParse(m['billty']?.toString() ?? ''),
      freightAmount: double.tryParse(m['freight']?.toString() ?? ''),
      freightType: ft ?? 'separate',
      lines: [for (final e in lines) PurchaseLineDraft.fromLineMap(e)],
    );
  }

  Map<String, dynamic> toPrefsMap() {
    final d = state;
    return {
      'supplierId': d.supplierId,
      'supplierName': d.supplierName,
      'brokerId': d.brokerId,
      'brokerName': d.brokerName,
      'brokerIdFromSupplier': d.brokerIdFromSupplier,
      'purchaseDate': d.purchaseDate?.toIso8601String(),
      'invoice': d.invoiceNumber,
      'paymentDays': d.paymentDays?.toString() ?? '',
      'headerDisc': d.headerDiscountPercent?.toString() ?? '',
      'commission': d.commissionPercent?.toString() ?? '',
      'delivered': d.deliveredRate?.toString() ?? '',
      'billty': d.billtyRate?.toString() ?? '',
      'freight': d.freightAmount?.toString() ?? '',
      'freightType': d.freightType,
      'items': [for (final l in d.lines) l.toLineMap()],
    };
  }

  /// Returns the raw server map for the wizard (e.g. human_id, payment snapshot).
  Future<Map<String, dynamic>?> loadFromEdit(String purchaseId) async {
    if (_disposed) return null;
    final session = ref.read(sessionProvider);
    if (session == null) return null;
    final raw = await ref.read(hexaApiProvider).getTradePurchase(
          businessId: session.primaryBusiness.id,
          purchaseId: purchaseId,
        );
    if (_disposed) return raw;
    state = _parseServerPurchaseMap(raw);
    return raw;
  }

  PurchaseDraft _parseServerPurchaseMap(Map<String, dynamic> raw) {
    var purchaseDate = DateTime.now();
    final pd = raw['purchase_date']?.toString();
    if (pd != null && pd.isNotEmpty) {
      final d0 = DateTime.tryParse(pd);
      if (d0 != null) purchaseDate = d0;
    }
    var ft = 'separate';
    final sft = raw['freight_type']?.toString();
    if (sft == 'included' || sft == 'separate') ft = sft!;

    int? pay;
    final payRaw = raw['payment_days'];
    if (payRaw is num) pay = payRaw.toInt();

    final lines = <PurchaseLineDraft>[];
    final ls = raw['lines'];
    if (ls is List) {
      for (final e in ls) {
        if (e is! Map) continue;
        lines.add(
          PurchaseLineDraft.fromLineMap(
            Map<String, dynamic>.from(e),
          ),
        );
      }
    }

    return PurchaseDraft(
      supplierId: raw['supplier_id']?.toString(),
      supplierName: raw['supplier_name']?.toString(),
      brokerId: raw['broker_id']?.toString(),
      brokerName: raw['broker_name']?.toString(),
      brokerIdFromSupplier: raw['broker_id']?.toString(),
      purchaseDate: purchaseDate,
      invoiceNumber: raw['invoice_number']?.toString(),
      paymentDays: pay,
      headerDiscountPercent: (raw['discount'] as num?)?.toDouble(),
      commissionPercent: (raw['commission_percent'] as num?)?.toDouble(),
      deliveredRate: (raw['delivered_rate'] as num?)?.toDouble(),
      billtyRate: (raw['billty_rate'] as num?)?.toDouble(),
      freightAmount: (raw['freight_amount'] as num?)?.toDouble(),
      freightType: ft,
      lines: lines,
    );
  }
}

final purchaseDraftProvider =
    NotifierProvider<PurchaseDraftNotifier, PurchaseDraft>(
  PurchaseDraftNotifier.new,
);
