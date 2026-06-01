import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../stock/reports_stock_providers.dart';
import '../stock/reports_stock_status.dart';

/// Filter chips [All][Active][Slow][Dead][Fast] + sort control.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Sort: ${sort.label}',
                  style: HexaDsType.bodySm(context),
                  maxLines: 2,
                ),
              ),
              TextButton.icon(
                onPressed: () => _openSortSheet(context, ref),
                icon: const Icon(Icons.sort_rounded, size: 18),
                label: const Text('Change'),
                style: TextButton.styleFrom(
                  foregroundColor: HexaColors.brandPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),
        ),
      ],
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
    return Material(
      color: selected
          ? HexaColors.brandPrimary.withValues(alpha: 0.12)
          : HexaColors.brandCard,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? HexaColors.brandPrimary
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            '$label ($count)',
            style: HexaDsType.bodyPrimary(context).copyWith(
              fontWeight: FontWeight.w700,
              color: selected
                  ? HexaColors.brandPrimary
                  : HexaDsColors.textBody,
            ),
          ),
        ),
      ),
    );
  }
}
