import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/stock_audit_rows.dart';
import '../../../../core/widgets/hexa_error_card.dart';
import '../../../../shared/widgets/hexa_empty_state.dart';

/// **Movement** tab on [StockPage]: audit events for the stock period.
class StockMovementTab extends ConsumerWidget {
  const StockMovementTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPagePeriodProvider);
    final feed = ref.watch(stockChangesFeedProvider);
    final df = DateFormat('d MMM, HH:mm');

    return feed.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => HexaErrorCard.fromError(
        error: e,
        title: 'Could not load stock movement',
        onRetry: () => ref.invalidate(stockChangesFeedProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return HexaEmptyState(
            icon: Icons.swap_vert_rounded,
            title: 'No stock movement',
            subtitle:
                'No audit events for ${period.label.toLowerCase()}. Try a wider period.',
            primaryActionLabel: 'Refresh',
            onPrimaryAction: () => ref.invalidate(stockChangesFeedProvider),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(stockChangesFeedProvider);
            await ref.read(stockChangesFeedProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final d = stockAuditQtyDelta(r);
              final isBill = r['adjustment_type']?.toString() == 'purchase' &&
                  d.abs() < 0.001;
              final name = r['item_name']?.toString() ?? 'Item';
              final unit = r['unit']?.toString() ?? '';
              final at =
                  parseStockAuditTimestamp(r) ?? DateTime.now();
              return ListTile(
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  isBill
                      ? '${r['reason']?.toString() ?? 'Bill'} · ${df.format(at)}'
                      : df.format(at),
                ),
                trailing: Text(
                  isBill ? 'Bill' : '${d >= 0 ? '+' : ''}${d.round()} $unit'.trim(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isBill
                        ? const Color(0xFFE65100)
                        : d >= 0
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
