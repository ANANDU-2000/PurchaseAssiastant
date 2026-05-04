import '../models/trade_purchase_models.dart';
import '../utils/trade_purchase_commission.dart';

/// Bag / Box / Tin — lines that do not match are excluded from aggregates.
enum ReportPackKind {
  bag,
  box,
  tin,
}

/// Single source of truth for Reports: classify only by [TradePurchaseLine.unit].
ReportPackKind? reportClassifyPackKind(TradePurchaseLine l) {
  final u = l.unit.trim().toUpperCase();
  if (u == 'BAG' || u == 'SACK' || u.contains('BAG') || u.contains('SACK')) {
    return ReportPackKind.bag;
  }
  if (u == 'BOX' || u.contains('BOX')) return ReportPackKind.box;
  if (u == 'TIN' || u.contains('TIN')) return ReportPackKind.tin;
  return null;
}

/// Kg from explicit fields; uses persisted [TradePurchaseLine.totalWeight] only when
/// geometry fields cannot yield a positive value (server-computed truth).
double reportLineKg(TradePurchaseLine l) {
  final k = reportClassifyPackKind(l);
  if (k == null) return 0;
  final q = l.qty;
  if (q <= 0) return 0;

  double tw() {
    final t = l.totalWeight;
    if (t != null && t > 0) return t;
    return 0;
  }

  switch (k) {
    case ReportPackKind.bag:
      final kpu = l.kgPerUnit;
      if (kpu != null && kpu > 0) return q * kpu;
      return tw();
    case ReportPackKind.box:
      final ipb = l.itemsPerBox;
      final wpi = l.weightPerItem;
      if (ipb != null && wpi != null && ipb > 0 && wpi > 0) {
        return q * ipb * wpi;
      }
      final kpb = l.kgPerBox;
      if (kpb != null && kpb > 0) return q * kpb;
      return tw();
    case ReportPackKind.tin:
      final wt = l.weightPerTin;
      if (wt != null && wt > 0) return q * wt;
      final kpu = l.kgPerUnit;
      if (kpu != null && kpu > 0) return q * kpu;
      return tw();
  }
}

double reportLineAmountInr(TradePurchaseLine l) => l.landingGross;

class TradeReportItemRow {
  TradeReportItemRow({
    required this.key,
    required this.name,
  });

  final String key;
  final String name;
  double bags = 0;
  double boxes = 0;
  double tins = 0;
  double kg = 0;
  double amountInr = 0;
  final Set<String> dealIds = {};
}

class TradeReportSupplierRow {
  TradeReportSupplierRow({required this.key, required this.name});

  final String key;
  final String name;
  final Set<String> dealIds = {};
  double bagQty = 0;
  double bagKg = 0;
}

class TradeReportBrokerRow {
  TradeReportBrokerRow({required this.key, required this.name});

  final String key;
  final String name;
  double commission = 0;
  final Set<String> purchaseIds = {};
}

class TradeReportTotals {
  const TradeReportTotals({
    required this.inr,
    required this.bags,
    required this.boxes,
    required this.tins,
    required this.kg,
    required this.deals,
  });

  final double inr;
  final double bags;
  final double boxes;
  final double tins;
  final double kg;
  final int deals;

  static const zero = TradeReportTotals(
    inr: 0,
    bags: 0,
    boxes: 0,
    tins: 0,
    kg: 0,
    deals: 0,
  );
}

class TradeReportAgg {
  TradeReportAgg({
    required this.totals,
    required this.itemsBag,
    required this.itemsBox,
    required this.itemsTin,
    required this.suppliers,
    required this.brokers,
    required this.purchasesIncluded,
  });

  final TradeReportTotals totals;

  /// Item rows when unit filter is Bag (columns: Bags, Kg, Amount).
  final List<TradeReportItemRow> itemsBag;

  /// Item rows for Box filter.
  final List<TradeReportItemRow> itemsBox;

  /// Item rows for Tin filter.
  final List<TradeReportItemRow> itemsTin;

  final List<TradeReportSupplierRow> suppliers;
  final List<TradeReportBrokerRow> brokers;

  /// Purchases that contributed at least one classified line (for PDF / detail).
  final List<TradePurchase> purchasesIncluded;
}

String reportItemKey(TradePurchaseLine l) {
  final cid = (l.catalogItemId ?? '').trim();
  if (cid.isNotEmpty) return 'cid:$cid';
  return 'n:${l.itemName.trim().toLowerCase()}';
}

