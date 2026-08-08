import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/stock_audit_rows.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../core/widgets/list_skeleton.dart';

import '../../../../core/theme/hexa_colors.dart';

enum StockItemHistoryFilter { all, today, week, month, physical }

/// Per-item stock audit + physical remaining timeline.
class StockItemHistoryPanel extends ConsumerStatefulWidget {
  const StockItemHistoryPanel({
    super.key,
    required this.itemId,
    this.compact = false,
  });

  final String itemId;
  final bool compact;

  @override
  ConsumerState<StockItemHistoryPanel> createState() =>
      _StockItemHistoryPanelState();
}

class _StockItemHistoryPanelState extends ConsumerState<StockItemHistoryPanel> {
  StockItemHistoryFilter _filter = StockItemHistoryFilter.all;

  bool _matchesFilter(DateTime? at) {
    if (_filter == StockItemHistoryFilter.all ||
        _filter == StockItemHistoryFilter.physical ||
        at == null) {
      return true;
    }
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final d = DateTime(at.year, at.month, at.day);
    switch (_filter) {
      case StockItemHistoryFilter.today:
        return d == day;
      case StockItemHistoryFilter.week:
        return !d.isBefore(day.subtract(const Duration(days: 7)));
      case StockItemHistoryFilter.month:
        return at.year == now.year && at.month == now.month;
      case StockItemHistoryFilter.all:
      case StockItemHistoryFilter.physical:
        return true;
    }
  }

  List<Map<String, dynamic>> _mergedRows(
    List<Map<String, dynamic>> audit,
    List<Map<String, dynamic>> physical,
  ) {
    return mergeStockActivityRows(audit: audit, physical: physical);
  }

  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(stockItemAuditProvider(widget.itemId));
    final physAsync = ref.watch(stockItemPhysicalCountsProvider(widget.itemId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 0 : 12,
            widget.compact ? 0 : 8,
            widget.compact ? 0 : 12,
            4,
          ),
          child: Row(
            children: [
              for (final f in StockItemHistoryFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(switch (f) {
                      StockItemHistoryFilter.all => 'All time',
                      StockItemHistoryFilter.today => 'Today',
                      StockItemHistoryFilter.week => 'This week',
                      StockItemHistoryFilter.month => 'This month',
                      StockItemHistoryFilter.physical => 'Physical',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _buildList(auditAsync, physAsync, context)),
      ],
    );
  }

  Widget _buildList(
    AsyncValue<List<Map<String, dynamic>>> auditAsync,
    AsyncValue<List<Map<String, dynamic>>> physAsync,
    BuildContext context,
  ) {
    if (auditAsync.isLoading && physAsync.isLoading) {
      return const ListSkeleton(rowCount: 8);
    }
    if (auditAsync.hasError && physAsync.hasError) {
      if (widget.compact) {
        return Center(
          child: TextButton(
            onPressed: () {
              ref.invalidate(stockItemAuditProvider(widget.itemId));
              ref.invalidate(stockItemPhysicalCountsProvider(widget.itemId));
            },
            child: const Text('Could not load history — tap to retry'),
          ),
        );
      }
      return FriendlyLoadError(
        message: 'Could not load stock history',
        subtitle: 'Please check your connection and try again.',
        onRetry: () {
          ref.invalidate(stockItemAuditProvider(widget.itemId));
          ref.invalidate(stockItemPhysicalCountsProvider(widget.itemId));
        },
      );
    }

    final audit = auditAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    final physical = physAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    var rows = _mergedRows(audit, physical);
    if (_filter == StockItemHistoryFilter.physical) {
      rows = rows.where(isPhysicalFloorFeedRow).toList();
    }
    final filtered = [
      for (final r in rows)
        if (_matchesFilter(parseStockAuditTimestamp(r))) r,
    ];

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                rows.isEmpty
                    ? 'No stock changes recorded'
                    : 'No changes in this date range',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                rows.isEmpty
                    ? 'Physical remaining and system updates will appear here'
                    : 'Try All time or Physical filter',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        96 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, i) {
        final r = filtered[i];
        final isPhysical = isPhysicalFloorFeedRow(r);
        final oldQ = coerceToDouble(r['old_qty'] ?? r['system_qty']);
        final newQ = coerceToDouble(r['new_qty'] ?? r['counted_qty']);
        final diff = isPhysical
            ? coerceToDouble(r['difference_qty'] ?? (newQ - oldQ))
            : newQ - oldQ;
        final barColor = isPhysical
            ? HexaColors.brandTealMid
            : diff > 0
                ? HexaColors.materialGreen
                : diff < 0
                    ? HexaColors.materialRed
                    : Colors.grey;
        final at = parseStockAuditTimestamp(r);
        final timeLabel = at != null
            ? DateFormat('d MMM · HH:mm').format(at)
            : '';
        final reason = (r['reason']?.toString().trim().isNotEmpty == true)
            ? r['reason'].toString().trim()
            : (isPhysical
                ? 'Physical remaining'
                : (r['adjustment_type']?.toString().trim().isNotEmpty == true
                    ? r['adjustment_type'].toString().trim()
                    : 'Stock update'));
        final whoRaw = r['updated_by_name']?.toString().trim() ??
            r['counted_by_name']?.toString().trim() ??
            '';
        final who = whoRaw.isNotEmpty ? whoRaw : '—';

        return SizedBox(
          height: 52,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: barColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isPhysical
                                  ? 'Floor ${newQ == newQ.roundToDouble() ? newQ.toInt() : newQ.toStringAsFixed(2)} '
                                      '(system ${oldQ.toStringAsFixed(0)}, diff ${diff > 0 ? '+' : ''}${diff == diff.roundToDouble() ? diff.toInt() : diff.toStringAsFixed(2)})'
                                  : '${diff > 0 ? '+' : ''}${diff == diff.roundToDouble() ? diff.toInt() : diff.toStringAsFixed(2)} '
                                      '(${oldQ.toStringAsFixed(0)} → ${newQ.toStringAsFixed(0)})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '$reason · by $who',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
