import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import 'low_stock_item_detail_tile.dart';
import 'low_stock_tree_counts.dart';

enum LowStockTreeTab {
  allLow,
  pendingOrder,
  outOfStock,
  purchasedInPeriod,
  pendingDelivery,
}

enum LowStockSearchScope { all, category, subcategory, item }

bool lowStockItemNeedsAttention(Map<String, dynamic> item) {
  final status = (item['stock_status']?.toString() ?? '').toLowerCase();
  final stock = coerceToDouble(item['current_stock']);
  final reorder = coerceToDouble(item['reorder_level']);
  final pendingDel = coerceToDoubleNullable(item['pending_delivery_qty']) ?? 0;
  if (pendingDel > 0.001) return true;
  if (item['has_pending_order'] == true &&
      item['last_purchase_delivered'] == false) {
    return true;
  }
  return status == 'low' ||
      status == 'critical' ||
      status == 'out' ||
      stock <= 0 ||
      (reorder > 0 && stock <= reorder);
}

bool lowStockItemPendingDelivery(Map<String, dynamic> item) {
  final pendingDel = coerceToDoubleNullable(item['pending_delivery_qty']) ?? 0;
  if (pendingDel > 0.001) return true;
  return item['has_pending_order'] == true &&
      item['last_purchase_delivered'] == false;
}

bool lowStockMatchesTab(Map<String, dynamic> item, LowStockTreeTab tab) {
  final status = (item['stock_status']?.toString() ?? '').toLowerCase();
  final stock = coerceToDouble(item['current_stock']);
  final pending = item['has_pending_order'] == true;
  final purchasedQty = coerceToDouble(item['period_purchased_qty']);
  return switch (tab) {
    LowStockTreeTab.pendingOrder => pending,
    LowStockTreeTab.outOfStock => stock <= 0 || status == 'out',
    LowStockTreeTab.purchasedInPeriod =>
      lowStockItemNeedsAttention(item) && (purchasedQty > 0 || pending),
    LowStockTreeTab.pendingDelivery => lowStockItemPendingDelivery(item),
    LowStockTreeTab.allLow => lowStockItemNeedsAttention(item),
  };
}

int countLowStockForTab(
  Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
  LowStockTreeTab tab,
) {
  var n = 0;
  for (final subMap in grouped.values) {
    for (final items in subMap.values) {
      for (final item in items) {
        if (lowStockMatchesTab(item, tab)) n++;
      }
    }
  }
  return n;
}

/// Filter grouped map by tab + search scope (client-side).
Map<String, Map<String, List<Map<String, dynamic>>>> filterLowStockGrouped({
  required Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
  required LowStockTreeTab tab,
  required String searchQuery,
  required LowStockSearchScope searchScope,
}) {
  final q = searchQuery.trim().toLowerCase();
  final filtered = <String, Map<String, List<Map<String, dynamic>>>>{};

  for (final catEntry in grouped.entries) {
    if (q.isNotEmpty &&
        searchScope == LowStockSearchScope.category &&
        !catEntry.key.toLowerCase().contains(q)) {
      continue;
    }

    final subMap = <String, List<Map<String, dynamic>>>{};
    for (final subEntry in catEntry.value.entries) {
      if (q.isNotEmpty &&
          searchScope == LowStockSearchScope.subcategory &&
          !subEntry.key.toLowerCase().contains(q)) {
        continue;
      }

      final items = subEntry.value.where((it) {
        if (!lowStockMatchesTab(it, tab)) return false;
        if (q.isEmpty) return true;
        if (searchScope == LowStockSearchScope.category ||
            searchScope == LowStockSearchScope.subcategory) {
          return true;
        }
        final hay = [
          it['name'],
          it['category_name'],
          it['subcategory_name'],
          it['item_code'],
          it['supplier_name'],
        ].whereType<String>().join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();

      if (items.isNotEmpty) subMap[subEntry.key] = items;
    }
    if (subMap.isNotEmpty) filtered[catEntry.key] = subMap;
  }
  return filtered;
}

/// Expandable category → subcategory → item list for low-stock dashboards.
class LowStockCategoryTree extends StatefulWidget {
  const LowStockCategoryTree({
    super.key,
    required this.grouped,
    required this.tab,
    this.searchQuery = '',
    this.searchScope = LowStockSearchScope.all,
    this.staffMode = false,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onReceive,
  });

  final Map<String, Map<String, List<Map<String, dynamic>>>> grouped;
  final LowStockTreeTab tab;
  final String searchQuery;
  final LowStockSearchScope searchScope;
  final bool staffMode;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  @override
  State<LowStockCategoryTree> createState() => _LowStockCategoryTreeState();
}

class _LowStockCategoryTreeState extends State<LowStockCategoryTree> {
  final _expandedCats = <String>{};
  String? _lastFilterKey;

  @override
  void initState() {
    super.initState();
    _resetExpandedForFilter();
  }

  void _resetExpandedForFilter() {
    _expandedCats.clear();
    final filtered = filterLowStockGrouped(
      grouped: widget.grouped,
      tab: widget.tab,
      searchQuery: widget.searchQuery,
      searchScope: widget.searchScope,
    );
    final first = categoryWithHighestOut(filtered, widget.tab);
    if (first != null) _expandedCats.add(first);
    _lastFilterKey =
        '${widget.tab}|${widget.searchQuery}|${widget.searchScope}|${widget.grouped.length}';
  }

  @override
  void didUpdateWidget(covariant LowStockCategoryTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key =
        '${widget.tab}|${widget.searchQuery}|${widget.searchScope}|${widget.grouped.length}';
    if (key != _lastFilterKey) {
      _resetExpandedForFilter();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filterLowStockGrouped(
      grouped: widget.grouped,
      tab: widget.tab,
      searchQuery: widget.searchQuery,
      searchScope: widget.searchScope,
    );

    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No items in this view',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final cats = sortedLowStockCategories(filtered, widget.tab);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: cats.length,
      itemBuilder: (ctx, ci) {
        final cat = cats[ci];
        final subMap = filtered[cat]!;
        final counts = countLowOutForGrouped(filtered, cat, widget.tab);
        final expanded = _expandedCats.contains(cat);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  cat,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DualBadge(label: 'LOW', count: counts.low),
                    const SizedBox(width: 6),
                    _DualBadge(label: 'OUT', count: counts.out),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedCats.remove(cat);
                  } else {
                    _expandedCats.add(cat);
                  }
                }),
              ),
              if (expanded)
                for (final subEntry in subMap.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key))) ...[
                  Builder(
                    builder: (context) {
                      final subCounts = countLowOutForItems(
                        subEntry.value,
                        widget.tab,
                      );
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                subEntry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            _DualBadge(
                              label: 'LOW',
                              count: subCounts.low,
                              compact: true,
                            ),
                            const SizedBox(width: 4),
                            _DualBadge(
                              label: 'OUT',
                              count: subCounts.out,
                              compact: true,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  for (final item in subEntry.value)
                    LowStockItemDetailTile(
                      item: item,
                      staffMode: widget.staffMode,
                      onOrderNow: widget.onOrderNow,
                      onNotifyOwner: widget.onNotifyOwner,
                      onEditReorder: widget.onEditReorder,
                      onStockUpdate: widget.onStockUpdate,
                      onReceive: widget.onReceive,
                    ),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _DualBadge extends StatelessWidget {
  const _DualBadge({
    required this.label,
    required this.count,
    this.compact = false,
  });

  final String label;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        compact ? '$count' : '$label $count',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}