String reportSupplierKey(TradePurchase p) {
  final sid = (p.supplierId ?? '').trim();
  final nm = (p.supplierName ?? '').trim().isEmpty ? '-' : p.supplierName!.trim();
  return sid.isNotEmpty ? 'sid:$sid' : 'sn:${nm.toLowerCase()}';
}

String reportSupplierTitle(TradePurchase p) =>
    (p.supplierName ?? '').trim().isEmpty ? '-' : p.supplierName!.trim();

/// When [onlyKind] is set, totals and item lists only include lines of that kind.
/// Suppliers: **deals** = any classified line; **bagQty/bagKg** only from BAG lines.
/// Brokers: commission from full purchase when it has classified lines and a broker.
TradeReportAgg buildTradeReportAgg(
  List<TradePurchase> purchases, {
  ReportPackKind? onlyKind,
}) {
  final bagMap = <String, TradeReportItemRow>{};
  final boxMap = <String, TradeReportItemRow>{};
  final tinMap = <String, TradeReportItemRow>{};
  final supMap = <String, TradeReportSupplierRow>{};
  final broMap = <String, TradeReportBrokerRow>{};

  var sumInr = 0.0;
  var sumBags = 0.0;
  var sumBoxes = 0.0;
  var sumTins = 0.0;
  var sumKg = 0.0;
  final dealIds = <String>{};
  final includedPurchases = <TradePurchase>[];

  for (final p in purchases) {
    var purchaseTouchesClassified = false;

    final bid = (p.brokerId ?? '').trim();
    final bnm = (p.brokerName ?? '').trim();
    TradeReportBrokerRow? broRow;
    if (bid.isNotEmpty || bnm.isNotEmpty) {
      final bk = bid.isNotEmpty ? 'bid:$bid' : 'bn:${bnm.toLowerCase()}';
      broRow = broMap.putIfAbsent(
        bk,
        () => TradeReportBrokerRow(
          key: bk,
          name: bnm.isEmpty ? 'Broker' : bnm,
        ),
      );
    }

    final sk = reportSupplierKey(p);
    final sup = supMap.putIfAbsent(
      sk,
      () => TradeReportSupplierRow(key: sk, name: reportSupplierTitle(p)),
    );

    for (final l in p.lines) {
      final pk = reportClassifyPackKind(l);
      if (pk == null) continue;
      if (onlyKind != null && pk != onlyKind) continue;

      purchaseTouchesClassified = true;
      dealIds.add(p.id);
      sup.dealIds.add(p.id);

      final kg = reportLineKg(l);
      final amt = reportLineAmountInr(l);
      sumInr += amt;
      sumKg += kg;

      final ik = reportItemKey(l);
      final title = l.itemName.trim().isEmpty ? '—' : l.itemName.trim();

      Map<String, TradeReportItemRow> targetMap;
      switch (pk) {
        case ReportPackKind.bag:
          targetMap = bagMap;
          sumBags += l.qty;
          sup.bagQty += l.qty;
          sup.bagKg += kg;
        case ReportPackKind.box:
          targetMap = boxMap;
          sumBoxes += l.qty;
        case ReportPackKind.tin:
          targetMap = tinMap;
          sumTins += l.qty;
      }

      final row = targetMap.putIfAbsent(
        ik,
        () => TradeReportItemRow(key: ik, name: title),
      );
      row.dealIds.add(p.id);
      row.kg += kg;
      row.amountInr += amt;
      switch (pk) {
        case ReportPackKind.bag:
          row.bags += l.qty;
        case ReportPackKind.box:
          row.boxes += l.qty;
        case ReportPackKind.tin:
          row.tins += l.qty;
      }

      if (broRow != null && broRow.purchaseIds.add(p.id)) {
        broRow.commission += tradePurchaseCommissionInr(p);
      }
    }

    if (purchaseTouchesClassified) {
      includedPurchases.add(p);
    }
  }

  List<TradeReportItemRow> sortItems(Map<String, TradeReportItemRow> m, ReportPackKind k) {
    final list = m.values.toList();
    list.sort((a, b) {
      if (k == ReportPackKind.bag && (a.kg - b.kg).abs() > 1e-9) {
        return b.kg.compareTo(a.kg);
      }
      final qa = switch (k) {
        ReportPackKind.bag => a.bags,
        ReportPackKind.box => a.boxes,
        ReportPackKind.tin => a.tins,
      };
      final qb = switch (k) {
        ReportPackKind.bag => b.bags,
        ReportPackKind.box => b.boxes,
        ReportPackKind.tin => b.tins,
      };
      if ((qa - qb).abs() > 1e-9) return qb.compareTo(qa);
      return a.name.compareTo(b.name);
    });
    return list;
  }

  final suppliers = supMap.values.where((s) => s.dealIds.isNotEmpty).toList()
    ..sort((a, b) {
      final d = b.dealIds.length.compareTo(a.dealIds.length);
      if (d != 0) return d;
      return a.name.compareTo(b.name);
    });

  final brokers = broMap.values.toList()
    ..sort((a, b) {
      final c = b.commission.compareTo(a.commission);
      if (c != 0) return c;
      final d = b.purchaseIds.length.compareTo(a.purchaseIds.length);
      if (d != 0) return d;
      return a.name.compareTo(b.name);
    });

  return TradeReportAgg(
    totals: TradeReportTotals(
      inr: sumInr,
      bags: sumBags,
      boxes: sumBoxes,
      tins: sumTins,
      kg: sumKg,
      deals: dealIds.length,
    ),
    itemsBag: sortItems(bagMap, ReportPackKind.bag),
    itemsBox: sortItems(boxMap, ReportPackKind.box),
    itemsTin: sortItems(tinMap, ReportPackKind.tin),
    suppliers: suppliers,
    brokers: brokers,
    purchasesIncluded: includedPurchases,
  );
}

