import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/calc_engine.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/strict_decimal.dart';
import '../domain/purchase_draft.dart';

double? _parseDecimalInput(String text) {
  final v = text.trim();
  if (v.isEmpty) return null;
  try {
    return StrictDecimal.parse(v).toDouble();
  } on FormatException {
    return null;
  }
}

double? _decimalFromObject(Object? value) {
  if (value == null) return null;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return null;
  }
}

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

TradeCommissionLine _draftLineToCommissionBasis(PurchaseLineDraft l) {
  return TradeCommissionLine(
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    kgPerUnit: l.kgPerUnit,
    catalogDefaultUnit: null,
    catalogDefaultKgPerBag: null,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  );
}

/// Maps draft lines to [computeTradeTotals] request (unchanged from legacy `\_computeTotals`).
TradeCalcRequest draftToCalcRequest(PurchaseDraft d) {
  return TradeCalcRequest(
    headerDiscountPercent: d.headerDiscountPercent,
    commissionPercent: d.commissionPercent,
    commissionMode: d.commissionMode,
    commissionMoney: d.commissionMoney,
    commissionBasisLines: [for (final l in d.lines) _draftLineToCommissionBasis(l)],
    freightAmount: d.freightAmount,
    freightType: d.freightType,
    billtyRate: d.billtyRate,
    deliveredRate: d.deliveredRate,
    lines: [for (final l in d.lines) _lineToCalc(l)],
  );
}

TradeCalcTotals computePurchaseTotals(PurchaseDraft d) =>
    computeTradeTotals(draftToCalcRequest(d));

bool _tradePurchaseMapLooksValid(Map<String, dynamic> raw) {
  final id = raw['id']?.toString();
  if (id == null || id.isEmpty) return false;
  final sid = raw['supplier_id']?.toString();
  if (sid != null && sid.isNotEmpty) return true;
  final ls = raw['lines'];
  return ls is List && ls.isNotEmpty;
}

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
  final commission = headerCommissionAddOnDecimal(
    commissionMode: d.commissionMode,
    afterHeader: StrictDecimal.fromObject(afterHeader),
    commissionPercent: d.commissionPercent != null
        ? StrictDecimal.fromObject(d.commissionPercent!)
        : null,
    commissionMoney: d.commissionMoney != null
        ? StrictDecimal.fromObject(d.commissionMoney!)
        : null,
    basisLines: [for (final l in d.lines) _draftLineToCommissionBasis(l)],
  ).toDouble();
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

final purchaseStrictBreakdownProvider = Provider<PurchaseStrictBreakdown>((ref) {
  ref.watch(
    purchaseDraftProvider.select(
      (d) => (
        lines: d.lines,
        headerDiscountPercent: d.headerDiscountPercent,
        commissionMode: d.commissionMode,
        commissionPercent: d.commissionPercent,
        commissionMoney: d.commissionMoney,
        freightAmount: d.freightAmount,
        freightType: d.freightType,
        billtyRate: d.billtyRate,
        deliveredRate: d.deliveredRate,
      ),
    ),
  );
  final d = ref.read(purchaseDraftProvider);
  return strictFooterBreakdown(d);
});

/// Rolled-up physical quantities for Summary (kg + counts by unit).
@immutable
class PurchaseQuantityTotals {
  const PurchaseQuantityTotals({
    required this.totalKg,
    required this.qtyByUnit,
  });

  /// Total mass in kg from all lines that contribute kg (bag lines + plain kg).
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
    final rawU = l.unit.trim().toLowerCase();
    if (rawU.isEmpty) continue;
    // Back-compat: historical rows may contain `sack`; treat as canonical `bag`.
    final u = rawU == 'sack' ? 'bag' : rawU;
    byUnit[u] = (byUnit[u] ?? 0) + l.qty;
    final kpu = l.kgPerUnit;
    if (kpu != null && kpu > 0 && u == 'bag') {
      totalKg += l.qty * kpu;
    } else if (u == 'kg') {
      totalKg += l.qty;
    }
  }
  return PurchaseQuantityTotals(totalKg: totalKg, qtyByUnit: byUnit);
});

