import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/analytics_kpi_provider.dart' show analyticsDateRangeProvider, analyticsKpiProvider;
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/app_settings_action.dart';

int _trendSortKey(Map<String, dynamic> r) {
  switch (r['trend']?.toString()) {
    case 'up':
      return 2;
    case 'flat':
      return 1;
    case 'down':
      return 0;
    default:
      return -1;
  }
}

Widget _trendCell(String? t) {
  switch (t) {
    case 'up':
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_up_rounded, size: 18, color: HexaColors.profit),
          const SizedBox(width: 4),
          Text('Up', style: TextStyle(fontWeight: FontWeight.w800, color: HexaColors.profit, fontSize: 12)),
        ],
      );
    case 'down':
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_down_rounded, size: 18, color: HexaColors.loss),
          const SizedBox(width: 4),
          Text('Down', style: TextStyle(fontWeight: FontWeight.w800, color: HexaColors.loss, fontSize: 12)),
        ],
      );
    case 'flat':
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_flat_rounded, size: 18, color: HexaColors.textSecondary),
          const SizedBox(width: 4),
          Text('Flat', style: TextStyle(color: HexaColors.textSecondary, fontSize: 12)),
        ],
      );
    default:
      return Text(
        '—',
        style: TextStyle(color: HexaColors.textSecondary.withValues(alpha: 0.85), fontSize: 12),
      );
  }
}

Widget _categoryBestChip(String? name, TextTheme tt) {
  if (name == null || name.isEmpty) {
    return Text('—', style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary));
  }
  return Chip(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    label: Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    visualDensity: VisualDensity.compact,
    backgroundColor: HexaColors.primaryLight.withValues(alpha: 0.85),
    side: BorderSide(color: HexaColors.primaryMid.withValues(alpha: 0.35)),
  );
}

List<Map<String, dynamic>> _sortedRows(
  List<Map<String, dynamic>> rows,
  String mode,
  bool asc,
  num Function(Map<String, dynamic> r) profitKey,
) {
  final o = List<Map<String, dynamic>>.from(rows);
  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (mode) {
      case 'best':
        return (a['best_item_name'] ?? '').toString().compareTo((b['best_item_name'] ?? '').toString());
      case 'name':
        return (a['item_name'] ?? a['category'] ?? a['supplier_name'] ?? a['broker_name'] ?? '')
            .toString()
            .compareTo((b['item_name'] ?? b['category'] ?? b['supplier_name'] ?? b['broker_name'] ?? '').toString());
      case 'qty':
        return ((a['total_qty'] as num?) ?? 0).compareTo((b['total_qty'] as num?) ?? 0);
      case 'lines':
        return ((a['line_count'] as num?) ?? 0).compareTo((b['line_count'] as num?) ?? 0);
      case 'deals':
        return ((a['deals'] as num?) ?? 0).compareTo((b['deals'] as num?) ?? 0);
      case 'avg':
        return ((a['avg_landing'] as num?) ?? 0).compareTo((b['avg_landing'] as num?) ?? 0);
      case 'commission':
        return ((a['total_commission'] as num?) ?? 0).compareTo((b['total_commission'] as num?) ?? 0);
      case 'margin':
        return ((a['margin_pct'] as num?) ?? 0).compareTo((b['margin_pct'] as num?) ?? 0);
      case 'trend':
        return _trendSortKey(a).compareTo(_trendSortKey(b));
      case 'commission_pct':
        return ((a['commission_pct_of_profit'] as num?) ?? 0).compareTo((b['commission_pct_of_profit'] as num?) ?? 0);
      case 'profit':
      default:
        return profitKey(a).compareTo(profitKey(b));
    }
  }

  o.sort((a, b) {
    final c = cmp(a, b);
    return asc ? c : -c;
  });
  return o;
}

