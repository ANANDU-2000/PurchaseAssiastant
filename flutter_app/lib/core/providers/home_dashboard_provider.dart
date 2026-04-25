import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';

/// Period chips on the home dashboard. [custom] uses
/// [homeCustomDateRangeProvider] (inclusive start/end dates).
enum HomePeriod { today, week, month, year, custom }

extension HomePeriodX on HomePeriod {
  String get label => switch (this) {
        HomePeriod.today => 'Today',
        HomePeriod.week => 'Week',
        HomePeriod.month => 'Month',
        HomePeriod.year => 'Year',
        HomePeriod.custom => 'Custom',
      };
}

/// Optional inclusive date range when [HomePeriod.custom] is selected.
final homeCustomDateRangeProvider =
    StateProvider<({DateTime start, DateTime endInclusive})?>(
  (_) => null,
);

/// Returns the half-open window `[start, end)` in local date space.
({DateTime start, DateTime end}) homePeriodRange(
  HomePeriod p, {
  DateTime? now,
  ({DateTime start, DateTime endInclusive})? custom,
}) {
  final t = now ?? DateTime.now();
  final endOfDay =
      DateTime(t.year, t.month, t.day).add(const Duration(days: 1));
  if (p == HomePeriod.custom && custom != null) {
    final s = DateTime(
      custom.start.year,
      custom.start.month,
      custom.start.day,
    );
    final e = DateTime(
      custom.endInclusive.year,
      custom.endInclusive.month,
      custom.endInclusive.day,
    ).add(const Duration(days: 1));
    return (start: s, end: e);
  }
  return switch (p) {
    HomePeriod.today => (
        start: DateTime(t.year, t.month, t.day),
        end: endOfDay,
      ),
    HomePeriod.week => (
        start:
            DateTime(t.year, t.month, t.day).subtract(const Duration(days: 6)),
        end: endOfDay,
      ),
    HomePeriod.month => (start: DateTime(t.year, t.month, 1), end: endOfDay),
    HomePeriod.year => (start: DateTime(t.year, 1, 1), end: endOfDay),
    HomePeriod.custom => (
        start: DateTime(t.year, t.month, 1),
        end: endOfDay,
      ),
  };
}

final homePeriodProvider = StateProvider<HomePeriod>((_) => HomePeriod.month);

class CategoryUnitTotals {
  CategoryUnitTotals({this.bags = 0, this.boxes = 0, this.tins = 0});
  double bags;
  double boxes;
  double tins;

  bool get isEmpty => bags == 0 && boxes == 0 && tins == 0;
}

class CategoryItemStat {
  const CategoryItemStat({
    required this.name,
    required this.qty,
    required this.unit,
    required this.amount,
  });

  final String name;
  final double qty;
  final String unit;
  final double amount;
}

class CategoryStat {
  const CategoryStat({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmount,
    required this.totalQty,
    required this.units,
    required this.items,
  });

  final String categoryId;
  final String categoryName;
  final double totalAmount;
  final double totalQty;
  final CategoryUnitTotals units;
  /// Sorted by amount (desc) — first is the category top item.
  final List<CategoryItemStat> items;
}

/// One row in the “Subcategory” (CategoryType) view — `label` is e.g. "Rice — Biriyani".
class SubcategoryStat {
  const SubcategoryStat({
    required this.id,
    required this.label,
    required this.totalAmount,
    required this.totalQty,
  });

  final String id;
  final String label;
  final double totalAmount;
  final double totalQty;
}

/// One slice/row in the “Items” donut and breakdown list.
class ItemSliceStat {
  const ItemSliceStat({
    required this.name,
    this.catalogItemId,
    required this.totalAmount,
    required this.totalQty,
    required this.unit,
  });

  final String name;
  final String? catalogItemId;
  final double totalAmount;
  final double totalQty;
  final String unit;
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.period,
    required this.totalPurchase,
    required this.totalQtyAllLines,
    required this.totalKg,
    required this.totalBags,
    required this.totalBoxes,
    required this.totalTins,
    required this.purchaseCount,
    required this.categories,
    required this.subcategories,
    required this.itemSlices,
  });

  final HomePeriod period;
  final double totalPurchase;
  /// Sum of line `qty` in range (for display next to purchase count).
  final double totalQtyAllLines;
  final double totalKg;
  final double totalBags;
  final double totalBoxes;
  final double totalTins;
  final int purchaseCount;
  final List<CategoryStat> categories;
  final List<SubcategoryStat> subcategories;
  final List<ItemSliceStat> itemSlices;

  bool get isEmpty => purchaseCount == 0;

  static const empty = HomeDashboardData(
    period: HomePeriod.month,
    totalPurchase: 0,
    totalQtyAllLines: 0,
    totalKg: 0,
    totalBags: 0,
    totalBoxes: 0,
    totalTins: 0,
    purchaseCount: 0,
    categories: [],
    subcategories: [],
    itemSlices: [],
  );
}