class PurchaseSaveValidation {
  const PurchaseSaveValidation({
    this.errorMessage,
    this.lineIndex,
    this.lineErrors = const {},
  });
  final String? errorMessage;
  /// First failing line (legacy / scroll target) when also using [lineErrors].
  final int? lineIndex;
  /// 0-based line index -> blocking message for summary inline display.
  final Map<int, String> lineErrors;
  bool get isOk =>
      (errorMessage == null || errorMessage!.trim().isEmpty) &&
      lineErrors.isEmpty;
}

/// from0 Party→Terms, from1 Terms→Items, from2 Items→Review, from3 Save.
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
  return (
    from0: hasS,
    from1: hasS,
    from2: validLines,
    from3: validLines,
  );
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
  final lineErrors = <int, String>{};
  for (var i = 0; i < d.lines.length; i++) {
    final reason = purchaseLineSaveBlockReason(d.lines[i]);
    if (reason != null) {
      lineErrors[i] = reason;
    }
  }
  if (lineErrors.isNotEmpty) {
    return PurchaseSaveValidation(
      lineIndex: lineErrors.keys.first,
      lineErrors: Map<int, String>.from(lineErrors),
    );
  }
  return const PurchaseSaveValidation();
});

/// Blocking message when Terms → Items advance should stop (broker commission input).
final purchaseTermsStepValidationProvider = Provider<String?>((ref) {
  final d = ref.watch(purchaseDraftProvider);
  if (d.supplierId == null || d.supplierId!.isEmpty) return null;
  final hasBroker = d.brokerId != null && d.brokerId!.trim().isNotEmpty;
  if (!hasBroker) return null;
  if (d.commissionMode == kPurchaseCommissionModePercent) {
    final p = d.commissionPercent;
    if (p != null && p > 100) {
      return 'Broker commission % cannot exceed 100.';
    }
  } else {
    final m = d.commissionMoney;
    if (m != null && m < 0) {
      return 'Broker commission amount cannot be negative.';
    }
  }
  return null;
});

/// First missing-field message that blocks each wizard step transition.
///
/// [Bug 3 fix] The wizard footer now ALWAYS enables Continue and uses these
/// reasons to show inline errors + scroll to the failing field, instead of
/// silently disabling the button.
@immutable
class PurchaseStepBlockReasons {
  const PurchaseStepBlockReasons({
    this.from0,
    this.from1,
    this.from2,
    this.from3,
    this.firstLineIndexError,
    this.firstLineErrorField,
  });

  /// Party → Terms: missing supplier.
  final String? from0;
  /// Terms → Items: bad broker commission etc.
  final String? from1;
  /// Items → Review: at least one valid line, all lines save-ready.
  final String? from2;
  /// Save: same as `from2` plus header validations.
  final String? from3;
  /// Index of the first invalid line (used for auto-scroll).
  final int? firstLineIndexError;
  /// Field key on the first invalid line for inline highlighting.
  final String? firstLineErrorField;
}

/// Field key derived from a line save-block reason (used for inline borders).
String? _lineFieldKeyForReason(String reason) {
  final r = reason.toLowerCase();
  if (r.contains('item')) return 'item';
  if (r.contains('quantity') || r.contains('qty') || r.contains('whole')) {
    return 'qty';
  }
  if (r.contains('unit')) return 'unit';
  if (r.contains('kg per bag') || r.contains('kg per unit')) return 'kg_per_bag';
  if (r.contains('per-kg cost') || r.contains('purchase rate') ||
      r.contains('landing cost')) {
    return 'landing';
  }
  if (r.contains('hsn')) return 'hsn';
  return null;
}

