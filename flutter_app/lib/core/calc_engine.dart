import 'strict_decimal.dart';
import 'utils/unit_classifier.dart';

/// One line of a trade purchase (API-aligned field names).
/// Totals: use [computeTradeTotals] — mirrors backend `trade_purchase_service`.
class TradeCalcLine {
  const TradeCalcLine({
    required this.qty,
    required this.landingCost,
    this.kgPerUnit,
    this.landingCostPerKg,
    this.discountPercent,
    this.taxPercent,
  });

  final double qty;
  /// When [kgPerUnit] and [landingCostPerKg] are set, this is the derived
  /// cost per *line* unit (e.g. per bag) = [kgPerUnit] * [landingCostPerKg].
  final double landingCost;
  /// e.g. 50 for a 50 kg bag. When set with [landingCostPerKg], [lineGrossBase]
  /// uses `qty * kgPerUnit * landingCostPerKg`.
  final double? kgPerUnit;
  /// Rupees per kilogram; used with [kgPerUnit] for weight-based lines.
  final double? landingCostPerKg;
  /// Line discount 0–100 (%), same semantics as backend.
  final double? discountPercent;
  final double? taxPercent;
}

/// Line snapshot for per-kg / per-bag / per-tin broker commission (header).
class TradeCommissionLine {
  const TradeCommissionLine({
    required this.itemName,
    required this.unit,
    required this.qty,
    this.kgPerUnit,
    this.catalogDefaultUnit,
    this.catalogDefaultKgPerBag,
    this.boxMode,
    this.itemsPerBox,
    this.weightPerItem,
    this.kgPerBox,
    this.weightPerTin,
  });

  final String itemName;
  final String unit;
  final double qty;
  final double? kgPerUnit;
  final String? catalogDefaultUnit;
  final double? catalogDefaultKgPerBag;
  final String? boxMode;
  final double? itemsPerBox;
  final double? weightPerItem;
  final double? kgPerBox;
  final double? weightPerTin;
}

class TradeCalcRequest {
  const TradeCalcRequest({
    required this.lines,
    this.headerDiscountPercent,
    this.commissionPercent,
    this.commissionMode = 'percent',
    this.commissionMoney,
    this.commissionBasisLines = const [],
    this.freightAmount,
    this.freightType,
    this.billtyRate,
    this.deliveredRate,
  });

  final List<TradeCalcLine> lines;
  final double? headerDiscountPercent;
  final double? commissionPercent;
  /// `percent` | `flat_invoice` | `flat_kg` | `flat_bag` | `flat_tin` (API `commission_mode`).
  final String commissionMode;
  /// Rupee rate or one-shot amount depending on [commissionMode].
  final double? commissionMoney;
  final List<TradeCommissionLine> commissionBasisLines;
  final double? freightAmount;
  /// `separate` adds freight; `included` ignores [freightAmount] for totals.
  final String? freightType;
  /// Fixed-rupee billty (matches backend [TradePurchaseCreateRequest.billty_rate]).
  final double? billtyRate;
  /// Fixed-rupee delivered charge (matches backend [TradePurchaseCreateRequest.delivered_rate]).
  final double? deliveredRate;
}

class TradeCalcTotals {
  const TradeCalcTotals({
    required this.qtySum,
    required this.amountSum,
  });

  final double qtySum;
  final double amountSum;
}

StrictDecimal _dec(double? x) => StrictDecimal.fromObject(x);
final _hundred = StrictDecimal.parse('100');
final _thousand = StrictDecimal.parse('1000');

/// Pre-discount base amount for one line (matches backend `_line_gross_base`).
StrictDecimal lineGrossBaseDecimal(TradeCalcLine li) {
  final kpu = li.kgPerUnit;
  final pk = li.landingCostPerKg;
  if (kpu != null && pk != null && kpu > 0 && pk > 0) {
    return _dec(li.qty) * _dec(kpu) * _dec(pk);
  }
  return _dec(li.qty) * _dec(li.landingCost);
}

double lineGrossBase(TradeCalcLine li) => lineGrossBaseDecimal(li).toDouble();

/// Taxable value after line discount, before GST multiplier (matches backend).
StrictDecimal lineTaxableAfterLineDiscDecimal(TradeCalcLine li) {
  final base = lineGrossBaseDecimal(li);
  final ld = li.discountPercent != null
      ? _dec(li.discountPercent).clamp(max: _hundred)
      : StrictDecimal.zero();
  return base - base.percentOf(ld);
}

