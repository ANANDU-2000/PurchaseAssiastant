import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';

String _inr(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

/// KPI grid for Reports Overview — cards first, charts below.
class ReportsOverviewKpiGrid extends ConsumerWidget {
  const ReportsOverviewKpiGrid({
    super.key,
    required this.agg,
    this.onTapStock,
    this.onTapPurchases,
    this.onTapItems,
  });

  final TradeReportAgg agg;
  final VoidCallback? onTapStock;
  final VoidCallback? onTapPurchases;
  final VoidCallback? onTapItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationalReportsProvider).valueOrNull;
    final dead = (ops?['dead_stock'] as List?)?.length ?? 0;
    final fast = (ops?['fast_moving'] as List?)?.length ?? 0;
    final lowCount = ref.watch(lowStockByCategoryProvider).maybeWhen(
          data: (m) => m.values.fold<int>(
            0,
            (s, cat) =>
                s +
                cat.values.fold<int>(0, (a, items) => a + items.length),
          ),
          orElse: () => 0,
        );
    final cats = ref.watch(analyticsCategoriesTableProvider).valueOrNull ?? [];
    String topCat = '—';
    if (cats.isNotEmpty) {
      topCat = (cats.first['category_name'] ?? cats.first['category'] ?? '—')
          .toString();
    }
    String topSup = '—';
    if (agg.suppliers.isNotEmpty) {
      topSup = agg.suppliers.first.name;
    }

    final qtyParts = <String>[];
    final t = agg.totals;
    if (t.bags > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('bag', t.bags)} bag');
    }
    if (t.boxes > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('box', t.boxes)} box');
    }
    if (t.tins > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('tin', t.tins)} tin');
    }
    if (t.kg > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('kg', t.kg)} kg');
    }
    final qtyLine = qtyParts.isEmpty ? '—' : qtyParts.join(' · ');

    final cards = <_KpiCardData>[
      _KpiCardData('Purchase value', _inr(t.inr), onTap: onTapPurchases),
      _KpiCardData('Purchase qty', qtyLine, onTap: onTapPurchases),
      _KpiCardData('Items', '${agg.itemsAll.length}', onTap: onTapItems),
      _KpiCardData('Suppliers', '${agg.suppliers.length}', onTap: onTapPurchases),
      _KpiCardData('Low stock', '$lowCount', onTap: onTapStock),
      _KpiCardData('Dead stock', '$dead', onTap: onTapStock),
      _KpiCardData('Fast moving', '$fast', onTap: onTapStock),
      _KpiCardData('Top supplier', topSup, onTap: onTapPurchases),
      _KpiCardData('Top category', topCat, onTap: onTapItems),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: 72,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) => _KpiTile(data: cards[i]),
        );
      },
    );
  }
}

class _KpiCardData {
  const _KpiCardData(this.label, this.value, {this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.data});
  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HexaColors.brandCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
