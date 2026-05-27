import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import 'low_stock_item_expanded.dart';

class LowStockCategoryGroup extends StatefulWidget {
  const LowStockCategoryGroup({
    super.key,
    required this.grouped,
    required this.staffMode,
    required this.periodDays,
    this.bulkMode = false,
    this.selectedIds = const {},
    this.onToggleSelect,
  });

  final Map<String, Map<String, List<Map<String, dynamic>>>> grouped;
  final bool staffMode;
  final int periodDays;
  final bool bulkMode;
  final Set<String> selectedIds;
  final void Function(String itemId, bool selected)? onToggleSelect;

  @override
  State<LowStockCategoryGroup> createState() => _LowStockCategoryGroupState();
}

class _LowStockCategoryGroupState extends State<LowStockCategoryGroup> {
  final _expandedCats = <String>{};

  @override
  Widget build(BuildContext context) {
    if (widget.grouped.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No low-stock items match your filters',
            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final cats = widget.grouped.keys.toList()..sort((a, b) => a.compareTo(b));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      itemCount: cats.length,
      itemBuilder: (ctx, ci) {
        final cat = cats[ci];
        final subMap = widget.grouped[cat]!;

        final flatItems = <Map<String, dynamic>>[];
        for (final items in subMap.values) {
          flatItems.addAll(items);
        }

        int outCount = 0;
        int pendingCount = 0;
        int delayedCount = 0;
        int disputedCount = 0;
        int verificationCount = 0;

        double sumUsage = 0;
        for (final item in flatItems) {
          final status = (item['stock_status']?.toString() ?? '').toLowerCase();
          final cur = coerceToDouble(item['current_stock']);
          final isOut = status == 'out' || cur <= 0;
          if (isOut) outCount++;

          final hasPending = item['has_pending_order'] == true;
          if (hasPending) pendingCount++;
          final pendingDays = item['pending_order_days'] is num
              ? (item['pending_order_days'] as num).toInt()
              : null;
          if (hasPending && (pendingDays ?? 0) >= 7) delayedCount++;

          final physDiff = (item['physical_stock_difference_qty'] as num?)?.toDouble() ??
              (item['warehouse_diff_qty'] as num?)?.toDouble() ??
              0.0;
          if (physDiff.abs() > 0.001) disputedCount++;

          if (item['needs_verification'] == true) verificationCount++;

          sumUsage += coerceToDouble(item['period_usage_qty']);
        }

        final affectedCount = flatItems.length;
        final subCount = subMap.keys.length;
        final expanded = _expandedCats.contains(cat);

        final usagePerDay =
            sumUsage / (widget.periodDays > 0 ? widget.periodDays : 1);
        final impactLabel = 'Usage/day: ${usagePerDay.isFinite ? usagePerDay.toStringAsFixed(0) : '—'}';

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  cat,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                subtitle: Text(
                  '$affectedCount affected · $outCount out · $pendingCount pending · $delayedCount delayed · $disputedCount disputed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                ),
                trailing: SizedBox(
                  width: 110,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          '$subCount',
                          style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    ],
                  ),
                ),
                onTap: () {
                  setState(() {
                    if (expanded) {
                      _expandedCats.remove(cat);
                    } else {
                      _expandedCats.add(cat);
                    }
                  });
                },
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Category impact',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF475569)),
                          ),
                          const Spacer(),
                          Text(
                            impactLabel,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0F766E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final sub in subMap.keys.toList()..sort((a, b) => a.compareTo(b)))
                        _SubSection(
                          sub: sub,
                          items: subMap[sub]!,
                          staffMode: widget.staffMode,
                          periodDays: widget.periodDays,
                          bulkMode: widget.bulkMode,
                          selectedIds: widget.selectedIds,
                          onToggleSelect: widget.onToggleSelect,
                        ),
                      if (verificationCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Verification pending: $verificationCount',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF0EA5E9)),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SubSection extends StatelessWidget {
  const _SubSection({
    required this.sub,
    required this.items,
    required this.staffMode,
    required this.periodDays,
    this.bulkMode = false,
    this.selectedIds = const {},
    this.onToggleSelect,
  });

  final String sub;
  final List<Map<String, dynamic>> items;
  final bool staffMode;
  final int periodDays;
  final bool bulkMode;
  final Set<String> selectedIds;
  final void Function(String itemId, bool selected)? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sub,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                Text(
                  '${items.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
          for (final item in items)
            LowStockItemExpanded(
              item: item,
              staffMode: staffMode,
              periodDays: periodDays,
              bulkMode: bulkMode,
              selected: selectedIds.contains(item['id']?.toString()),
              onSelectionChanged: (v) {
                final id = item['id']?.toString();
                if (id == null) return;
                onToggleSelect?.call(id, v);
              },
              onTapSelect: () {
                final id = item['id']?.toString();
                if (id == null) return;
                onToggleSelect?.call(id, !selectedIds.contains(id));
              },
            ),
        ],
      ),
    );
  }
}

