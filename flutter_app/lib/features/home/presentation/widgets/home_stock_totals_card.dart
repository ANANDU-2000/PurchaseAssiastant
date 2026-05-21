import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';

/// Owner home: on-hand totals + purchase vs stock variance for selected period.
class HomeStockTotalsCard extends ConsumerWidget {
  const HomeStockTotalsCard({super.key});

  static String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalsAsync = ref.watch(stockTotalsProvider);
    final dash = ref.watch(homeDashboardDataProvider);

    return totalsAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ),
      error: (_, __) => FriendlyLoadError(
        message: 'Could not load stock totals',
        onRetry: () => ref.invalidate(stockTotalsProvider),
      ),
      data: (totals) {
        final bags = (totals['total_bags'] as num?)?.toDouble() ?? 0;
        final kg = (totals['total_kg'] as num?)?.toDouble() ?? 0;
        final boxes = (totals['total_boxes'] as num?)?.toDouble() ?? 0;
        final tins = (totals['total_tins'] as num?)?.toDouble() ?? 0;
        final items = (totals['total_items'] as num?)?.toInt() ?? 0;

        final purchasedBags = dash.snapshot.data.totalBags;
        final variance = bags - purchasedBags;
        final pct = purchasedBags > 0
            ? (variance.abs() / purchasedBags * 100)
            : 0.0;
        final alert = purchasedBags <= 0
            ? 'No purchases in this period to compare'
            : pct > 25
                ? 'High variance — manual audit recommended'
                : pct > 10
                    ? 'Stock variance — check with staff'
                    : 'Stock levels look normal';
        final alertColor = purchasedBags <= 0
            ? HexaDsColors.textMuted
            : pct > 25
                ? HexaColors.loss
                : pct > 10
                    ? const Color(0xFFE65100)
                    : const Color(0xFF2E7D32);

        Widget tile(String label, String value) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: HexaColors.brandPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    label,
                    style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Total stock on hand',
                  style: HexaDsType.heading(15, color: HexaDsColors.textPrimary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    tile('BAGS', _fmtNum(bags)),
                    const SizedBox(width: 6),
                    tile('KG', _fmtNum(kg)),
                    const SizedBox(width: 6),
                    tile('BOXES', _fmtNum(boxes)),
                    const SizedBox(width: 6),
                    tile('TINS', _fmtNum(tins)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$items items tracked',
                  style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                ),
                const Divider(height: 20),
                Text(
                  'This period movement',
                  style: HexaDsType.heading(14, color: HexaDsColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Purchased: ${_fmtNum(purchasedBags)} BAGS · Current: ${_fmtNum(bags)} BAGS',
                  style: HexaDsType.body(13),
                ),
                Text(
                  'Variance: ${variance >= 0 ? '+' : ''}${_fmtNum(variance)} BAGS',
                  style: HexaDsType.body(13, color: HexaDsColors.textMuted),
                ),
                const SizedBox(height: 6),
                Text(
                  alert,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: alertColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
