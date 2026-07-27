import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../stock/reports_stock_providers.dart';
import '../stock/reports_stock_status.dart';

/// Clickable KPI chips — Active / Slow / Dead / Fast with counts.
class ReportsStockSummaryBar extends ConsumerWidget {
  const ReportsStockSummaryBar({super.key});

  static const _kpiFilters = [
    ReportsStockChipFilter.active,
    ReportsStockChipFilter.slow,
    ReportsStockChipFilter.dead,
    ReportsStockChipFilter.fast,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(reportsStockSummaryProvider);
    final selected = ref.watch(reportsStockChipFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final chip in _kpiFilters)
            _KpiChip(
              label: chip.label,
              count: summary.countFor(chip),
              accent: _accentFor(chip),
              selected: selected == chip,
              onTap: () {
                ref.read(reportsStockChipFilterProvider.notifier).state =
                    selected == chip ? ReportsStockChipFilter.all : chip;
              },
            ),
        ],
      ),
    );
  }

  Color _accentFor(ReportsStockChipFilter chip) => switch (chip) {
        ReportsStockChipFilter.active => const Color(0xFF4CAF50),
        ReportsStockChipFilter.slow => const Color(0xFFFBC02D),
        ReportsStockChipFilter.dead => const Color(0xFFE53935),
        ReportsStockChipFilter.fast => const Color(0xFF2196F3),
        ReportsStockChipFilter.all => HexaColors.brandPrimary,
      };
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.label,
    required this.count,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.14)
          : HexaColors.brandCard,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: HexaDsType.bodyPrimary(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: HexaDsType.h3(context).copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