double lineTaxableAfterLineDisc(TradeCalcLine li) =>
    lineTaxableAfterLineDiscDecimal(li).toDouble();

/// Per-line amount after line discount and tax multiplier (matches backend).
StrictDecimal lineMoneyDecimal(TradeCalcLine li) {
  final afterDisc = lineTaxableAfterLineDiscDecimal(li);
  final tax = li.taxPercent != null
      ? _dec(li.taxPercent).clamp(max: _thousand)
      : StrictDecimal.zero();
  return afterDisc + afterDisc.percentOf(tax);
}

double lineMoney(TradeCalcLine li) => lineMoneyDecimal(li).toDouble();

/// Physical mass in kg for one line (display + rolled totals; not money).
///
/// Rules: [bag]/[sack] → qty × kgPerUnit when kg known; else 0.
/// [box] fixed-weight → qty × max(kgPerBox, kgPerUnit); items_per_box uses items × weight/item.
/// With no kg snapshot on fixed box → 0. [tin] → qty × (weightPerTin ?? kgPerUnit) when set.
/// [kg] → qty.
double linePhysicalWeightKg({
  required String unit,
  required double qty,
  double? kgPerUnit,
  String? boxMode,
  double? itemsPerBox,
  double? weightPerItem,
  double? kgPerBox,
  double? weightPerTin,
}) {
  if (qty <= 0) return 0;
  final u = unit.trim().toLowerCase();
  if (u == 'kg') {
    return _dec(qty).toDouble();
  }
  if (u == 'bag' || u == 'sack') {
    final kpu = kgPerUnit;
    if (kpu == null || kpu <= 0) return 0;
    return (_dec(qty) * _dec(kpu)).toDouble();
  }
  if (u == 'box') {
    final mode = boxMode?.trim().toLowerCase();
    if (mode == 'items_per_box') {
      final ipb = itemsPerBox;
      final wpi = weightPerItem;
      if (ipb == null || wpi == null || ipb <= 0 || wpi <= 0) return 0;
      return (_dec(qty) * _dec(ipb) * _dec(wpi)).toDouble();
    }
    // fixed_weight_box (or unspecified): needs kg per box or line kg snapshot.
    final kBox = (kgPerBox != null && kgPerBox > 0)
        ? kgPerBox
        : ((kgPerUnit != null && kgPerUnit > 0) ? kgPerUnit : null);
    if (kBox == null || kBox <= 0) return 0;
    return (_dec(qty) * _dec(kBox)).toDouble();
  }
  if (u == 'tin') {
    final wKg = (kgPerUnit != null && kgPerUnit > 0) ? kgPerUnit : null;
    final wTin =
        (weightPerTin != null && weightPerTin > 0) ? weightPerTin : null;
    final w = wKg ?? wTin;
    if (w == null) return 0;
    return (_dec(qty) * _dec(w)).toDouble();
  }
  return 0;
}

/// Physical kg for one line driven by [UnitType] (sheet preview + aggregates).
///
/// [weightBag]: `qty * kgPerUnit` when kg/bag known, else `0`.
/// [singlePack]: `qty * kgFromName` when set, else `qty` (count / nominal kg qty).
/// [multiPackBox]: `qty * itemsPerBox * weightPerItem` when both set; else `0`.
double classifierLineWeightKg({
  required UnitType type,
  required double qty,
  double? kgPerUnit,
  double? kgFromName,
  double? itemsPerBox,
  double? weightPerItem,
}) {
  if (qty <= 0) return 0;
  switch (type) {
    case UnitType.weightBag:
      final k = kgPerUnit;
      if (k == null || k <= 0) return 0;
      return (_dec(qty) * _dec(k)).toDouble();
    case UnitType.singlePack:
      if (kgFromName != null && kgFromName > 0) {
        return (_dec(qty) * _dec(kgFromName)).toDouble();
      }
      return _dec(qty).toDouble();
    case UnitType.multiPackBox:
      final ipb = itemsPerBox;
      final wpi = weightPerItem;
      if (ipb == null || ipb <= 0) return 0;
      if (wpi != null && wpi > 0) {
        return (_dec(qty) * _dec(ipb) * _dec(wpi)).toDouble();
      }
      return 0;
  }
}

