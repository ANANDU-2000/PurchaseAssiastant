import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/reports_bi_providers.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../widgets/bi/breakdown_legend_list.dart';
import '../widgets/bi/reports_bi_slice.dart';
import '../widgets/reports_item_row_card.dart';
import '../widgets/reports_purchase_row_card.dart';
import '../reporting/reports_item_metrics.dart';

/// Purchases tab: ranking, trends, recent bills, top items.
class ReportsPurchasesTab extends ConsumerWidget {
  const ReportsPurchasesTab({
    super.key,
    required this.agg,
    required this.purchases,
    required this.merged,
    required this.onLoadMore,
    required this.hasMore,
    this.isLoading = false,
  });

  final TradeReportAgg agg;
  final List<TradePurchase> purchases;
  final List<TradePurchase> merged;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isLoading && purchases.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (purchases.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No purchases in this period.')),
      );
    }

    final comparison = ref.watch(reportsPeriodComparisonProvider).valueOrNull;
    final pct = comparison?['purchase_change_pct'];
    final topSuppliers = agg.suppliers.take(8).toList();
    final topItems = agg.itemsAll.take(8).toList();
    final recent = [...purchases]
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    final recentCap = recent.take(hasMore ? 15 : recent.length).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ReportsSectionTitle('Supplier ranking'),
        if (topSuppliers.isEmpty)
          const _EmptyLine('No supplier data')
        else
          BreakdownLegendList(
            slices: [
              for (var i = 0; i < topSuppliers.length; i++)
                ReportsBiSlice(
                  title: topSuppliers[i].name,
                  subtitle: '${topSuppliers[i].dealIds.length} bills',
                  amount: topSuppliers[i].amountInr,
                  color: HexaColors.chartPalette[i % HexaColors.chartPalette.length],
                  pct: agg.totals.inr > 0
                      ? (topSuppliers[i].amountInr / agg.totals.inr) * 100
                      : 0,
                ),
            ],
          ),
        if (pct is num && pct.abs() >= 1) ...[
          ReportsSectionTitle('Purchase trends'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              pct > 0
                  ? 'Up ${pct.toStringAsFixed(0)}% vs prior period'
                  : 'Down ${pct.abs().toStringAsFixed(0)}% vs prior period',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
        ],
        ReportsSectionTitle('Recent bills'),
        for (final p in recentCap)
          ReportsPurchaseRowCard(
            purchase: p,
            onTap: () => context.push('/reports/purchase/${p.id}', extra: p),
          ),
        if (hasMore && onLoadMore != null)
          TextButton(onPressed: onLoadMore, child: const Text('Load more')),
        ReportsSectionTitle('Top purchased items'),
        for (final r in topItems)
          ReportsItemRowCard(
            row: r,
            rateLine: reportItemRateArrowLine(merged, r.key),
            purchaseCount: r.dealIds.length,
            onTap: () {},
          ),
      ],
    );
  }
}

class ReportsSectionTitle extends StatelessWidget {
  const ReportsSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: const TextStyle(color: Color(0xFF64748B))),
    );
  }
}
