import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/low_stock_providers.dart';
import '../../../catalog/domain/item_stock_snapshot.dart';
import 'low_stock_lifecycle_strip.dart';

/// Desktop right-rail context for the selected low-stock item.
class LowStockContextPanel extends ConsumerWidget {
  const LowStockContextPanel({
    super.key,
    required this.item,
    required this.periodDays,
    required this.staffMode,
  });

  final Map<String, dynamic>? item;
  final int periodDays;
  final bool staffMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item == null) {
      return _emptyState(context);
    }

    final snap = ItemStockSnapshot.fromStockListRow(item!);
    final name = item!['name']?.toString() ?? 'Item';
    final supplier = item!['supplier_name']?.toString().trim();
    final usage = coerceToDouble(item!['period_usage_qty']);
    final usagePerDay = usage / (periodDays > 0 ? periodDays : 1);
    final stage = item!['lifecycle_stage']?.toString() ?? 'attention';
    final reorderStatus = item!['reorder_entry_status']?.toString();
    final pendingDays = item!['pending_order_days'] is num
        ? (item!['pending_order_days'] as num).toInt()
        : null;
    final itemId = item!['id']?.toString();

    final activityAsync = itemId == null
        ? null
        : ref.watch(lowStockItemTimelineProvider(itemId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
        LowStockLifecycleStrip(
          stage: stage,
          reorderStatus: reorderStatus,
          pendingDays: pendingDays,
        ),
        const SizedBox(height: 12),
        _metricRow('System', '${snap.systemQty} ${snap.unitLabel}'),
        _metricRow('Physical', '${snap.physicalQty} ${snap.unitLabel}'),
        _metricRow('Difference', snap.diffLabel()),
        _metricRow('Usage/day', usagePerDay.isFinite ? usagePerDay.toStringAsFixed(1) : '—'),
        _metricRow('Supplier', supplier != null && supplier.isNotEmpty ? supplier : '—'),
        const SizedBox(height: 12),
        if (itemId != null)
          FilledButton.tonal(
            onPressed: () => context.push('/catalog/item/$itemId'),
            child: const Text('Open item detail'),
          ),
        if (!staffMode && itemId != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/purchase/new?itemId=$itemId'),
            child: const Text('Order now'),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Recent activity',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: activityAsync == null
              ? const SizedBox.shrink()
              : activityAsync.when(
                  loading: () => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, __) => const Text(
                    'Could not load activity',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  data: (data) {
                    final events = data['activity'] as List? ?? const [];
                    if (events.isEmpty) {
                      return const Text(
                        'No recent movements',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      );
                    }
                    return ListView.separated(
                      itemCount: events.length.clamp(0, 8),
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (ctx, i) {
                        final e = events[i];
                        if (e is! Map) return const SizedBox.shrink();
                        final title = e['title']?.toString() ??
                            e['kind']?.toString() ??
                            'Event';
                        final when = e['occurred_at']?.toString() ?? '';
                        return Text(
                          '$title${when.isNotEmpty ? '\n$when' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ops command center',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Select an item to see supplier context, lifecycle stage, and recent stock activity.',
          style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
