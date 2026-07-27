import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../stock_period_utils.dart';

/// Compact period picker (overlay menu, not modal).
class StockPeriodDropdown extends ConsumerWidget {
  const StockPeriodDropdown({
    super.key,
    this.showYear = true,
    this.iconSize = 22,
  });

  final bool showYear;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPagePeriodProvider);
    final periods = showYear
        ? const [
            HomePeriod.allTime,
            HomePeriod.today,
            HomePeriod.week,
            HomePeriod.month,
            HomePeriod.year,
          ]
        : const [
            HomePeriod.allTime,
            HomePeriod.today,
            HomePeriod.week,
            HomePeriod.month,
          ];

    return PopupMenuButton<HomePeriod>(
      tooltip: 'Time: ${period.label}',
      icon: Icon(Icons.schedule_rounded, size: iconSize),
      initialValue: period,
      onSelected: (p) => applyStockPagePeriod(ref, p),
      itemBuilder: (ctx) => [
        for (final p in periods)
          CheckedPopupMenuItem<HomePeriod>(
            value: p,
            checked: period == p,
            child: Text(p.label),
          ),
      ],
    );
  }
}
