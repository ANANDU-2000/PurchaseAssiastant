import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import 'reports_qty_unit_strip.dart';

String _inr(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

/// KPI grid for Reports Overview — hero amount, unit strip, compact secondary cards.
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

  static const _amountColor = Color(0xFF3B6D11);
  static const _countColor = Color(0xFF2563EB);
  static const _warnColor = Color(0xFFDC2626);
  static const _mutedColor = Color(0xFF64748B);
  static const _accentColor = Color(0xFF0D9488);

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

    final t = agg.totals;
    final secondary = <_KpiCardData>[
      _KpiCardData('Items', '${agg.itemsAll.length}', _countColor, onTap: onTapItems),
      _KpiCardData(
        'Suppliers',
        '${agg.suppliers.length}',
        _accentColor,
        onTap: onTapPurchases,
      ),
      _KpiCardData('Low stock', '$lowCount', _warnColor, onTap: onTapStock),
      _KpiCardData('Dead stock', '$dead', _warnColor, onTap: onTapStock),
      _KpiCardData('Fast moving', '$fast', _mutedColor, onTap: onTapStock),
      _KpiCardData('Top supplier', topSup, _accentColor, onTap: onTapPurchases),
      _KpiCardData('Top category', topCat, _mutedColor, onTap: onTapItems),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _HeroKpiTile(
                    label: 'Total amount',
                    value: _inr(t.inr),
                    color: _amountColor,
                    onTap: onTapPurchases,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KpiTile(
                    data: _KpiCardData(
                      'Bills',
                      '${t.deals}',
                      _countColor,
                      onTap: onTapPurchases,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ReportsQtyUnitStrip(
              bags: t.bags,
              boxes: t.boxes,
              tins: t.tins,
              kg: t.kg,
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: 64,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: secondary.length,
              itemBuilder: (_, i) => _KpiTile(data: secondary[i]),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCardData {
  const _KpiCardData(this.label, this.value, this.valueColor, {this.onTap});
  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback? onTap;
}

class _HeroKpiTile extends StatelessWidget {
  const _HeroKpiTile({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HexaColors.brandCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: data.valueColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
