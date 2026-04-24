import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';

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

class HomeDashboardData {
  const HomeDashboardData({
    required this.period,
    required this.totalPurchase,
    required this.totalKg,
    required this.totalBags,
    required this.totalBoxes,
    required this.totalTins,
    required this.purchaseCount,
    required this.categories,
    required this.topItemName,
    required this.topItemAmount,
    required this.topItemUnit,
    required this.topSupplierName,
    required this.topSupplierAmount,
    required this.mostUsedUnit,
  });

  final HomePeriod period;
  final double totalPurchase;
  final double totalKg;
  final double totalBags;
  final double totalBoxes;
  final double totalTins;
  final int purchaseCount;
  final List<CategoryStat> categories;
  final String? topItemName;
  final double topItemAmount;
  final String topItemUnit;
  final String? topSupplierName;
  final double topSupplierAmount;
  final String? mostUsedUnit;

  bool get isEmpty => purchaseCount == 0;

  static const empty = HomeDashboardData(
    period: HomePeriod.month,
    totalPurchase: 0,
    totalKg: 0,
    totalBags: 0,
    totalBoxes: 0,
    totalTins: 0,
    purchaseCount: 0,
    categories: [],
    topItemName: null,
    topItemAmount: 0,
    topItemUnit: '',
    topSupplierName: null,
    topSupplierAmount: 0,
    mostUsedUnit: null,
  );
}

/// Aggregated snapshot for the home dashboard. Fed by trade purchases + catalog;
/// window comes from [homePeriodProvider] + optional custom range.
final homeDashboardDataProvider =
    Provider.autoDispose<AsyncValue<HomeDashboardData>>((ref) {
  final period = ref.watch(homePeriodProvider);
  final custom = ref.watch(homeCustomDateRangeProvider);
  final purchasesAsync = ref.watch(tradePurchasesParsedProvider);
  final itemsAsync = ref.watch(catalogItemsListProvider);
  final catsAsync = ref.watch(itemCategoriesListProvider);

  if (purchasesAsync.isLoading &&
      !purchasesAsync.hasValue &&
      !purchasesAsync.hasError) {
    return const AsyncValue<HomeDashboardData>.loading();
  }
  if (purchasesAsync.hasError && !purchasesAsync.hasValue) {
    return AsyncValue<HomeDashboardData>.error(
      purchasesAsync.error!,
      purchasesAsync.stackTrace ?? StackTrace.current,
    );
  }

  final purchases = purchasesAsync.valueOrNull ?? const <TradePurchase>[];
  final items = itemsAsync.valueOrNull ?? const <Map<String, dynamic>>[];
  final cats = catsAsync.valueOrNull ?? const <Map<String, dynamic>>[];

  final range = homePeriodRange(period, now: DateTime.now(), custom: custom);
  return AsyncValue.data(_aggregate(
    period: period,
    purchases: purchases,
    items: items,
    categories: cats,
    rangeStart: range.start,
    rangeEnd: range.end,
  ));
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

double _lineLandingAmount(TradePurchaseLine ln) => ln.qty * ln.landingCost;

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
  var totalKg = 0.0;
  var totalBags = 0.0;
  var totalBoxes = 0.0;
  var totalTins = 0.0;
  var purchaseCount = 0;

  final catAgg = <String, _CatAgg>{};
  final globalItem = <String, _ItemAgg>{};
  final supplierSpend = <String, _SupAgg>{};
  final unitCounts = <String, int>{};

  for (final p in purchases) {
    if (p.purchaseDate.isBefore(rangeStart) ||
        !p.purchaseDate.isBefore(rangeEnd)) {
      continue;
    }

    purchaseCount++;
    totalPurchase += p.totalAmount;

    final supKey = (p.supplierName != null && p.supplierName!.trim().isNotEmpty)
        ? p.supplierName!.trim()
        : (p.supplierId ?? 'Unknown supplier');
    supplierSpend.putIfAbsent(supKey, () => _SupAgg(name: supKey)).amount +=
        p.totalAmount;

    for (final ln in p.lines) {
      final amt = _lineLandingAmount(ln);
      totalKg += _lineKg(ln);

      final u = ln.unit.toUpperCase();
      if (u.contains('BAG')) totalBags += ln.qty;
      if (u.contains('BOX')) totalBoxes += ln.qty;
      if (u.contains('TIN')) totalTins += ln.qty;

      final un = ln.unit.trim().isEmpty ? '—' : ln.unit.trim().toUpperCase();
      unitCounts[un] = (unitCounts[un] ?? 0) + 1;

      String catId = '_uncat';
      String catName = 'Uncategorised';
      final ci = ln.catalogItemId;
      if (ci != null && ci.isNotEmpty) {
        final item = itemById[ci];
        final cid = item?['category_id']?.toString();
        if (cid != null && cid.isNotEmpty) {
          catId = cid;
          catName = catNameById[cid] ?? 'Uncategorised';
        }
      }
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

      final g = globalItem.putIfAbsent(
        itemKey,
        () => _ItemAgg(name: itemKey, unit: ln.unit),
      );
      g.qty += ln.qty;
      g.amount += amt;
    }
  }

  String? topItemName;
  var topItemAmount = 0.0;
  var topItemUnit = '';
  for (final it in globalItem.values) {
    if (it.amount > topItemAmount) {
      topItemAmount = it.amount;
      topItemName = it.name;
      topItemUnit = it.unit;
    }
  }

  String? topSupplierName;
  var topSupplierAmount = 0.0;
  for (final s in supplierSpend.values) {
    if (s.amount > topSupplierAmount) {
      topSupplierAmount = s.amount;
      topSupplierName = s.name;
    }
  }

  String? mostUsedUnit;
  var bestU = 0;
  for (final e in unitCounts.entries) {
    if (e.value > bestU) {
      bestU = e.value;
      mostUsedUnit = e.key;
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

  return HomeDashboardData(
    period: period,
    totalPurchase: totalPurchase,
    totalKg: totalKg,
    totalBags: totalBags,
    totalBoxes: totalBoxes,
    totalTins: totalTins,
    purchaseCount: purchaseCount,
    categories: cats,
    topItemName: topItemName,
    topItemAmount: topItemAmount,
    topItemUnit: topItemUnit,
    topSupplierName: topSupplierName,
    topSupplierAmount: topSupplierAmount,
    mostUsedUnit: mostUsedUnit,
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
  double qty = 0;
  double amount = 0;
}

class _SupAgg {
  _SupAgg({required this.name});
  final String name;
  double amount = 0;
}
