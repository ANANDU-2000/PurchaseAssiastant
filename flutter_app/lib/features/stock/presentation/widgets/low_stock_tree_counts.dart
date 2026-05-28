import '../../../../core/json_coerce.dart';
import 'low_stock_category_tree.dart';

/// Low / out counts for category or subcategory rows (tab-filtered).
class LowStockDualCounts {
  const LowStockDualCounts({required this.low, required this.out});

  final int low;
  final int out;
}

bool lowStockItemIsOut(Map<String, dynamic> item) {
  final status = (item['stock_status']?.toString() ?? '').toLowerCase();
  final stock = coerceToDouble(item['current_stock']);
  return status == 'out' || stock <= 0;
}

bool lowStockItemIsLow(Map<String, dynamic> item) {
  if (lowStockItemIsOut(item)) return false;
  final status = (item['stock_status']?.toString() ?? '').toLowerCase();
  return status == 'low' || status == 'critical';
}

LowStockDualCounts countLowOutForItems(
  Iterable<Map<String, dynamic>> items,
  LowStockTreeTab tab,
) {
  var low = 0;
  var out = 0;
  for (final item in items) {
    if (!lowStockMatchesTab(item, tab)) continue;
    if (lowStockItemIsOut(item)) {
      out++;
    } else if (lowStockItemIsLow(item)) {
      low++;
    }
  }
  return LowStockDualCounts(low: low, out: out);
}

LowStockDualCounts countLowOutForSubMap(
  Map<String, List<Map<String, dynamic>>> subMap,
  LowStockTreeTab tab,
) {
  final items = subMap.values.expand((list) => list);
  return countLowOutForItems(items, tab);
}

LowStockDualCounts countLowOutForGrouped(
  Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
  String category,
  LowStockTreeTab tab,
) {
  final subMap = grouped[category];
  if (subMap == null) return const LowStockDualCounts(low: 0, out: 0);
  return countLowOutForSubMap(subMap, tab);
}

/// Sort categories: highest out first, then low, then name.
List<String> sortedLowStockCategories(
  Map<String, Map<String, List<Map<String, dynamic>>>> filtered,
  LowStockTreeTab tab,
) {
  final cats = filtered.keys.toList();
  cats.sort((a, b) {
    final ac = countLowOutForGrouped(filtered, a, tab);
    final bc = countLowOutForGrouped(filtered, b, tab);
    final byOut = bc.out.compareTo(ac.out);
    if (byOut != 0) return byOut;
    final byLow = bc.low.compareTo(ac.low);
    if (byLow != 0) return byLow;
    return a.compareTo(b);
  });
  return cats;
}

String? categoryWithHighestOut(
  Map<String, Map<String, List<Map<String, dynamic>>>> filtered,
  LowStockTreeTab tab,
) {
  final sorted = sortedLowStockCategories(filtered, tab);
  if (sorted.isEmpty) return null;
  return sorted.first;
}