final purchaseStepBlockReasonsProvider =
    Provider<PurchaseStepBlockReasons>((ref) {
  final d = ref.watch(purchaseDraftProvider);

  // Step 0 → 1: supplier required.
  String? from0;
  if (d.supplierId == null || d.supplierId!.trim().isEmpty) {
    from0 = 'Select a supplier to continue.';
  }

  // Step 1 → 2: terms validation (broker commission ranges).
  final from1 = from0 ?? ref.watch(purchaseTermsStepValidationProvider);

  // Step 2 → 3 (and Save): supplier + at least one save-ready line.
  String? from2 = from1;
  int? firstLineIdx;
  String? firstLineField;
  if (from2 == null) {
    if (d.lines.isEmpty) {
      from2 = 'Add at least one item to continue.';
    } else {
      for (var i = 0; i < d.lines.length; i++) {
        final reason = purchaseLineSaveBlockReason(d.lines[i]);
        if (reason != null) {
          from2 = 'Item ${i + 1}: $reason';
          firstLineIdx = i;
          firstLineField = _lineFieldKeyForReason(reason);
          break;
        }
      }
    }
  }

  return PurchaseStepBlockReasons(
    from0: from0,
    from1: from1,
    from2: from2,
    from3: from2,
    firstLineIndexError: firstLineIdx,
    firstLineErrorField: firstLineField,
  );
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

  /// Replace entire draft (e.g. seeded from bill scan OCR review).
  void replaceDraft(PurchaseDraft d) {
    state = d;
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
    final p = _parseDecimalInput(v);
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
    del = _decimalFromObject(dr);
    if (del != null && del <= 0) del = null;

    double? bill;
    final brR = row['default_billty_rate'];
    bill = _decimalFromObject(brR);
    if (bill != null && bill <= 0) bill = null;

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
  ///
  /// Clears broker + header terms when picking a supplier; fills terms via broker defaults
  /// when a broker is selected (or hinted from last trade without copying header money).
  void applySupplierSelection(Map<String, dynamic> _, String id, String name) {
    state = state.copyWith(
      supplierId: id,
      supplierName: name,
      clearBroker: true,
      clearBrokerFromSupplier: true,
      clearPaymentDays: true,
      clearHeaderDiscount: true,
      clearCommission: true,
      clearDelivered: true,
      clearBillty: true,
      clearFreight: true,
      freightType: 'separate',
    );
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

  /// Header terms from broker master (payment/discount/rates/freight/commission).
  void applyBrokerDealDefaults(Map<String, dynamic> raw) {
    final pd = raw['default_payment_days'];
    int? pay;
    if (pd is num) pay = pd.toInt();

    double? disc = _decimalFromObject(raw['default_discount']);
    if (disc != null && disc < 0) disc = null;

    double? del = _decimalFromObject(raw['default_delivered_rate']);
    if (del != null && del < 0) del = null;
    double? bill = _decimalFromObject(raw['default_billty_rate']);
    if (bill != null && bill < 0) bill = null;

    String commMode = kPurchaseCommissionModePercent;
    double? commPct;
    double? commMoney;
    final ct = raw['commission_type']?.toString() ?? 'percent';
    if (ct == 'percent') {
      commPct = _decimalFromObject(raw['commission_value']);
      if (commPct != null && commPct < 0) commPct = null;
    } else {
      commMode = kPurchaseCommissionModeFlatInvoice;
      commMoney = _decimalFromObject(raw['commission_value']);
      if (commMoney != null && commMoney < 0) commMoney = null;
    }

    var ft = state.freightType;
    final sft = raw['freight_type']?.toString();
    if (sft == 'included' || sft == 'separate') ft = sft!;

    state = state.copyWith(
      clearPaymentDays: pay == null,
      paymentDays: pay,
      clearHeaderDiscount: disc == null,
      headerDiscountPercent: disc,
      clearDelivered: del == null,
      deliveredRate: del,
      clearBillty: bill == null,
      billtyRate: bill,
      freightType: ft,
    ).withCommissionHeader(
      mode: commMode,
      percent: commPct,
      money: commMoney,
    );
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
    state = state.copyWith(deliveredRate: _parseDecimalInput(v));
  }

  void setBilltyText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearBillty: true);
      return;
    }
    state = state.copyWith(billtyRate: _parseDecimalInput(v));
  }

  void setFreightText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      state = state.copyWith(clearFreight: true);
      return;
    }
    state = state.copyWith(freightAmount: _parseDecimalInput(v));
  }

  void setFreightType(String t) {
    if (t != 'included' && t != 'separate') return;
    state = state.copyWith(freightType: t);
  }

  void setCommissionText(String t) {
    final v = t.trim();
    if (v.isEmpty) {
      if (state.commissionMode == kPurchaseCommissionModePercent) {
        state = state.copyWith(clearCommission: true);
      } else {
        state = state.copyWith(clearCommissionMoney: true);
      }
      return;
    }
    final parsed = _parseDecimalInput(v);
    state = state.withCommissionHeader(
      mode: state.commissionMode,
      percent: state.commissionMode == kPurchaseCommissionModePercent
          ? parsed
          : state.commissionPercent,
      money: state.commissionMode != kPurchaseCommissionModePercent
          ? parsed
          : state.commissionMoney,
    );
  }

  void setCommissionMode(String rawMode) {
    final m = PurchaseDraft.normalizeCommissionMode(rawMode);
    if (m == state.commissionMode) return;
    state = state.withCommissionHeader(
      mode: m,
      percent: m == kPurchaseCommissionModePercent
          ? state.commissionPercent
          : null,
      money: m != kPurchaseCommissionModePercent ? state.commissionMoney : null,
    );
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

  /// Builds the trade-purchase API body. Header `delivered_rate`, `billty_rate`,
  /// `freight_amount`, and purchase `discount` are authoritative; line JSON may
  /// still include legacy per-line charges when loaded from older saves.
  Map<String, dynamic> buildTradePurchaseBody({bool forceDuplicate = false}) {
    return state.toTradePurchaseCreateBody(forceDuplicate: forceDuplicate);
  }

  /// JSON for [HexaApi.previewTradePurchaseLines] — `draft` status so the server
  /// skips the line-gross gate while the user is still editing rates.
  Map<String, dynamic> buildTradePurchasePreviewBody() {
    final m = Map<String, dynamic>.from(buildTradePurchaseBody(forceDuplicate: false));
    m['status'] = 'draft';
    return m;
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
    final cmRaw = m['commissionMode']?.toString();
    final commMode = PurchaseDraft.normalizeCommissionMode(cmRaw);
    state = PurchaseDraft(
      supplierId: m['supplierId']?.toString(),
      supplierName: m['supplierName']?.toString(),
      brokerId: m['brokerId']?.toString(),
      brokerName: m['brokerName']?.toString(),
      brokerIdFromSupplier: m['brokerIdFromSupplier']?.toString(),
      purchaseDate: date,
      invoiceNumber: m['invoice']?.toString(),
      paymentDays: int.tryParse(m['paymentDays']?.toString() ?? ''),
      headerDiscountPercent: _parseDecimalInput(m['headerDisc']?.toString() ?? ''),
      commissionMode: commMode,
      commissionPercent: commMode == kPurchaseCommissionModePercent
          ? _parseDecimalInput(m['commission']?.toString() ?? '')
          : null,
      commissionMoney: commMode != kPurchaseCommissionModePercent
          ? _parseDecimalInput(m['commission']?.toString() ?? '')
          : null,
      deliveredRate: _parseDecimalInput(m['delivered']?.toString() ?? ''),
      billtyRate: _parseDecimalInput(m['billty']?.toString() ?? ''),
      freightAmount: _parseDecimalInput(m['freight']?.toString() ?? ''),
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
      'commissionMode': d.commissionMode,
      'commission': d.commissionMode == kPurchaseCommissionModePercent
          ? (d.commissionPercent?.toString() ?? '')
          : (d.commissionMoney?.toString() ?? ''),
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
    Map<String, dynamic> raw;
    try {
      raw = await ref
          .read(hexaApiProvider)
          .getTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: purchaseId,
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      return null;
    }
    if (_disposed) return raw;
    if (!_tradePurchaseMapLooksValid(raw)) {
      return null;
    }
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

    final apiMode =
        PurchaseDraft.normalizeCommissionMode(raw['commission_mode']?.toString());
    final pct = _decimalFromObject(raw['commission_percent']);
    final money = _decimalFromObject(raw['commission_money']);
    return PurchaseDraft(
      supplierId: raw['supplier_id']?.toString(),
      supplierName: raw['supplier_name']?.toString(),
      brokerId: raw['broker_id']?.toString(),
      brokerName: raw['broker_name']?.toString(),
      brokerIdFromSupplier: raw['broker_id']?.toString(),
      purchaseDate: purchaseDate,
      invoiceNumber: raw['invoice_number']?.toString(),
      paymentDays: pay,
      headerDiscountPercent: _decimalFromObject(raw['discount']),
      commissionMode: apiMode,
      commissionPercent: apiMode == kPurchaseCommissionModePercent ? pct : null,
      commissionMoney: apiMode != kPurchaseCommissionModePercent ? money : null,
      deliveredRate: _decimalFromObject(raw['delivered_rate']),
      billtyRate: _decimalFromObject(raw['billty_rate']),
      freightAmount: _decimalFromObject(raw['freight_amount']),
      freightType: ft,
      lines: lines,
    );
  }
}

final purchaseDraftProvider =
    NotifierProvider<PurchaseDraftNotifier, PurchaseDraft>(
  PurchaseDraftNotifier.new,
);