/// Total items packed in boxes (`qty * itemsPerBox`) when [multiPackBox];
/// otherwise the line quantity unit count / bag count.
double classifierTotalItems({
  required UnitType type,
  required double qty,
  double? itemsPerBox,
}) {
  if (qty <= 0) return 0;
  switch (type) {
    case UnitType.weightBag:
    case UnitType.singlePack:
      return _dec(qty).toDouble();
    case UnitType.multiPackBox:
      final ipb = itemsPerBox;
      if (ipb == null || ipb <= 0) return 0;
      return (_dec(qty) * _dec(ipb)).toDouble();
  }
}

/// Tax component of [lineMoney] (difference between inclusive and taxable).
StrictDecimal lineTaxAmountDecimal(TradeCalcLine li) =>
    lineMoneyDecimal(li) - lineTaxableAfterLineDiscDecimal(li);

double lineTaxAmount(TradeCalcLine li) => lineTaxAmountDecimal(li).toDouble();

/// Broker commission rupees added to the bill total (matches backend `_header_commission_rupees`).
StrictDecimal headerCommissionAddOnDecimal({
  required String commissionMode,
  required StrictDecimal afterHeader,
  required StrictDecimal? commissionPercent,
  required StrictDecimal? commissionMoney,
  required List<TradeCommissionLine> basisLines,
}) {
  final mode = commissionMode.trim().toLowerCase();
  if (mode.isEmpty || mode == 'percent') {
    final c = commissionPercent != null
        ? commissionPercent.clamp(max: _hundred)
        : StrictDecimal.zero();
    if (!c.isPositive) return StrictDecimal.zero();
    return afterHeader.percentOf(c);
  }
  final rate = commissionMoney ?? StrictDecimal.zero();
  if (!rate.isPositive) return StrictDecimal.zero();
  switch (mode) {
    case 'flat_invoice':
      return rate.toScale(2);
    case 'flat_kg':
      var kg = StrictDecimal.zero();
      for (final l in basisLines) {
        final w = ledgerTradeLineWeightKg(
          itemName: l.itemName,
          unit: l.unit,
          qty: l.qty,
          catalogDefaultUnit: l.catalogDefaultUnit,
          catalogDefaultKgPerBag: l.catalogDefaultKgPerBag,
          kgPerUnit: l.kgPerUnit,
          boxMode: l.boxMode,
          itemsPerBox: l.itemsPerBox,
          weightPerItem: l.weightPerItem,
          kgPerBox: l.kgPerBox,
          weightPerTin: l.weightPerTin,
        );
        kg += StrictDecimal.fromObject(w);
      }
      if (!kg.isPositive) return StrictDecimal.zero();
      return (rate * kg).toScale(2);
    case 'flat_bag':
      var bags = StrictDecimal.zero();
      for (final l in basisLines) {
        final u = l.unit.trim().toLowerCase();
        if (u == 'bag' || u == 'sack' || u == 'box') {
          bags += _dec(l.qty);
        }
      }
      if (!bags.isPositive) return StrictDecimal.zero();
      return (rate * bags).toScale(2);
    case 'flat_tin':
      var tins = StrictDecimal.zero();
      for (final l in basisLines) {
        final u = l.unit.trim().toLowerCase();
        if (u == 'tin') {
          tins += _dec(l.qty);
        }
      }
      if (!tins.isPositive) return StrictDecimal.zero();
      return (rate * tins).toScale(2);
    default:
      return StrictDecimal.zero();
  }
}

/// Returns total quantity sum and final amount (matches backend `compute_totals`).
TradeCalcTotals computeTradeTotals(TradeCalcRequest req) {
  var qtySum = StrictDecimal.zero();
  var amtSum = StrictDecimal.zero();
  for (final li in req.lines) {
    qtySum += _dec(li.qty);
    amtSum += lineMoneyDecimal(li);
  }

  final headerDisc =
      req.headerDiscountPercent != null
          ? _dec(req.headerDiscountPercent).clamp(max: _hundred)
          : StrictDecimal.zero();
  var afterHeader = amtSum;
  if (headerDisc.isPositive) {
    afterHeader = amtSum - amtSum.percentOf(headerDisc);
  }
  amtSum = afterHeader;

  var freight = req.freightAmount != null ? _dec(req.freightAmount) : StrictDecimal.zero();
  if (req.freightType == 'included') {
    freight = StrictDecimal.zero();
  }
  amtSum += freight;

  amtSum += headerCommissionAddOnDecimal(
    commissionMode: req.commissionMode,
    afterHeader: afterHeader,
    commissionPercent:
        req.commissionPercent != null ? _dec(req.commissionPercent) : null,
    commissionMoney:
        req.commissionMoney != null ? _dec(req.commissionMoney) : null,
    basisLines: req.commissionBasisLines,
  );

  final billty = req.billtyRate != null ? _dec(req.billtyRate) : StrictDecimal.zero();
  final delivered =
      req.deliveredRate != null ? _dec(req.deliveredRate) : StrictDecimal.zero();
  amtSum += billty + delivered;

  return TradeCalcTotals(
    qtySum: qtySum.toScale(3).toDouble(),
    amountSum: amtSum.toScale(2).toDouble(),
  );
}