/// Classified-line spend grouped by catalog category (for Reports → Categories).
class TradeReportCategoryRow {
  TradeReportCategoryRow({
    required this.categoryKey,
    required this.name,
  });

  final String categoryKey;
  final String name;
  double amountInr = 0;
  double kg = 0;
  double bagQty = 0;
  final Set<String> dealIds = {};
}

/// Maps each catalog item id to its category id, and category id → display name.
List<TradeReportCategoryRow> buildTradeReportCategoryRows(
  List<TradePurchase> purchases, {
  required Map<String, String> catalogItemIdToCategoryId,
  required Map<String, String> categoryIdToName,
}) {
  const unc = '_uncategorized';
  final m = <String, TradeReportCategoryRow>{};

  for (final p in purchases) {
    for (final l in p.lines) {
      final pk = reportClassifyPackKind(l);
      if (pk == null) continue;
      final cid = (l.catalogItemId ?? '').trim();
      final catId =
          cid.isEmpty ? unc : (catalogItemIdToCategoryId[cid] ?? unc);
      final nm = catId == unc
          ? 'Uncategorized'
          : (categoryIdToName[catId] ?? 'Category');
      final row = m.putIfAbsent(
        catId,
        () => TradeReportCategoryRow(categoryKey: catId, name: nm),
      );
      row.dealIds.add(p.id);
      row.amountInr += reportLineAmountInr(l);
      row.kg += reportLineKg(l);
      if (pk == ReportPackKind.bag) {
        row.bagQty += l.qty;
      }
    }
  }

  final list = m.values.toList()
    ..sort((a, b) {
      final c = b.amountInr.compareTo(a.amountInr);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
  return list;
}

/// Statement row for PDF/export (every classified line).
class TradeReportStatementLine {
  TradeReportStatementLine({
    required this.date,
    required this.supplierName,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.kg,
    required this.rate,
    required this.amountInr,
  });

  final DateTime date;
  final String supplierName;
  final String itemName;
  final double qty;
  final String unit;
  final double kg;
  final double rate;
  final double amountInr;
}

List<TradeReportStatementLine> buildTradeStatementLines(
    List<TradePurchase> purchases) {
  final out = <TradeReportStatementLine>[];
  for (final p in purchases) {
    final sup = reportSupplierTitle(p);
    for (final l in p.lines) {
      if (reportClassifyPackKind(l) == null) continue;
      final kg = reportLineKg(l);
      final amt = reportLineAmountInr(l);
      final rate = l.qty > 0 ? amt / l.qty : 0.0;
      out.add(
        TradeReportStatementLine(
          date: p.purchaseDate,
          supplierName: sup,
          itemName: l.itemName.trim().isEmpty ? '—' : l.itemName.trim(),
          qty: l.qty,
          unit: l.unit.trim().toUpperCase(),
          kg: kg,
          rate: rate,
          amountInr: amt,
        ),
      );
    }
  }
  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    if (c != 0) return c;
    return a.itemName.compareTo(b.itemName);
  });
  return out;
}