String _csvCell(String value) {
  final s = value.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
  if (s.contains(',') || s.contains('"')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

Future<void> _shareCsv({
  required String title,
  required List<String> headers,
  required List<Map<String, dynamic>> rows,
  required List<String Function(Map<String, dynamic> r)> columns,
}) async {
  final buf = StringBuffer();
  buf.writeln(headers.map(_csvCell).join(','));
  for (final r in rows) {
    buf.writeln(columns.map((c) => _csvCell(c(r))).join(','));
  }
  await Share.share(buf.toString(), subject: title);
}

Color _analyticsDataRowColor(BuildContext context, int index, double profit) {
  final surface = Theme.of(context).colorScheme.surface;
  final stripe = HexaColors.surfaceMuted.withValues(alpha: 0.4);
  var row = index.isEven ? surface : Color.alphaBlend(stripe, surface);
  if (profit < 0) {
    row = Color.alphaBlend(HexaColors.loss.withValues(alpha: 0.11), row);
  } else if (profit > 0) {
    row = Color.alphaBlend(HexaColors.profit.withValues(alpha: 0.06), row);
  }
  return row;
}

Color _marginStripeColor(double? m) {
  if (m == null) return Colors.transparent;
  if (m >= 15) return HexaColors.profit.withValues(alpha: 0.85);
  if (m >= 5) return HexaColors.accentAmber.withValues(alpha: 0.9);
  return HexaColors.loss.withValues(alpha: 0.75);
}

Color _itemsRowBg(
  BuildContext context,
  int index,
  double profit,
  double? marginPct,
) {
  final base = _analyticsDataRowColor(context, index, profit);
  if (marginPct == null) return base;
  Color stripe;
  if (marginPct >= 15) {
    stripe = HexaColors.profit.withValues(alpha: 0.14);
  } else if (marginPct >= 5) {
    stripe = HexaColors.accentAmber.withValues(alpha: 0.16);
  } else {
    stripe = HexaColors.loss.withValues(alpha: 0.12);
  }
  return Color.alphaBlend(stripe, base);
}

class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  String _inr(num n) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

  Future<void> _pickFrom(BuildContext context, WidgetRef ref) async {
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: range.from,
      firstDate: DateTime(2020),
      lastDate: range.to,
    );
    if (picked != null) {
      ref.read(analyticsDateRangeProvider.notifier).state = (from: picked, to: range.to);
      _invalidateTables(ref);
    }
  }

  Future<void> _pickTo(BuildContext context, WidgetRef ref) async {
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: range.to,
      firstDate: range.from,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(analyticsDateRangeProvider.notifier).state = (from: range.from, to: picked);
      _invalidateTables(ref);
    }
  }

  void _preset(WidgetRef ref, {required DateTime from, required DateTime to}) {
    ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
    _invalidateTables(ref);
  }

  void _invalidateTables(WidgetRef ref) {
    ref.invalidate(analyticsKpiProvider);
    ref.invalidate(analyticsDailyProfitProvider);
    ref.invalidate(analyticsItemsTableProvider);
    ref.invalidate(analyticsCategoriesTableProvider);
    ref.invalidate(analyticsSuppliersTableProvider);
    ref.invalidate(analyticsBrokersTableProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsDateRangeProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fmt = DateFormat.yMMMd();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final yearStart = DateTime(now.year, 1, 1);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analytics'),
          actions: const [AppSettingsAction()],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Items'),
              Tab(text: 'Categories'),
              Tab(text: 'Suppliers'),
              Tab(text: 'Brokers'),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date range', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickFrom(context, ref),
                          child: Text('From\n${fmt.format(range.from)}', textAlign: TextAlign.center),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTo(context, ref),
                          child: Text('To\n${fmt.format(range.to)}', textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        ActionChip(
                          label: const Text('Today'),
                          onPressed: () => _preset(ref, from: today, to: today),
                        ),
                        ActionChip(
                          label: const Text('Yesterday'),
                          onPressed: () {
                            final y = today.subtract(const Duration(days: 1));
                            _preset(ref, from: y, to: y);
                          },
                        ),
                        ActionChip(
                          label: const Text('This week'),
                          onPressed: () => _preset(ref, from: weekStart, to: today),
                        ),
                        ActionChip(
                          label: const Text('This month'),
                          onPressed: () => _preset(ref, from: monthStart, to: today),
                        ),
                        ActionChip(
                          label: const Text('This year'),
                          onPressed: () => _preset(ref, from: yearStart, to: today),
                        ),
                        ActionChip(
                          label: const Text('Last 7 days'),
                          onPressed: () => _preset(ref, from: today.subtract(const Duration(days: 6)), to: today),
                        ),
                        ActionChip(
                          label: const Text('Last 30 days'),
                          onPressed: () => _preset(ref, from: today.subtract(const Duration(days: 29)), to: today),
                        ),
                        ActionChip(
                          label: const Text('Last month'),
                          onPressed: () {
                            final firstThis = DateTime(now.year, now.month, 1);
                            final lastPrev = firstThis.subtract(const Duration(days: 1));
                            final firstPrev = DateTime(lastPrev.year, lastPrev.month, 1);
                            _preset(ref, from: firstPrev, to: lastPrev);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(cs: cs, tt: tt, inr: _inr),
                  _ItemsTab(inr: _inr),
                  _CategoriesTab(inr: _inr),
                  _SuppliersTab(inr: _inr),
                  _BrokersTab(inr: _inr),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({
    required this.cs,
    required this.tt,
    required this.inr,
  });

  final ColorScheme cs;
  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpi = ref.watch(analyticsKpiProvider);
    final daily = ref.watch(analyticsDailyProfitProvider);
    final items = ref.watch(analyticsItemsTableProvider);
    final cats = ref.watch(analyticsCategoriesTableProvider);
    return kpi.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e', style: TextStyle(color: cs.error))),
      data: (d) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(analyticsKpiProvider);
            ref.invalidate(analyticsDailyProfitProvider);
            ref.invalidate(analyticsItemsTableProvider);
            ref.invalidate(analyticsCategoriesTableProvider);
            await ref.read(analyticsKpiProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Summary', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _OverviewStatCard(
                      label: 'Total profit',
                      value: inr(d.totalProfit),
                      stripe: HexaColors.profit,
                      icon: Icons.trending_up_rounded,
                      iconTint: HexaColors.profit,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OverviewStatCard(
                      label: 'Total purchase',
                      value: inr(d.totalPurchase),
                      stripe: const Color(0xFF2563EB),
                      icon: Icons.shopping_bag_outlined,
                      iconTint: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _OverviewStatCard(
                      label: 'Count',
                      value: '${d.purchaseCount}',
                      stripe: HexaColors.primaryMid,
                      icon: Icons.receipt_long_outlined,
                      iconTint: HexaColors.primaryMid,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OverviewStatCard(
                      label: 'Qty (base)',
                      value: d.totalQtyBase.toStringAsFixed(1),
                      stripe: const Color(0xFF7C3AED),
                      icon: Icons.scale_outlined,
                      iconTint: const Color(0xFF7C3AED),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              daily.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (points) => _ProfitTrendCard(points: points, tt: tt, inr: inr),
              ),
              const SizedBox(height: 12),
              items.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rows) => _TopItemsHorizontalBars(rows: rows, tt: tt, inr: inr),
              ),
              const SizedBox(height: 12),
              cats.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rows) => _CategoryPurchasePie(
                  rows: rows,
                  totalPurchase: d.totalPurchase,
                  tt: tt,
                  inr: inr,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OverviewStatCard extends StatelessWidget {
  const _OverviewStatCard({
    required this.label,
    required this.value,
    required this.stripe,
    required this.icon,
    required this.iconTint,
  });

  final String label;
  final String value;
  final Color stripe;
  final IconData icon;
  final Color iconTint;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HexaColors.border),
          boxShadow: HexaColors.cardShadow(context),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(color: stripe, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: iconTint.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: iconTint),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      fontSize: 11,
                      color: HexaColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: tt.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800, color: HexaColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfitTrendCard extends StatelessWidget {
  const _ProfitTrendCard({
    required this.points,
    required this.tt,
    required this.inr,
  });

  final List<AnalyticsDailyProfitPoint> points;
  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    final hasData = points.any((p) => p.profit > 0);
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].profit),
    ];
    final maxY = spots.isEmpty ? 1.0 : spots.map((s) => s.y).reduce(math.max);
    final minY = 0.0;
    final padY = maxY <= 0 ? 1.0 : maxY * 0.12;
    final fmt = DateFormat.MMMd();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profit trend (30 days)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: hasData
                  ? LineChart(
                      LineChartData(
                        minY: minY,
                        maxY: maxY + padY,
                        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: math.max((maxY + padY) / 4, 1)),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              interval: 5,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    fmt.format(points[i].day),
                                    style: tt.labelSmall?.copyWith(fontSize: 9, color: HexaColors.textSecondary),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, _) => Text(
                                v >= 100000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                                style: tt.labelSmall?.copyWith(fontSize: 10, color: HexaColors.textSecondary),
                              ),
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: HexaColors.profit,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: HexaColors.profit.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: Text(
                        'No data for this period',
                        style: tt.bodyMedium?.copyWith(color: HexaColors.textSecondary),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopItemsHorizontalBars extends StatelessWidget {
  const _TopItemsHorizontalBars({required this.rows, required this.tt, required this.inr});

  final List<Map<String, dynamic>> rows;
  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No items in range', style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary)),
        ),
      );
    }
    final top = rows.take(5).toList();
    final profits = top.map((r) => (r['total_profit'] as num?)?.toDouble() ?? 0.0).toList();
    final maxP = profits.fold<double>(0, math.max);
    final scale = maxP > 0 ? maxP : 1.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top items by profit', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: Column(
                children: [
                  for (var i = 0; i < top.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            top[i]['item_name']?.toString() ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Container(
                                height: 22,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: HexaColors.surfaceMuted,
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: (profits[i] / scale).clamp(0.0, 1.0),
                                child: Container(
                                  height: 22,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    gradient: LinearGradient(
                                      colors: [HexaColors.primaryMid, HexaColors.profit],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: Text(
                            inr(profits[i]),
                            textAlign: TextAlign.end,
                            style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPurchasePie extends StatelessWidget {
  const _CategoryPurchasePie({
    required this.rows,
    required this.totalPurchase,
    required this.tt,
    required this.inr,
  });

  final List<Map<String, dynamic>> rows;
  final double totalPurchase;
  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty || totalPurchase <= 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No category purchase split in this range',
            style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
          ),
        ),
      );
    }
    final pieColors = [
      HexaColors.primaryMid,
      HexaColors.accentAmber,
      HexaColors.profit,
      const Color(0xFF5C6BC0),
      const Color(0xFF00897B),
      const Color(0xFFAD1457),
      const Color(0xFF6D4C41),
      const Color(0xFFE91E63),
    ];
    final qtys = rows.map((r) => (r['total_qty'] as num?)?.toDouble() ?? 0.0).toList();
    final sumQty = qtys.fold<double>(0, (a, b) => a + b);
    final profits = rows.map((r) => (r['total_profit'] as num?)?.toDouble() ?? 0.0).toList();
    final sumProfit = profits.fold<double>(0, (a, b) => a + b);
    final n = math.min(8, rows.length);
    double slicePurchase(int i) {
      if (sumQty > 0) return totalPurchase * (qtys[i] / sumQty);
      if (sumProfit > 0) return totalPurchase * (profits[i] / sumProfit);
      return totalPurchase / n;
    }

    final sliceVals = [for (var i = 0; i < n; i++) slicePurchase(i).clamp(0.0, 1e18)];
    final sumSlices = sliceVals.fold<double>(0, (a, b) => a + b);
    if (sumSlices <= 0) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Categories by purchase (est.)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Shares split by line qty (fallback: profit) · center = total purchase',
              style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 52,
                      sections: [
                        for (var i = 0; i < n; i++)
                          PieChartSectionData(
                            color: pieColors[i % pieColors.length],
                            value: sliceVals[i],
                            title: '${((sliceVals[i] / sumSlices) * 100).toStringAsFixed(0)}%',
                            radius: 54,
                            titleStyle: tt.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total', style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
                      Text(
                        inr(totalPurchase),
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: HexaColors.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < n; i++)
                  Chip(
                    avatar: CircleAvatar(backgroundColor: pieColors[i % pieColors.length], radius: 6),
                    label: Text(
                      rows[i]['category']?.toString() ?? '',
                      style: tt.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemsTab extends ConsumerStatefulWidget {
  const _ItemsTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<_ItemsTab> {
  static const _modes = ['name', 'qty', 'lines', 'avg', 'margin', 'trend', 'profit'];
  int _sortColumnIndex = 6;
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsItemsTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No data in this range'));
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = _sortedRows(
          rows,
          mode,
          _asc,
          (r) => (r['total_profit'] as num?) ?? 0,
        );
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text('${sorted.length} rows', style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title: 'HEXA Items ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const ['Item', 'Qty', 'Lines', 'Avg landing', 'Margin %', 'Trend', 'Profit'],
                      rows: sorted,
                      columns: [
                        (r) => r['item_name']?.toString() ?? '',
                        (r) => ((r['total_qty'] as num?) ?? 0).toString(),
                        (r) => ((r['line_count'] as num?) ?? 0).toString(),
                        (r) => ((r['avg_landing'] as num?) ?? 0).toStringAsFixed(2),
                        (r) => ((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1),
                        (r) => r['trend']?.toString() ?? '',
                        (r) => ((r['total_profit'] as num?) ?? 0).toStringAsFixed(2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(analyticsItemsTableProvider);
                  await ref.read(analyticsItemsTableProvider.future);
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth, minHeight: constraints.maxHeight),
                          child: DataTable(
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _asc,
                            headingRowColor: WidgetStateProperty.all(HexaColors.primaryLight.withValues(alpha: 0.65)),
                            dataTextStyle: tt.bodySmall,
                            columnSpacing: 20,
                            horizontalMargin: 16,
                            columns: [
                              DataColumn(
                                label: const Text('Item'),
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Qty'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Lines'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Avg landing'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Margin %'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Trend'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Profit'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                            ],
                            rows: [
                              for (var i = 0; i < sorted.length; i++)
                                DataRow(
                                  color: WidgetStateProperty.all(
                                    _itemsRowBg(
                                      context,
                                      i,
                                      ((sorted[i]['total_profit'] as num?) ?? 0).toDouble(),
                                      (sorted[i]['margin_pct'] as num?)?.toDouble(),
                                    ),
                                  ),
                                  onSelectChanged: (_) {
                                    final name = sorted[i]['item_name']?.toString() ?? '';
                                    context.push('/item-analytics/${Uri.encodeComponent(name)}');
                                  },
                                  cells: [
                                    DataCell(
                                      Row(
                                        children: [
                                          Container(
                                            width: 4,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: _marginStripeColor((sorted[i]['margin_pct'] as num?)?.toDouble()),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              sorted[i]['item_name']?.toString() ?? '—',
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text('${sorted[i]['total_qty'] ?? '—'}')),
                                    DataCell(
                                      Chip(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        label: Text(
                                          '${sorted[i]['line_count'] ?? '—'}×',
                                          style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: HexaColors.primaryLight.withValues(alpha: 0.9),
                                        side: BorderSide.none,
                                      ),
                                    ),
                                    DataCell(Text(widget.inr(((sorted[i]['avg_landing'] as num?) ?? 0).toDouble()))),
                                    DataCell(
                                      Text(
                                        '${((sorted[i]['margin_pct'] as num?) ?? 0).toStringAsFixed(1)}%',
                                        style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    DataCell(_trendCell(sorted[i]['trend']?.toString())),
                                    DataCell(
                                      Text(
                                        widget.inr(((sorted[i]['total_profit'] as num?) ?? 0).toDouble()),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ((sorted[i]['total_profit'] as num?) ?? 0).toDouble() >= 0 ? HexaColors.profit : HexaColors.loss,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoriesTab extends ConsumerStatefulWidget {
  const _CategoriesTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<_CategoriesTab> {
  static const _modes = ['name', 'best', 'qty', 'lines', 'profit'];
  int _sortColumnIndex = 4;
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsCategoriesTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No categories in this range'));
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = _sortedRows(rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text('${sorted.length} rows', style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title: 'HEXA Categories ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const ['Category', 'Best item', 'Qty', 'Lines', 'Profit'],
                      rows: sorted,
                      columns: [
                        (r) => r['category']?.toString() ?? '',
                        (r) => r['best_item_name']?.toString() ?? '',
                        (r) => ((r['total_qty'] as num?) ?? 0).toString(),
                        (r) => ((r['line_count'] as num?) ?? 0).toString(),
                        (r) => ((r['total_profit'] as num?) ?? 0).toStringAsFixed(2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(analyticsCategoriesTableProvider);
                  await ref.read(analyticsCategoriesTableProvider.future);
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth, minHeight: constraints.maxHeight),
                          child: DataTable(
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _asc,
                            headingRowColor: WidgetStateProperty.all(HexaColors.primaryLight.withValues(alpha: 0.65)),
                            dataTextStyle: tt.bodySmall,
                            columnSpacing: 20,
                            horizontalMargin: 16,
                            columns: [
                              DataColumn(
                                label: const Text('Category'),
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Best item'),
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Qty'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Lines'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Profit'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                            ],
                            rows: [
                              for (var i = 0; i < sorted.length; i++)
                                DataRow(
                                  color: WidgetStateProperty.all(
                                    _analyticsDataRowColor(
                                      context,
                                      i,
                                      ((sorted[i]['total_profit'] as num?) ?? 0).toDouble(),
                                    ),
                                  ),
                                  cells: [
                                    DataCell(Text(sorted[i]['category']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600))),
                                    DataCell(_categoryBestChip(sorted[i]['best_item_name']?.toString(), tt)),
                                    DataCell(Text('${sorted[i]['total_qty'] ?? '—'}')),
                                    DataCell(Text('${sorted[i]['line_count'] ?? '—'}')),
                                    DataCell(
                                      Text(
                                        widget.inr(((sorted[i]['total_profit'] as num?) ?? 0).toDouble()),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ((sorted[i]['total_profit'] as num?) ?? 0).toDouble() >= 0 ? HexaColors.profit : HexaColors.loss,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuppliersTab extends ConsumerStatefulWidget {
  const _SuppliersTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends ConsumerState<_SuppliersTab> {
  static const _modes = ['name', 'deals', 'avg', 'margin', 'profit'];
  int _sortColumnIndex = 4;
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsSuppliersTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No supplier-linked entries in this range'));
        }
        final profitRank = <String, int>{};
        final ranked = List<Map<String, dynamic>>.from(rows);
        ranked.sort((a, b) => ((b['total_profit'] as num?) ?? 0).compareTo((a['total_profit'] as num?) ?? 0));
        for (var j = 0; j < ranked.length && j < 3; j++) {
          final id = ranked[j]['supplier_id']?.toString();
          if (id != null) profitRank[id] = j;
        }
        String medalFor(String? sid) {
          final r = profitRank[sid];
          if (r == null) return '';
          if (r == 0) return '🥇 ';
          if (r == 1) return '🥈 ';
          return '🥉 ';
        }

        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = _sortedRows(rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text('${sorted.length} rows', style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title: 'HEXA Suppliers ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const ['Supplier', 'Deals', 'Avg landing', 'Margin %', 'Profit'],
                      rows: sorted,
                      columns: [
                        (r) => r['supplier_name']?.toString() ?? '',
                        (r) => ((r['deals'] as num?) ?? 0).toString(),
                        (r) => ((r['avg_landing'] as num?) ?? 0).toStringAsFixed(2),
                        (r) => ((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1),
                        (r) => ((r['total_profit'] as num?) ?? 0).toStringAsFixed(2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(analyticsSuppliersTableProvider);
                  await ref.read(analyticsSuppliersTableProvider.future);
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth, minHeight: constraints.maxHeight),
                          child: DataTable(
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _asc,
                            headingRowColor: WidgetStateProperty.all(HexaColors.primaryLight.withValues(alpha: 0.65)),
                            dataTextStyle: tt.bodySmall,
                            columnSpacing: 20,
                            horizontalMargin: 16,
                            columns: [
                              DataColumn(
                                label: const Text('Supplier'),
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Deals'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Avg landing'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Margin %'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Profit'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                            ],
                            rows: [
                              for (var i = 0; i < sorted.length; i++)
                                DataRow(
                                  color: WidgetStateProperty.all(
                                    _analyticsDataRowColor(
                                      context,
                                      i,
                                      ((sorted[i]['total_profit'] as num?) ?? 0).toDouble(),
                                    ),
                                  ),
                                  onSelectChanged: sorted[i]['supplier_id'] == null
                                      ? null
                                      : (_) => context.push('/supplier/${sorted[i]['supplier_id']}'),
                                  cells: [
                                    DataCell(
                                      Text(
                                        '${medalFor(sorted[i]['supplier_id']?.toString())}'
                                        '${sorted[i]['supplier_name']?.toString() ?? '—'}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    DataCell(Text('${sorted[i]['deals'] ?? '—'}')),
                                    DataCell(Text(widget.inr(((sorted[i]['avg_landing'] as num?) ?? 0).toDouble()))),
                                    DataCell(
                                      Text(
                                        '${((sorted[i]['margin_pct'] as num?) ?? 0).toStringAsFixed(1)}%',
                                        style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        widget.inr(((sorted[i]['total_profit'] as num?) ?? 0).toDouble()),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ((sorted[i]['total_profit'] as num?) ?? 0).toDouble() >= 0 ? HexaColors.profit : HexaColors.loss,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BrokersTab extends ConsumerStatefulWidget {
  const _BrokersTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_BrokersTab> createState() => _BrokersTabState();
}

class _BrokersTabState extends ConsumerState<_BrokersTab> {
  static const _modes = ['name', 'deals', 'commission', 'commission_pct', 'profit'];
  int _sortColumnIndex = 4;
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsBrokersTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No broker-linked entries in this range'));
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = _sortedRows(rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text('${sorted.length} rows', style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title: 'HEXA Brokers ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const ['Broker', 'Deals', 'Commission', 'Comm % of profit', 'Profit'],
                      rows: sorted,
                      columns: [
                        (r) => r['broker_name']?.toString() ?? '',
                        (r) => ((r['deals'] as num?) ?? 0).toString(),
                        (r) => ((r['total_commission'] as num?) ?? 0).toStringAsFixed(2),
                        (r) => ((r['commission_pct_of_profit'] as num?) ?? 0).toStringAsFixed(1),
                        (r) => ((r['total_profit'] as num?) ?? 0).toStringAsFixed(2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(analyticsBrokersTableProvider);
                  await ref.read(analyticsBrokersTableProvider.future);
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth, minHeight: constraints.maxHeight),
                          child: DataTable(
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _asc,
                            headingRowColor: WidgetStateProperty.all(HexaColors.primaryLight.withValues(alpha: 0.65)),
                            dataTextStyle: tt.bodySmall,
                            columnSpacing: 20,
                            horizontalMargin: 16,
                            columns: [
                              DataColumn(
                                label: const Text('Broker'),
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Deals'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Commission'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Comm %'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('Profit'),
                                numeric: true,
                                onSort: (i, asc) => setState(() {
                                  _sortColumnIndex = i;
                                  _asc = asc;
                                }),
                              ),
                            ],
                            rows: [
                              for (var i = 0; i < sorted.length; i++)
                                DataRow(
                                  color: WidgetStateProperty.all(
                                    _analyticsDataRowColor(
                                      context,
                                      i,
                                      ((sorted[i]['total_profit'] as num?) ?? 0).toDouble(),
                                    ),
                                  ),
                                  onSelectChanged: sorted[i]['broker_id'] == null
                                      ? null
                                      : (_) => context.push('/broker/${sorted[i]['broker_id']}'),
                                  cells: [
                                    DataCell(Text(sorted[i]['broker_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600))),
                                    DataCell(Text('${sorted[i]['deals'] ?? '—'}')),
                                    DataCell(Text(widget.inr(((sorted[i]['total_commission'] as num?) ?? 0).toDouble()))),
                                    DataCell(
                                      Builder(
                                        builder: (context) {
                                          final cp = ((sorted[i]['commission_pct_of_profit'] as num?) ?? 0).toDouble();
                                          final warn = cp > 10;
                                          return Text(
                                            '${cp.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: warn ? HexaColors.accentAmber : HexaColors.textSecondary,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        widget.inr(((sorted[i]['total_profit'] as num?) ?? 0).toDouble()),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ((sorted[i]['total_profit'] as num?) ?? 0).toDouble() >= 0 ? HexaColors.profit : HexaColors.loss,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
