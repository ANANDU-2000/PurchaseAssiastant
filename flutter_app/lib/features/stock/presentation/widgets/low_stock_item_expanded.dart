import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/low_stock_providers.dart';
import 'low_stock_item_row.dart';
import 'low_stock_lifecycle_strip.dart';

/// Compact row with optional expansion for lifecycle + activity preview.
class LowStockItemExpanded extends ConsumerStatefulWidget {
  const LowStockItemExpanded({
    super.key,
    required this.item,
    required this.staffMode,
    required this.periodDays,
    this.selected = false,
    this.bulkMode = false,
    this.onSelectionChanged,
    this.onTapSelect,
    this.highlighted = false,
    this.onDesktopSelect,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final int periodDays;
  final bool selected;
  final bool bulkMode;
  final bool highlighted;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onTapSelect;
  final VoidCallback? onDesktopSelect;

  @override
  ConsumerState<LowStockItemExpanded> createState() =>
      _LowStockItemExpandedState();
}

class _LowStockItemExpandedState extends ConsumerState<LowStockItemExpanded> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final stage = widget.item['lifecycle_stage']?.toString() ?? 'attention';
    final reorderStatus = widget.item['reorder_entry_status']?.toString();
    final pendingDays = widget.item['pending_order_days'] is num
        ? (widget.item['pending_order_days'] as num).toInt()
        : null;
    final itemId = widget.item['id']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.bulkMode)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 18),
                child: Checkbox(
                  value: widget.selected,
                  onChanged: (v) {
                    widget.onSelectionChanged?.call(v ?? false);
                  },
                ),
              ),
            Expanded(
              child: GestureDetector(
                onTap: widget.bulkMode
                    ? widget.onTapSelect
                    : () {
                        widget.onDesktopSelect?.call();
                        setState(() => _expanded = !_expanded);
                      },
                child: LowStockItemRow(
                  item: widget.item,
                  staffMode: widget.staffMode,
                  periodDays: widget.periodDays,
                  highlightSelected: widget.selected || widget.highlighted,
                ),
              ),
            ),
          ],
        ),
        if (_expanded && !widget.bulkMode) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: LowStockLifecycleStrip(
              stage: stage,
              reorderStatus: reorderStatus,
              pendingDays: pendingDays,
            ),
          ),
          if (itemId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _TimelinePreview(itemId: itemId),
            ),
        ],
      ],
    );
  }
}

class _TimelinePreview extends ConsumerWidget {
  const _TimelinePreview({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lowStockItemTimelineProvider(itemId));
    return async.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, __) => const Text(
        'Activity unavailable',
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      data: (data) {
        final events = data['activity'] as List? ?? const [];
        if (events.isEmpty) {
          return const Text(
            'No recent stock events',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Recent activity',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 4),
            for (final e in events.take(3))
              if (e is Map)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    e['title']?.toString() ?? e['kind']?.toString() ?? 'Event',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
          ],
        );
      },
    );
  }
}
