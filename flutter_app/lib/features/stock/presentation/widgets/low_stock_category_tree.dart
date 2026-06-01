import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../shared/widgets/hexa_empty_state.dart';
import 'low_stock_compact_item_row.dart';
import 'low_stock_tree_counts.dart';

enum LowStockTreeTab {
  allLow,
  pendingOrder,
  outOfStock,
  purchasedInPeriod,
  pendingDelivery,
}

enum LowStockSearchScope { all, category, subcategory, item, supplier }

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
  String? subcategoryFilter,
}) {
  final q = searchQuery.trim().toLowerCase();
  final subFilter = subcategoryFilter?.trim().toLowerCase() ?? '';
  final filtered = <String, Map<String, List<Map<String, dynamic>>>>{};

  bool itemMatchesSearch(
    Map<String, dynamic> it,
    String cat,
    String sub,
  ) {
    if (q.isEmpty) return true;
    final itemHay = _itemSearchHay(it);
    switch (searchScope) {
      case LowStockSearchScope.category:
        return cat.toLowerCase().contains(q) || itemHay.contains(q);
      case LowStockSearchScope.subcategory:
        return sub.toLowerCase().contains(q) || itemHay.contains(q);
      case LowStockSearchScope.item:
        return itemHay.contains(q);
      case LowStockSearchScope.supplier:
        return (it['supplier_name']?.toString().toLowerCase() ?? '')
                .contains(q) ||
            itemHay.contains(q);
      case LowStockSearchScope.all:
        return cat.toLowerCase().contains(q) ||
            sub.toLowerCase().contains(q) ||
            itemHay.contains(q);
    }
  }

  for (final catEntry in grouped.entries) {
    if (q.isNotEmpty &&
        searchScope == LowStockSearchScope.category &&
        !catEntry.key.toLowerCase().contains(q) &&
        !catEntry.value.values.any(
          (items) => items.any((it) => _itemSearchHay(it).contains(q)),
        )) {
      continue;
    }

    final subMap = <String, List<Map<String, dynamic>>>{};
    for (final subEntry in catEntry.value.entries) {
      if (subFilter.isNotEmpty &&
          subEntry.key.toLowerCase() != subFilter &&
          !subEntry.key.toLowerCase().contains(subFilter)) {
        continue;
      }
      if (q.isNotEmpty &&
          searchScope == LowStockSearchScope.subcategory &&
          !subEntry.key.toLowerCase().contains(q) &&
          !subEntry.value.any((it) => _itemSearchHay(it).contains(q))) {
        continue;
      }

      final items = subEntry.value.where((it) {
        if (!lowStockMatchesTab(it, tab)) return false;
        return itemMatchesSearch(it, catEntry.key, subEntry.key);
      }).toList();

      if (items.isNotEmpty) subMap[subEntry.key] = items;
    }
    if (subMap.isNotEmpty) filtered[catEntry.key] = subMap;
  }
  return filtered;
}

String _itemSearchHay(Map<String, dynamic> it) {
  return [
    it['name'],
    it['category_name'],
    it['subcategory_name'],
    it['item_code'],
    it['supplier_name'],
    it['last_purchase_human_id'],
  ].whereType<String>().join(' ').toLowerCase();
}

/// All subcategory names in grouped data (for filter chips).
List<String> lowStockSubcategoryOptions(
  Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
) {
  final subs = <String>{};
  for (final subMap in grouped.values) {
    subs.addAll(subMap.keys);
  }
  final list = subs.toList()..sort();
  return list;
}

