import '../calc_engine.dart';
import '../models/trade_purchase_models.dart';

/// Purchase rows that are not meaningful for catalog / trade intel.
bool purchaseCountsForCatalogIntel(TradePurchase p) {
  final s = p.statusEnum;
  return s != PurchaseStatus.draft && s != PurchaseStatus.cancelled;
}

TradeCalcLine tradeLineToCalc(TradePurchaseLine ln) {
  return TradeCalcLine(
    qty: ln.qty,
    landingCost: ln.landingCost,
    kgPerUnit: ln.kgPerUnit,
    landingCostPerKg: ln.landingCostPerKg,
    taxPercent: ln.taxPercent,
    discountPercent: ln.discount,
  );
}

/// One appearance of [line] on a trade purchase for [catalogItemId].
class ItemTradeHistoryRow {
  const ItemTradeHistoryRow({
    required this.purchaseId,
    required this.humanId,
    required this.purchaseDate,
    required this.supplierName,
    this.supplierPhone,
    this.brokerName,
    this.brokerPhone,
    required this.line,
  });

  final String purchaseId;
  final String humanId;
  final DateTime purchaseDate;
  final String supplierName;
  final String? supplierPhone;
  final String? brokerName;
  final String? brokerPhone;
  final TradePurchaseLine line;

  double get lineTotal => lineMoney(tradeLineToCalc(line));

  /// Display rate: ₹/kg when weight line, else ₹ per line unit.
  String rateLabel() {
    final kpu = line.kgPerUnit;
    final lcpk = line.landingCostPerKg;
    if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
      return '₹${_fmtNum(lcpk)}/kg';
    }
    return '₹${_fmtNum(line.landingCost)}/${line.unit}';
  }
}

String _fmtNum(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

/// All trade lines for this catalog item, newest purchase first.
List<ItemTradeHistoryRow> itemTradeHistoryRows(
  List<TradePurchase> purchases,
  String catalogItemId,
) {
  if (catalogItemId.isEmpty) return [];
  final out = <ItemTradeHistoryRow>[];
  for (final p in purchases) {
    if (!purchaseCountsForCatalogIntel(p)) continue;
    for (final ln in p.lines) {
      if (ln.catalogItemId != catalogItemId) continue;
      out.add(
        ItemTradeHistoryRow(
          purchaseId: p.id,
          humanId: p.humanId,
          purchaseDate: p.purchaseDate,
          supplierName: p.supplierName ?? '—',
          supplierPhone: p.supplierPhone,
          brokerName: p.brokerName,
          brokerPhone: p.brokerPhone,
          line: ln,
        ),
      );
    }
  }
  out.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  return out;
}

/// Per-supplier aggregates from [rows] (same catalog item).
class ItemSupplierIntel {
  const ItemSupplierIntel({
    required this.supplierName,
    required this.deals,
    required this.avgPerKg,
    required this.avgPerUnit,
    required this.hasWeightSamples,
  });

  final String supplierName;
  final int deals;
  final double? avgPerKg;
  final double? avgPerUnit;
  final bool hasWeightSamples;

  String avgLabel() {
    if (hasWeightSamples && avgPerKg != null) {
      return '₹${_fmtNum(avgPerKg!)}/kg avg';
    }
    if (avgPerUnit != null) {
      return '₹${_fmtNum(avgPerUnit!)} avg / unit';
    }
    return '—';
  }
}

/// Group [rows] by supplier; sort by lowest comparable average.
List<ItemSupplierIntel> itemSupplierIntel(List<ItemTradeHistoryRow> rows) {
  final byName = <String, List<ItemTradeHistoryRow>>{};
  for (final r in rows) {
    byName.putIfAbsent(r.supplierName, () => []).add(r);
  }
  final out = <ItemSupplierIntel>[];
  for (final e in byName.entries) {
    final list = e.value;
    final kgPrices = <double>[];
    final unitAvgs = <double>[];
    for (final r in list) {
      final ln = r.line;
      final kpu = ln.kgPerUnit;
      final lcpk = ln.landingCostPerKg;
      if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
        kgPrices.add(lcpk);
      } else if (ln.qty > 0) {
        unitAvgs.add(r.lineTotal / ln.qty);
      }
    }
    final avgKg = kgPrices.isEmpty
        ? null
        : kgPrices.reduce((a, b) => a + b) / kgPrices.length;
    final avgUnit = unitAvgs.isEmpty
        ? null
        : unitAvgs.reduce((a, b) => a + b) / unitAvgs.length;
    out.add(
      ItemSupplierIntel(
        supplierName: e.key,
        deals: list.length,
        avgPerKg: avgKg,
        avgPerUnit: avgUnit,
        hasWeightSamples: kgPrices.isNotEmpty,
      ),
    );
  }
  final anyWeight = out.any((s) => s.hasWeightSamples && s.avgPerKg != null);
  if (anyWeight) {
    out.sort((a, b) {
      if (a.hasWeightSamples != b.hasWeightSamples) {
        return a.hasWeightSamples ? -1 : 1;
      }
      final ak = a.avgPerKg ?? double.infinity;
      final bk = b.avgPerKg ?? double.infinity;
      final c = ak.compareTo(bk);
      if (c != 0) return c;
      return a.supplierName.compareTo(b.supplierName);
    });
  } else {
    out.sort((a, b) {
      final au = a.avgPerUnit ?? double.infinity;
      final bu = b.avgPerUnit ?? double.infinity;
      final c = au.compareTo(bu);
      if (c != 0) return c;
      return a.supplierName.compareTo(b.supplierName);
    });
  }
  return out;
}

bool supplierIntelIsBest(ItemSupplierIntel s, List<ItemSupplierIntel> all) {
  if (all.isEmpty) return false;
  final anyWeight = all.any((x) => x.hasWeightSamples && x.avgPerKg != null);
  if (anyWeight && s.hasWeightSamples && s.avgPerKg != null) {
    final best = all
        .where((x) => x.hasWeightSamples && x.avgPerKg != null)
        .map((x) => x.avgPerKg!)
        .reduce((a, b) => a < b ? a : b);
    return (s.avgPerKg! - best).abs() < 1e-6;
  }
  if (!anyWeight && s.avgPerUnit != null) {
    final best = all
        .where((x) => x.avgPerUnit != null)
        .map((x) => x.avgPerUnit!)
        .reduce((a, b) => a < b ? a : b);
    return (s.avgPerUnit! - best).abs() < 1e-6;
  }
  return false;
}
