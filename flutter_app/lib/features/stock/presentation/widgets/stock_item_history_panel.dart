import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../core/widgets/list_skeleton.dart';

enum StockItemHistoryFilter { all, today, week, month }

/// Per-item stock audit timeline (embedded in catalog detail or standalone route).
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
    if (_filter == StockItemHistoryFilter.all || at == null) return true;
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
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(stockItemAuditProvider(widget.itemId));

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
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _buildList(auditAsync, context)),
      ],
    );
  }

  Widget _buildList(
    AsyncValue<List<Map<String, dynamic>>> auditAsync,
    BuildContext context,
  ) {
    return auditAsync.when(
      loading: () => const ListSkeleton(rowCount: 8),
      error: (e, _) {
        if (widget.compact) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  ref.invalidate(stockItemAuditProvider(widget.itemId)),
              child: const Text('Could not load history — tap to retry'),
            ),
          );
        }
        return FriendlyLoadError(
          message: 'Could not load stock history',
          subtitle: 'Please check your connection and try again.',
          onRetry: () => ref.invalidate(stockItemAuditProvider(widget.itemId)),
        );
      },
      data: (rows) {
        final filtered = [
          for (final r in rows)
            if (_matchesFilter(
              DateTime.tryParse(r['updated_at']?.toString() ?? ''),
            ))
              r,
        ];
        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_rounded,
                    size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'No stock changes recorded',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  'Stock updates will appear here',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
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
            final oldQ = coerceToDouble(r['old_qty']);
            final newQ = coerceToDouble(r['new_qty']);
            final diff = newQ - oldQ;
            final barColor = diff > 0
                ? const Color(0xFF2E7D32)
                : diff < 0
                    ? const Color(0xFFC62828)
                    : Colors.grey;
            final at =
                DateTime.tryParse(r['updated_at']?.toString() ?? '');
            final timeLabel = at != null
                ? DateFormat('d MMM · HH:mm').format(at.toLocal())
                : '';
            final reason = r['reason']?.toString() ??
                r['adjustment_type']?.toString() ??
                '';
            final who = r['updated_by_name']?.toString() ?? '—';

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
                                  '${diff > 0 ? '+' : ''}${diff == diff.roundToDouble() ? diff.toInt() : diff.toStringAsFixed(2)} '
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
      },
    );
  }
}