/// Kg for a saved trade line in ledger/table views — matches purchase sheet:
/// classifier first, then [linePhysicalWeightKg] fallback.
double ledgerTradeLineWeightKg({
  required String itemName,
  required String unit,
  required double qty,
  String? catalogDefaultUnit,
  double? catalogDefaultKgPerBag,
  double? kgPerUnit,
  String? boxMode,
  double? itemsPerBox,
  double? weightPerItem,
  double? kgPerBox,
  double? weightPerTin,
}) {
  if (qty <= 0) return 0;
  final ul = unit.trim().toLowerCase();
  final c = UnitClassifier.classify(
    itemName: itemName,
    lineUnit: unit,
    catalogDefaultUnit: catalogDefaultUnit,
    catalogDefaultKgPerBag: catalogDefaultKgPerBag,
  );
  double? kgName = c.kgFromName;
  if (!(c.type == UnitType.singlePack &&
      (ul == 'box' || ul == 'tin' || ul == 'kg'))) {
    kgName = null;
  }
  var kg = classifierLineWeightKg(
    type: c.type,
    qty: qty,
    kgPerUnit: kgPerUnit,
    kgFromName: kgName,
    itemsPerBox: itemsPerBox,
    weightPerItem: weightPerItem,
  );
  // If classifier fell back to "qty as kg/count" for pack units, prefer the
  // explicit physical snapshot logic (kgPerUnit, box/tin fields) instead.
  if (kgPerUnit != null &&
      kgPerUnit > 1e-9 &&
      (ul == 'bag' || ul == 'sack' || ul == 'box' || ul == 'tin') &&
      (kg - qty).abs() < 1e-6) {
    kg = 0;
  }
  if (kg <= 0) {
    kg = linePhysicalWeightKg(
      unit: unit,
      qty: qty,
      kgPerUnit: kgPerUnit,
      boxMode: boxMode,
      itemsPerBox: itemsPerBox,
      weightPerItem: weightPerItem,
      kgPerBox: kgPerBox,
      weightPerTin: weightPerTin,
    );
  }
  return kg;
}

/// Mirrors [TradePurchaseLine.landingGross] without importing app models here.
double ledgerLineLandingGross({
  required double qty,
  required double landingCost,
  double? purchaseRate,
  double? kgPerUnit,
  double? landingCostPerKg,
  double? lineTotal,
}) {
  if (lineTotal != null) return _dec(lineTotal).toDouble();
  if (kgPerUnit != null &&
      landingCostPerKg != null &&
      kgPerUnit > 0 &&
      landingCostPerKg > 0) {
    return (_dec(qty) * _dec(kgPerUnit) * _dec(landingCostPerKg)).toDouble();
  }
  return (_dec(qty) * _dec(purchaseRate ?? landingCost)).toDouble();
}

/// Ledger “rate”: landed gross / qty units, or / (qty × kg_per_unit) when the
/// line is weight-priced ([kgPerUnit] + [landingCostPerKg]).
double ledgerLineDisplayRate({
  required double qty,
  required double landingCost,
  double? purchaseRate,
  double? kgPerUnit,
  double? landingCostPerKg,
  double? lineTotal,
}) {
  final gross = ledgerLineLandingGross(
    qty: qty,
    landingCost: landingCost,
    purchaseRate: purchaseRate,
    kgPerUnit: kgPerUnit,
    landingCostPerKg: landingCostPerKg,
    lineTotal: lineTotal,
  );
  if (qty <= 0 || gross <= 0) return 0;
  final weightPriced = kgPerUnit != null &&
      landingCostPerKg != null &&
      kgPerUnit > 0 &&
      landingCostPerKg > 0;
  if (weightPriced) {
    final denom = qty * kgPerUnit;
    return denom > 0 ? gross / denom : 0;
  }
  return gross / qty;
}
