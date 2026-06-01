import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/operations_providers.dart';
import '../filters/reports_filter_state.dart';
import 'reports_stock_models.dart';
import 'reports_stock_status.dart';

final reportsStockChipFilterProvider = StateProvider<ReportsStockChipFilter>(
  (ref) => ReportsStockChipFilter.all,
);

final reportsStockSortProvider = StateProvider<ReportsStockSort>(
  (ref) => ReportsStockSort.highestStock,
);

final reportsStockIntelItemsProvider =
    Provider<List<ReportsStockIntelItem>>((ref) {
  final ops = ref.watch(operationalReportsProvider).valueOrNull;
  if (ops == null) return const [];
  final rows = (ops['items'] as List?) ?? const [];
  return rows
      .whereType<Map>()
      .map((e) => ReportsStockIntelItem.fromMap(Map<String, dynamic>.from(e)))
      .toList();
});

final reportsStockSummaryProvider = Provider<ReportsStockSummary>((ref) {
  final ops = ref.watch(operationalReportsProvider).valueOrNull;
  final summaryRaw = ops?['summary'];
  if (summaryRaw is Map) {
    return ReportsStockSummary.fromMap(Map<String, dynamic>.from(summaryRaw));
  }
  // Fallback when API lacks summary (older backend).
  final items = ref.watch(reportsStockIntelItemsProvider);
  var active = 0, slow = 0, dead = 0, fast = 0, all = 0;
  for (final item in items) {
    if (item.currentStock <= 0) continue;
    all++;
    switch (item.status) {
      case ReportsStockMovementStatus.active:
        active++;
      case ReportsStockMovementStatus.slow:
      case ReportsStockMovementStatus.verySlow:
        slow++;
      case ReportsStockMovementStatus.dead:
        dead++;
      case ReportsStockMovementStatus.fast:
        fast++;
      default:
        break;
    }
  }
  return ReportsStockSummary(
    all: all,
    active: active,
    slow: slow,
    dead: dead,
    fast: fast,
  );
});

final filteredReportsStockItemsProvider =
    Provider<List<ReportsStockIntelItem>>((ref) {
  final items = ref.watch(reportsStockIntelItemsProvider);
  final chip = ref.watch(reportsStockChipFilterProvider);
  final sort = ref.watch(reportsStockSortProvider);
  final query = ref.watch(reportsFilterProvider).searchQuery.trim().toLowerCase();

  var list = items.where((item) {
    if (!item.matchesChip(chip)) return false;
    if (query.isEmpty) return true;
    final name = item.name.toLowerCase();
    final cat = item.category.toLowerCase();
    final code = (item.itemCode ?? '').toLowerCase();
    return name.contains(query) || cat.contains(query) || code.contains(query);
  }).toList();

  list.sort((a, b) {
    switch (sort) {
      case ReportsStockSort.highestStock:
        return b.currentStock.compareTo(a.currentStock);
      case ReportsStockSort.lowestStock:
        return a.currentStock.compareTo(b.currentStock);
      case ReportsStockSort.mostUsed:
        return b.used7d.compareTo(a.used7d);
      case ReportsStockSort.leastUsed:
        return a.used7d.compareTo(b.used7d);
      case ReportsStockSort.recentlyMoved:
        return a.idleDays.compareTo(b.idleDays);
      case ReportsStockSort.oldestMovement:
        return b.idleDays.compareTo(a.idleDays);
      case ReportsStockSort.az:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
  });
  return list;
});