String _apiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Server-side trade report snapshot (line amounts + [trade_query] statuses) for one date window.
HomeDashboardData homeDashboardDataFromApiSnapshot(
  HomePeriod period,
  Map<String, dynamic> snap,
) {
  final summary = (snap['summary'] is Map) ? snap['summary']! as Map : const {};
  final unitTotals =
      (snap['unit_totals'] is Map) ? snap['unit_totals']! as Map : const {};
  final deals = (summary['deals'] as num?)?.toInt() ?? 0;
  final totalPurchase = (summary['total_purchase'] as num?)?.toDouble() ?? 0.0;
  final totalQtyAllLines = (summary['total_qty'] as num?)?.toDouble() ?? 0.0;
  final totalKg = (unitTotals['total_kg'] as num?)?.toDouble() ?? 0.0;
  final totalBags = (unitTotals['total_bags'] as num?)?.toDouble() ?? 0.0;
  final totalBoxes = (unitTotals['total_boxes'] as num?)?.toDouble() ?? 0.0;
  final totalTins = (unitTotals['total_tins'] as num?)?.toDouble() ?? 0.0;

  final rawCats = snap['categories'];
  final categories = <CategoryStat>[];
  if (rawCats is List) {
    for (final c in rawCats) {
      if (c is! Map) continue;
      final m = Map<String, dynamic>.from(c);
      final u = m['units'];
      final umap = u is Map ? Map<String, dynamic>.from(u) : const {};
      final itemRows = <CategoryItemStat>[];
      final items = m['items'];
      if (items is List) {
        for (final it in items) {
          if (it is! Map) continue;
          final im = Map<String, dynamic>.from(it);
          itemRows.add(
            CategoryItemStat(
              name: im['name']?.toString() ?? '—',
              qty: (im['qty'] as num?)?.toDouble() ?? 0.0,
              unit: im['unit']?.toString() ?? '—',
              amount: (im['amount'] as num?)?.toDouble() ?? 0.0,
            ),
          );
        }
      }
      itemRows.sort((a, b) => b.amount.compareTo(a.amount));
      categories.add(
        CategoryStat(
          categoryId: m['category_id']?.toString() ?? '_uncat',
          categoryName: m['category_name']?.toString() ?? 'Uncategorised',
          totalAmount: (m['total_purchase'] as num?)?.toDouble() ?? 0.0,
          totalQty: (m['total_qty'] as num?)?.toDouble() ?? 0.0,
          units: CategoryUnitTotals(
            bags: (umap['bags'] as num?)?.toDouble() ?? 0.0,
            boxes: (umap['boxes'] as num?)?.toDouble() ?? 0.0,
            tins: (umap['tins'] as num?)?.toDouble() ?? 0.0,
          ),
          items: itemRows,
        ),
      );
    }
  }
  categories.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final subcategories = <SubcategoryStat>[];
  final rawTypes = snap['subcategories'];
  if (rawTypes is List) {
    for (final t in rawTypes) {
      if (t is! Map) continue;
      final tm = Map<String, dynamic>.from(t);
      final cat = tm['category_name']?.toString() ?? '';
      final tname = tm['type_name']?.toString() ?? '';
      final label = tname.isEmpty ? '$cat — No type' : '$cat — $tname';
      final id = '$cat|${tm['type_name'] ?? 'none'}';
      subcategories.add(
        SubcategoryStat(
          id: id,
          label: label,
          totalAmount: (tm['total_purchase'] as num?)?.toDouble() ?? 0.0,
          totalQty: (tm['total_qty'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }
  }
  subcategories.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final itemSlices = <ItemSliceStat>[];
  final rawItems = snap['item_slices'];
  if (rawItems is List) {
    for (final it in rawItems) {
      if (it is! Map) continue;
      final im = Map<String, dynamic>.from(it);
      itemSlices.add(
        ItemSliceStat(
          name: im['item_name']?.toString() ?? '—',
          catalogItemId: im['catalog_item_id']?.toString(),
          totalAmount: (im['total_purchase'] as num?)?.toDouble() ?? 0.0,
          totalQty: (im['total_qty'] as num?)?.toDouble() ?? 0.0,
          unit: im['unit']?.toString() ?? '—',
        ),
      );
    }
  }
  itemSlices.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  return HomeDashboardData(
    period: period,
    totalPurchase: totalPurchase,
    totalQtyAllLines: totalQtyAllLines,
    totalKg: totalKg,
    totalBags: totalBags,
    totalBoxes: totalBoxes,
    totalTins: totalTins,
    purchaseCount: deals,
    categories: categories,
    subcategories: subcategories,
    itemSlices: itemSlices,
  );
}

/// Aggregated snapshot: server [tradeDashboardSnapshot] — same numbers as report APIs.
/// To match Analytics KPI for a period, align calendar `from`/`to` with
/// the analytics date range in `lib/core/providers/analytics_kpi_provider.dart`.
final homeDashboardDataProvider =
    FutureProvider.autoDispose<HomeDashboardData>((ref) async {
  ref.keepAlive();
  final period = ref.watch(homePeriodProvider);
  final custom = ref.watch(homeCustomDateRangeProvider);
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return HomeDashboardData.empty;
  }
  final range = homePeriodRange(period, now: DateTime.now(), custom: custom);
  final lastInclusive =
      range.end.subtract(const Duration(milliseconds: 1));
  final from = _apiDate(range.start);
  final to = _apiDate(lastInclusive);
  final snap = await ref.read(hexaApiProvider).tradeDashboardSnapshot(
        businessId: session.primaryBusiness.id,
        from: from,
        to: to,
      );
  return homeDashboardDataFromApiSnapshot(period, snap);
});

/// Pure function — safe to call from tests.
HomeDashboardData aggregateHomeDashboard({
  required HomePeriod period,
  required List<TradePurchase> purchases,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> categories,
  DateTime? now,
  ({DateTime start, DateTime endInclusive})? custom,
}) {
  final range = homePeriodRange(period, now: now, custom: custom);
  return _aggregate(
    period: period,
    purchases: purchases,
    items: items,
    categories: categories,
    rangeStart: range.start,
    rangeEnd: range.end,
  );
}

/// Matches backend `_trade_line_amount_expr`: weight lines use qty × kg_per_unit × landing_cost_per_kg.
double _lineTradeAmount(TradePurchaseLine ln) {
  final kpu = ln.kgPerUnit;
  final lcpk = ln.landingCostPerKg;
  if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
    return ln.qty * kpu * lcpk;
  }
  return ln.qty * ln.landingCost;
}

double _lineKg(TradePurchaseLine ln) {
  if (ln.kgPerUnit != null &&
      ln.kgPerUnit! > 0 &&
      ln.landingCostPerKg != null &&
      ln.landingCostPerKg! > 0) {
    return ln.qty * ln.kgPerUnit!;
  }
  final u = ln.unit.toUpperCase().trim();
  if (u == 'KG' || u.endsWith('KG')) return ln.qty;
  if (u.contains('BAG')) {
    final k = ln.defaultKgPerBag ?? ln.kgPerUnit;
    if (k != null && k > 0) return ln.qty * k;
  }
  return 0;
}

HomeDashboardData _aggregate({
  required HomePeriod period,
  required List<TradePurchase> purchases,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> categories,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final itemById = <String, Map<String, dynamic>>{
    for (final m in items)
      if (m['id'] != null) m['id'].toString(): m,
  };
  final catNameById = <String, String>{
    for (final c in categories)
      if (c['id'] != null)
        c['id'].toString(): (c['name']?.toString() ?? 'Uncategorised'),
  };

  var totalPurchase = 0.0;
  var totalQtyAllLines = 0.0;
  var totalKg = 0.0;
  var totalBags = 0.0;
  var totalBoxes = 0.0;
  var totalTins = 0.0;
  var purchaseCount = 0;

  final catAgg = <String, _CatAgg>{};
  final typeAgg = <String, _TypeAgg>{};
  final globalItem = <String, _ItemAgg>{};

  for (final p in purchases) {
    if (p.purchaseDate.isBefore(rangeStart) ||
        !p.purchaseDate.isBefore(rangeEnd)) {
      continue;
    }

    purchaseCount++;
    totalPurchase += p.totalAmount;

    for (final ln in p.lines) {
      final amt = _lineTradeAmount(ln);
      totalQtyAllLines += ln.qty;
      totalKg += _lineKg(ln);

      final u = ln.unit.toUpperCase();
      if (u.contains('BAG')) totalBags += ln.qty;
      if (u.contains('BOX')) totalBoxes += ln.qty;
      if (u.contains('TIN')) totalTins += ln.qty;

      String catId = '_uncat';
      String catName = 'Uncategorised';
      final ci = ln.catalogItemId;
      final Map<String, dynamic>? item =
          (ci != null && ci.isNotEmpty) ? itemById[ci] : null;
      if (item != null) {
        final cid = item['category_id']?.toString();
        if (cid != null && cid.isNotEmpty) {
          catId = cid;
          catName = catNameById[cid] ?? 'Uncategorised';
        }
      }
      final tid = item?['type_id']?.toString() ?? 'none';
      final typeKey = '$catId|$tid';
      final tname = (item?['type_name']?.toString() ?? '').trim();
      final typeLabel = item == null
          ? 'Uncategorised'
          : (tname.isEmpty ? '$catName — No type' : '$catName — $tname');
      typeAgg
          .putIfAbsent(
            typeKey,
            () => _TypeAgg(id: typeKey, label: typeLabel),
          )
          .add(amt, ln.qty);

      final agg = catAgg.putIfAbsent(
        catId,
        () => _CatAgg(id: catId, name: catName),
      );
      agg.totalAmount += amt;
      agg.totalQty += ln.qty;

      if (u.contains('BAG')) agg.units.bags += ln.qty;
      if (u.contains('BOX')) agg.units.boxes += ln.qty;
      if (u.contains('TIN')) agg.units.tins += ln.qty;

      final itemKey = ln.itemName.trim().isEmpty ? '—' : ln.itemName.trim();
      final slot = agg.itemMap.putIfAbsent(
        itemKey,
        () => _ItemAgg(name: itemKey, unit: ln.unit),
      );
      slot.qty += ln.qty;
      slot.amount += amt;
      if (ci != null && ci.isNotEmpty) slot.catalogItemId ??= ci;

      final gk = (ci != null && ci.isNotEmpty) ? 'id:$ci' : 'n:$itemKey';
      final g = globalItem.putIfAbsent(
        gk,
        () => _ItemAgg(name: itemKey, unit: ln.unit),
      );
      g.qty += ln.qty;
      g.amount += amt;
      if (ci != null && ci.isNotEmpty) g.catalogItemId ??= ci;
    }
  }

  final cats = <CategoryStat>[];
  for (final a in catAgg.values) {
    final itemRows = <CategoryItemStat>[];
    for (final it in a.itemMap.values) {
      if (it.qty <= 0 && it.amount <= 0) continue;
      itemRows.add(CategoryItemStat(
        name: it.name,
        qty: it.qty,
        unit: it.unit,
        amount: it.amount,
      ));
    }
    itemRows.sort((x, y) => y.amount.compareTo(x.amount));
    cats.add(CategoryStat(
      categoryId: a.id,
      categoryName: a.name,
      totalAmount: a.totalAmount,
      totalQty: a.totalQty,
      units: a.units,
      items: itemRows,
    ));
  }
  cats.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final subRows = <SubcategoryStat>[];
  for (final t in typeAgg.values) {
    if (t.totalAmount <= 0) continue;
    subRows.add(SubcategoryStat(
      id: t.id,
      label: t.label,
      totalAmount: t.totalAmount,
      totalQty: t.totalQty,
    ));
  }
  subRows.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final itemRows = <ItemSliceStat>[];
  for (final it in globalItem.values) {
    if (it.qty <= 0 && it.amount <= 0) continue;
    itemRows.add(ItemSliceStat(
      name: it.name,
      totalAmount: it.amount,
      totalQty: it.qty,
      unit: it.unit,
    ));
  }
  itemRows.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  return HomeDashboardData(
    period: period,
    totalPurchase: totalPurchase,
    totalQtyAllLines: totalQtyAllLines,
    totalKg: totalKg,
    totalBags: totalBags,
    totalBoxes: totalBoxes,
    totalTins: totalTins,
    purchaseCount: purchaseCount,
    categories: cats,
    subcategories: subRows,
    itemSlices: itemRows,
  );
}

class _CatAgg {
  _CatAgg({required this.id, required this.name});
  final String id;
  final String name;
  double totalAmount = 0;
  double totalQty = 0;
  final CategoryUnitTotals units = CategoryUnitTotals();
  final Map<String, _ItemAgg> itemMap = {};
}

class _ItemAgg {
  _ItemAgg({required this.name, required this.unit});
  final String name;
  final String unit;
  String? catalogItemId;
  double qty = 0;
  double amount = 0;
}

class _TypeAgg {
  _TypeAgg({required this.id, required this.label});
  final String id;
  final String label;
  double totalAmount = 0;
  double totalQty = 0;

  void add(double amt, double q) {
    totalAmount += amt;
    totalQty += q;
  }
}
