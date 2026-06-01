import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../stock/reports_stock_providers.dart';
import '../stock/reports_stock_status.dart';

/// Filter chips + compact sort — single strip (no duplicate KPI row above).
class ReportsStockFilterSortBar extends ConsumerWidget {
  const ReportsStockFilterSortBar({super.key});

  static const _filters = [
    ReportsStockChipFilter.all,
    ReportsStockChipFilter.active,
    ReportsStockChipFilter.slow,
    ReportsStockChipFilter.dead,
    ReportsStockChipFilter.fast,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(reportsStockSummaryProvider);
    final selected = ref.watch(reportsStockChipFilterProvider);
    final sort = ref.watch(reportsStockSortProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              'Movement class (rolling · not tied to period above)',
              style: HexaDsType.labelCaps(context).copyWith(fontSize: 10),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final chip in _filters) ...[
                  _FilterChip(
                    label: chip.label,
                    count: summary.countFor(chip),
                    selected: selected == chip,
                    onTap: () => ref
                        .read(reportsStockChipFilterProvider.notifier)
                        .state = chip,
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sort: ${sort.label}',
                    style: HexaDsType.bodySm(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Change sort',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openSortSheet(context, ref),
                  icon: const Icon(Icons.sort_rounded, size: 20),
                  color: HexaColors.brandPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSortSheet(BuildContext context, WidgetRef ref) async {
    final current = ref.read(reportsStockSortProvider);
    final picked = await showModalBottomSheet<ReportsStockSort>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Sort stock list', style: HexaDsType.h3(ctx)),
              ),
              for (final option in ReportsStockSort.values)
                ListTile(
                  dense: true,
                  title: Text(option.label),
                  trailing: current == option
                      ? Icon(Icons.check_rounded,
                          color: HexaColors.brandPrimary)
                      : null,
                  onTap: () => Navigator.pop(ctx, option),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      ref.read(reportsStockSortProvider.notifier).state = picked;
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        '$label ($count)',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? HexaColors.brandPrimary : HexaDsColors.textBody,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      showCheckmark: true,
    );
  }
}