/// Search suggestions: item names, categories, subcategories, suppliers, codes.
List<String> lowStockSearchSuggestions(
  Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
) {
  final out = <String>{};
  for (final catEntry in grouped.entries) {
    if (catEntry.key.trim().isNotEmpty) out.add(catEntry.key.trim());
    for (final subEntry in catEntry.value.entries) {
      if (subEntry.key.trim().isNotEmpty &&
          subEntry.key != '—' &&
          subEntry.key != 'Uncategorized') {
        out.add(subEntry.key.trim());
      }
      for (final it in subEntry.value) {
        final name = it['name']?.toString().trim();
        if (name != null && name.isNotEmpty) out.add(name);
        final code = it['item_code']?.toString().trim();
        if (code != null && code.isNotEmpty) out.add(code);
        final sup = it['supplier_name']?.toString().trim();
        if (sup != null && sup.isNotEmpty) out.add(sup);
      }
    }
  }
  final list = out.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

/// Stable A→Z order for rows inside a category / sub-tab.
List<Map<String, dynamic>> sortedLowStockItemsByName(
  Iterable<Map<String, dynamic>> items,
) {
  final list = items.toList()
    ..sort((a, b) {
      final an = (a['name']?.toString() ?? '').toLowerCase();
      final bn = (b['name']?.toString() ?? '').toLowerCase();
      final byName = an.compareTo(bn);
      if (byName != 0) return byName;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });
  return list;
}

/// Flatten filtered grouped map to item rows (PDF / export).
List<Map<String, dynamic>> flattenLowStockGrouped(
  Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
) {
  final out = <Map<String, dynamic>>[];
  for (final subMap in grouped.values) {
    for (final items in subMap.values) {
      out.addAll(items);
    }
  }
  return out;
}

/// Expandable category → subcategory → item list for low-stock dashboards.
class LowStockCategoryTree extends StatefulWidget {
  const LowStockCategoryTree({
    super.key,
    required this.grouped,
    required this.tab,
    this.searchQuery = '',
    this.searchScope = LowStockSearchScope.all,
    this.subcategoryFilter,
    this.staffMode = false,
    this.informedOwnerIds = const {},
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onSystemStockUpdate,
    this.onReceive,
  });

  final Map<String, Map<String, List<Map<String, dynamic>>>> grouped;
  final LowStockTreeTab tab;
  final String searchQuery;
  final LowStockSearchScope searchScope;
  final String? subcategoryFilter;
  final bool staffMode;
  final Set<String> informedOwnerIds;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onSystemStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  @override
  State<LowStockCategoryTree> createState() => _LowStockCategoryTreeState();
}

class _LowStockCategoryTreeState extends State<LowStockCategoryTree> {
  final _expandedCats = <String>{};
  /// Per-category subcategory tab (`null` = all subs in category).
  final _subTabByCat = <String, String?>{};
  String? _lastFilterKey;

  @override
  void initState() {
    super.initState();
    _resetExpandedForFilter();
  }

  void _resetExpandedForFilter() {
    _expandedCats.clear();
    _subTabByCat.clear();
    _lastFilterKey =
        '${widget.tab}|${widget.searchQuery}|${widget.searchScope}|${widget.subcategoryFilter}|${widget.grouped.length}';
  }

  @override
  void didUpdateWidget(covariant LowStockCategoryTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key =
        '${widget.tab}|${widget.searchQuery}|${widget.searchScope}|${widget.subcategoryFilter}|${widget.grouped.length}';
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
      subcategoryFilter: widget.subcategoryFilter,
    );

    if (filtered.isEmpty) {
      return const HexaEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No low-stock items here',
        subtitle: 'Try another tab or clear filters.',
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
          margin: const EdgeInsets.only(bottom: 6),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE2E8E6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  cat,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (counts.out > 0)
                      _OutCountBadge(count: counts.out)
                    else if (counts.low > 0)
                      _OutCountBadge(count: counts.low, label: 'LOW'),
                    const SizedBox(width: 4),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
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
              if (expanded) ...[
                Builder(
                  builder: (context) {
                    final namedSubs = subMap.keys
                        .where(
                          (k) =>
                              k.trim().isNotEmpty &&
                              k != '—' &&
                              k != 'Uncategorized',
                        )
                        .toList()
                      ..sort();
                    final countsBySub = {
                      for (final k in namedSubs) k: subMap[k]!.length,
                    };
                    return _SubcategoryTabBar(
                      subs: namedSubs,
                      countsBySub: countsBySub,
                      selected: _subTabByCat[cat],
                      onSelected: (sub) => setState(() {
                        if (sub == null) {
                          _subTabByCat.remove(cat);
                        } else {
                          _subTabByCat[cat] = sub;
                        }
                      }),
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    var serial = 0;
                    final subEntries = subMap.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key));
                    final selectedSub = _subTabByCat[cat];
                    final showAllSubs = selectedSub == null;
                    final rows = <Widget>[];

                    for (final subEntry in subEntries) {
                      if (!showAllSubs && selectedSub != subEntry.key) {
                        continue;
                      }
                      final items =
                          sortedLowStockItemsByName(subEntry.value);
                      if (items.isEmpty) continue;

                      final subLabel = subEntry.key.trim();
                      final hasNamedSub = subLabel.isNotEmpty &&
                          subLabel != '—' &&
                          subLabel != 'Uncategorized';

                      if (showAllSubs && hasNamedSub) {
                        rows.add(
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                            child: Text(
                              '$subLabel · ${items.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        );
                      }

                      for (final item in items) {
                        serial++;
                        rows.add(
                          LowStockCompactItemRow(
                            serialNumber: serial,
                            item: item,
                            staffMode: widget.staffMode,
                            hideSubcategory: hasNamedSub,
                            ownerInformed: widget.informedOwnerIds
                                .contains(item['id']?.toString()),
                            onOrderNow: widget.onOrderNow,
                            onNotifyOwner: widget.onNotifyOwner,
                            onEditReorder: widget.onEditReorder,
                            onStockUpdate: widget.onStockUpdate,
                            onSystemStockUpdate: widget.onSystemStockUpdate,
                            onReceive: widget.onReceive,
                          ),
                        );
                      }
                    }

                    if (rows.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Text(
                          'No items in this subcategory.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      );
                    }

                    if (serial > 0) {
                      rows.insert(
                        0,
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                          child: Text(
                            showAllSubs
                                ? '$serial items · numbered in order'
                                : '$serial in $selectedSub · #1–$serial',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SubcategoryTabBar extends StatelessWidget {
  const _SubcategoryTabBar({
    required this.subs,
    required this.countsBySub,
    required this.selected,
    required this.onSelected,
  });

  final List<String> subs;
  final Map<String, int> countsBySub;
  final String? selected;
  final void Function(String? sub) onSelected;

  @override
  Widget build(BuildContext context) {
    if (subs.isEmpty) return const SizedBox.shrink();
    final total = countsBySub.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  'All ($total)',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                showCheckmark: true,
              ),
            ),
            for (final sub in subs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(
                    '${sub.length > 14 ? '${sub.substring(0, 14)}…' : sub} (${countsBySub[sub] ?? 0})',
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: selected == sub,
                  onSelected: (_) => onSelected(sub),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  showCheckmark: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OutCountBadge extends StatelessWidget {
  const _OutCountBadge({required this.count, this.label = 'OUT'});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label $count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
