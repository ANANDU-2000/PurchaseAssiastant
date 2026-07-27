import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/stock_providers.dart';
import 'opening_stock_summary_bar.dart';

class OpeningStockProgressSheet extends ConsumerWidget {
  const OpeningStockProgressSheet({
    super.key,
    required this.pendingCount,
    required this.completedCount,
    required this.totalCount,
    this.lastUpdatedAtIso,
    this.lastUpdatedBy,
  });

  final int pendingCount;
  final int completedCount;
  final int totalCount;
  final String? lastUpdatedAtIso;
  final String? lastUpdatedBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = totalCount - completedCount;
    final pct = totalCount <= 0 ? 0.0 : (completedCount / totalCount) * 100.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        OpeningStockSummaryBar(
            pendingCount: pendingCount,
            completedCount: completedCount,
            totalCount: totalCount,
            lastUpdatedAtIso: lastUpdatedAtIso,
            lastUpdatedBy: lastUpdatedBy,
          ),
          const SizedBox(height: 14),
          Text(
            'Progress: ${pct.toStringAsFixed(0)}% complete',
            style: HexaDsType.label(12).copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: totalCount <= 0 ? 0 : completedCount / totalCount,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              ref.read(openingStockSetupQueryProvider.notifier).state =
                  ref
                      .read(openingStockSetupQueryProvider)
                      .copyWith(status: 'pending', page: 1);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.pending_actions_rounded, size: 18),
            label: Text('View pending items ($remaining)'),
          ),
        ],
    );
  }
}

Future<void> showOpeningStockProgressSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> summary,
}) async {
  await showHexaBottomSheet<void>(
    context: context,
    compact: true,
    child: OpeningStockProgressSheet(
      pendingCount: (summary['pending_count'] as num?)?.toInt() ?? 0,
      completedCount: (summary['completed_count'] as num?)?.toInt() ?? 0,
      totalCount: (summary['total_count'] as num?)?.toInt() ?? 0,
      lastUpdatedAtIso: summary['last_updated_at']?.toString(),
      lastUpdatedBy: summary['last_updated_by']?.toString(),
    ),
  );
}

