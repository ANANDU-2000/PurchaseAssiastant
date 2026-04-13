import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/analytics_kpi_provider.dart'
    show analyticsDateRangeProvider, analyticsKpiProvider;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/app_settings_action.dart';

/// KPI can succeed while a dependent chart request fails — one card per slice (clear label).
Widget _overviewSliceError(
  BuildContext context,
  String sectionLabel,
  VoidCallback onRetry,
) {
  return Container(
    margin: const EdgeInsets.only(top: 4, bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: HexaColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: HexaColors.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sectionLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Could not load this section.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ),
      ],
    ),
  );
}

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
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_up_rounded, size: 18, color: HexaColors.profit),
          SizedBox(width: 4),
          Text('Up',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: HexaColors.profit,
                  fontSize: 12)),
        ],
      );
    case 'down':
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_down_rounded, size: 18, color: HexaColors.loss),
          SizedBox(width: 4),
          Text('Down',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: HexaColors.loss,
                  fontSize: 12)),
        ],
      );
    case 'flat':
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_flat_rounded,
              size: 18, color: HexaColors.textSecondary),
          SizedBox(width: 4),
          Text('Flat',
              style: TextStyle(color: HexaColors.textSecondary, fontSize: 12)),
        ],
      );
    default:
      return Text(
        '—',
        style: TextStyle(
            color: HexaColors.textSecondary.withValues(alpha: 0.85),
            fontSize: 12),
      );
  }
}

Widget _categoryBestChip(String? name, TextTheme tt) {
  if (name == null || name.isEmpty) {
    return Text('—',
        style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary));
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
        return (a['best_item_name'] ?? '')
            .toString()
            .compareTo((b['best_item_name'] ?? '').toString());
      case 'name':
        return (a['item_name'] ??
                a['category'] ??
                a['supplier_name'] ??
                a['broker_name'] ??
                '')
            .toString()
            .compareTo((b['item_name'] ??
                    b['category'] ??
                    b['supplier_name'] ??
                    b['broker_name'] ??
                    '')
                .toString());
      case 'qty':
        return ((a['total_qty'] as num?) ?? 0)
            .compareTo((b['total_qty'] as num?) ?? 0);
      case 'lines':
        return ((a['line_count'] as num?) ?? 0)
            .compareTo((b['line_count'] as num?) ?? 0);
      case 'deals':
        return ((a['deals'] as num?) ?? 0).compareTo((b['deals'] as num?) ?? 0);
      case 'avg':
        return ((a['avg_landing'] as num?) ?? 0)
            .compareTo((b['avg_landing'] as num?) ?? 0);
      case 'commission':
        return ((a['total_commission'] as num?) ?? 0)
            .compareTo((b['total_commission'] as num?) ?? 0);
      case 'margin':
        return ((a['margin_pct'] as num?) ?? 0)
            .compareTo((b['margin_pct'] as num?) ?? 0);
      case 'trend':
        return _trendSortKey(a).compareTo(_trendSortKey(b));
      case 'commission_pct':
        return ((a['commission_pct_of_profit'] as num?) ?? 0)
            .compareTo((b['commission_pct_of_profit'] as num?) ?? 0);
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

Color _marginStripeColor(double? m) {
  if (m == null) return Colors.transparent;
  if (m >= 15) return HexaColors.profit.withValues(alpha: 0.85);
  if (m >= 5) return HexaColors.accentAmber.withValues(alpha: 0.9);
  return HexaColors.loss.withValues(alpha: 0.75);
}

List<Map<String, dynamic>> _filterQuery(
    List<Map<String, dynamic>> rows, String q, String field) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return rows;
  return rows
      .where((r) => (r[field]?.toString() ?? '').toLowerCase().contains(t))
      .toList();
}

class _AnalyticsDateChip extends StatelessWidget {
  const _AnalyticsDateChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: HexaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: tt.labelMedium?.copyWith(
                color: HexaColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  String _inr(num n) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(n);

  Future<void> _pickFrom(BuildContext context, WidgetRef ref) async {
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: range.from,
      firstDate: DateTime(2020),
      lastDate: range.to,
    );
    if (picked != null) {
      ref.read(analyticsDateRangeProvider.notifier).state =
          (from: picked, to: range.to);
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
      ref.read(analyticsDateRangeProvider.notifier).state =
          (from: range.from, to: picked);
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
    ref.invalidate(analyticsBestSupplierInsightProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsDateRangeProvider);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat.yMMMd();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final yearStart = DateTime(now.year, 1, 1);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: context.adaptiveScaffold,
        appBar: AppBar(
          backgroundColor: context.adaptiveAppBarBg,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          actions: const [AppSettingsAction()],
          bottom: TabBar(
            isScrollable: true,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            tabs: const [
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${fmt.format(range.from)} – ${fmt.format(range.to)}',
                          style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _pickFrom(context, ref),
                        icon:
                            const Icon(Icons.calendar_month_rounded, size: 18),
                        label: const Text('From'),
                        style: TextButton.styleFrom(
                            foregroundColor: HexaColors.primaryMid),
                      ),
                      TextButton.icon(
                        onPressed: () => _pickTo(context, ref),
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: const Text('To'),
                        style: TextButton.styleFrom(
                            foregroundColor: HexaColors.primaryMid),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _AnalyticsDateChip(
                            label: 'Today',
                            onTap: () => _preset(ref, from: today, to: today)),
                        _AnalyticsDateChip(
                          label: 'Yesterday',
                          onTap: () {
                            final y = today.subtract(const Duration(days: 1));
                            _preset(ref, from: y, to: y);
                          },
                        ),
                        _AnalyticsDateChip(
                            label: 'This week',
                            onTap: () =>
                                _preset(ref, from: weekStart, to: today)),
                        _AnalyticsDateChip(
                            label: 'This month',
                            onTap: () =>
                                _preset(ref, from: monthStart, to: today)),
                        _AnalyticsDateChip(
                            label: 'This year',
                            onTap: () =>
                                _preset(ref, from: yearStart, to: today)),
                        _AnalyticsDateChip(
                          label: 'Last 7 days',
                          onTap: () => _preset(ref,
                              from: today.subtract(const Duration(days: 6)),
                              to: today),
                        ),
                        _AnalyticsDateChip(
                          label: 'Last 30 days',
                          onTap: () => _preset(ref,
                              from: today.subtract(const Duration(days: 29)),
                              to: today),
                        ),
                        _AnalyticsDateChip(
                          label: 'Last month',
                          onTap: () {
                            final firstThis = DateTime(now.year, now.month, 1);
                            final lastPrev =
                                firstThis.subtract(const Duration(days: 1));
                            final firstPrev =
                                DateTime(lastPrev.year, lastPrev.month, 1);
                            _preset(ref, from: firstPrev, to: lastPrev);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(tt: tt, inr: _inr),
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
    required this.tt,
    required this.inr,
  });

  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurf = Theme.of(context).colorScheme.onSurface;
    final kpi = ref.watch(analyticsKpiProvider);
    final daily = ref.watch(analyticsDailyProfitProvider);
    final items = ref.watch(analyticsItemsTableProvider);
    final cats = ref.watch(analyticsCategoriesTableProvider);
    final sup = ref.watch(analyticsSuppliersTableProvider);
    return kpi.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(analyticsKpiProvider);
          ref.invalidate(analyticsDailyProfitProvider);
          ref.invalidate(analyticsItemsTableProvider);
          ref.invalidate(analyticsCategoriesTableProvider);
          ref.invalidate(analyticsSuppliersTableProvider);
          ref.invalidate(analyticsBestSupplierInsightProvider);
        },
      ),
      data: (d) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(analyticsKpiProvider);
            ref.invalidate(analyticsDailyProfitProvider);
            ref.invalidate(analyticsItemsTableProvider);
            ref.invalidate(analyticsCategoriesTableProvider);
            ref.invalidate(analyticsSuppliersTableProvider);
            ref.invalidate(analyticsBestSupplierInsightProvider);
            await ref.read(analyticsKpiProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('Overview',
                  style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: onSurf)),
              const SizedBox(height: 12),
              SizedBox(
                height: 112,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    SizedBox(
                      width: 168,
                      child: _OverviewStatCard(
                        label: 'Total purchase',
                        value: inr(d.totalPurchase),
                        stripe: HexaColors.chartLandingCost,
                        icon: Icons.shopping_bag_outlined,
                        iconTint: HexaColors.chartLandingCost,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 168,
                      child: _OverviewStatCard(
                        label: 'Total profit',
                        value: inr(d.totalProfit),
                        stripe: HexaColors.profit,
                        icon: Icons.trending_up_rounded,
                        iconTint: HexaColors.profit,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 168,
                      child: _OverviewStatCard(
                        label: 'Purchase count',
                        value: '${d.purchaseCount}',
                        stripe: HexaColors.chartPurple,
                        icon: Icons.receipt_long_outlined,
                        iconTint: HexaColors.chartPurple,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 168,
                      child: _OverviewStatCard(
                        label: 'Total qty',
                        value: d.totalQtyBase.toStringAsFixed(1),
                        stripe: HexaColors.chartOrange,
                        icon: Icons.scale_outlined,
                        iconTint: HexaColors.chartOrange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              daily.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => _overviewSliceError(
                    context,
                    'Daily profit trend',
                    () => ref.invalidate(analyticsDailyProfitProvider)),
                data: (points) =>
                    _ProfitTrendCard(points: points, tt: tt, inr: inr),
              ),
              const SizedBox(height: 12),
              items.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => _overviewSliceError(
                    context,
                    'Item costs & revenue',
                    () => ref.invalidate(analyticsItemsTableProvider)),
                data: (rows) =>
                    _ItemCostRevenueBars(rows: rows, tt: tt, inr: inr),
              ),
              const SizedBox(height: 12),
              cats.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => _overviewSliceError(
                    context,
                    'Category split',
                    () => ref.invalidate(analyticsCategoriesTableProvider)),
                data: (rows) =>
                    _CategoryProfitDonut(rows: rows, tt: tt, inr: inr),
              ),
              const SizedBox(height: 12),
              sup.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => _overviewSliceError(
                    context,
                    'Supplier performance',
                    () => ref.invalidate(analyticsSuppliersTableProvider)),
                data: (rows) => _SupplierMarginPerformers(rows: rows, tt: tt),
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
      color: HexaColors.surfaceCard,
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
              decoration: BoxDecoration(
                  color: stripe, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: iconTint.withValues(alpha: 0.1),
                  shape: BoxShape.circle),
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
                    style: tt.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: HexaColors.textPrimary),
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
    final allZero = points.isEmpty || points.every((p) => p.profit == 0);
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].profit),
    ];
    final maxY = spots.isEmpty ? 1.0 : spots.map((s) => s.y).reduce(math.max);
    final padY = maxY <= 0 ? 1.0 : maxY * 0.12;
    final fmt = DateFormat.MMMd();

    String yLabel(double v) {
      if (v >= 100000) return '₹${(v / 1000).toStringAsFixed(0)}K';
      if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
      return '₹${v.toStringAsFixed(0)}';
    }

    return Container(
      decoration: BoxDecoration(
        color: HexaColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HexaColors.border),
        boxShadow: HexaColors.cardShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profit trend (30 days)',
              style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800, color: HexaColors.textPrimary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: allZero
                ? Center(
                    child: Text(
                      'Add purchases to see trend',
                      style: tt.bodyMedium
                          ?.copyWith(color: HexaColors.textSecondary),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxY + padY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: math.max((maxY + padY) / 4, 1),
                        getDrawingHorizontalLine: (v) => FlLine(
                            color: HexaColors.border.withValues(alpha: 0.5),
                            strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touched) {
                            return touched.map((t) {
                              final i = t.x.toInt().clamp(0, points.length - 1);
                              final p = points[i];
                              return LineTooltipItem(
                                '${fmt.format(p.day)}\n${inr(p.profit)}',
                                const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              );
                            }).toList();
                          },
                          getTooltipColor: (_) => HexaColors.surfaceElevated,
                        ),
                        handleBuiltInTouches: true,
                        getTouchedSpotIndicator: (bar, spot) => [
                          TouchedSpotIndicatorData(
                            const FlLine(
                                color: HexaColors.primaryMid, strokeWidth: 1),
                            FlDotData(
                              show: true,
                              getDotPainter: (s, p, bar, i) =>
                                  FlDotCirclePainter(
                                radius: 4,
                                color: HexaColors.primaryMid,
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: math.max(
                                1, (points.length / 5).floorToDouble()),
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= points.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  fmt.format(points[i].day),
                                  style: tt.labelSmall?.copyWith(
                                      fontSize: 9,
                                      color: HexaColors.textSecondary),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (v, _) => Text(
                              yLabel(v),
                              style: tt.labelSmall?.copyWith(
                                  fontSize: 9, color: HexaColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: HexaColors.primaryMid,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                HexaColors.primaryMid.withValues(alpha: 0.15),
                                HexaColors.primaryMid.withValues(alpha: 0.02),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Top 6 items by estimated purchase (avg_landing × qty): landing cost vs selling revenue.
class _ItemCostRevenueBars extends StatelessWidget {
  const _ItemCostRevenueBars(
      {required this.rows, required this.tt, required this.inr});

  final List<Map<String, dynamic>> rows;
  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HexaColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HexaColors.border),
        ),
        child: Text('No items in range',
            style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary)),
      );
    }
    final ranked = List<Map<String, dynamic>>.from(rows);
    ranked.sort((a, b) {
      final av = ((a['avg_landing'] as num?) ?? 0).toDouble() *
          ((a['total_qty'] as num?) ?? 0).toDouble();
      final bv = ((b['avg_landing'] as num?) ?? 0).toDouble() *
          ((b['total_qty'] as num?) ?? 0).toDouble();
      return bv.compareTo(av);
    });
    final top = ranked.take(6).toList();
    var maxY = 1.0;
    for (final r in top) {
      final al = (r['avg_landing'] as num?)?.toDouble() ?? 0;
      final tq = (r['total_qty'] as num?)?.toDouble() ?? 0;
      final tp = (r['total_profit'] as num?)?.toDouble() ?? 0;
      final land = al * tq;
      final sell = land + tp;
      maxY = math.max(maxY, math.max(land, sell));
    }
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < top.length; i++) {
      final r = top[i];
      final al = (r['avg_landing'] as num?)?.toDouble() ?? 0;
      final tq = (r['total_qty'] as num?)?.toDouble() ?? 0;
      final tp = (r['total_profit'] as num?)?.toDouble() ?? 0;
      final land = al * tq;
      final sell = land + tp;
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 4,
          barRods: [
            BarChartRodData(
              toY: land,
              width: 10,
              color: HexaColors.chartLandingCost,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            BarChartRodData(
              toY: sell,
              width: 10,
              color: HexaColors.chartSellingCost,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: HexaColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HexaColors.border),
        boxShadow: HexaColors.cardShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Landing vs selling (top 6 items)',
              style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800, color: HexaColors.textPrimary)),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: HexaColors.chartLandingCost,
                      shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Landing cost',
                  style:
                      tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
              const SizedBox(width: 16),
              Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: HexaColors.chartSellingCost,
                      shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Selling revenue',
                  style:
                      tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.08,
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) => FlLine(
                        color: HexaColors.border.withValues(alpha: 0.4))),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      reservedSize: 40,
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(
                        v >= 100000
                            ? '₹${(v / 1000).toStringAsFixed(0)}k'
                            : '₹${v.toStringAsFixed(0)}',
                        style: tt.labelSmall?.copyWith(
                            fontSize: 9, color: HexaColors.textSecondary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= top.length) {
                          return const SizedBox.shrink();
                        }
                        final raw = top[i]['item_name']?.toString() ?? '';
                        final t =
                            raw.length > 8 ? '${raw.substring(0, 8)}…' : raw;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(t,
                              style: tt.labelSmall?.copyWith(
                                  fontSize: 9,
                                  color: HexaColors.textSecondary)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: groups,
                alignment: BarChartAlignment.spaceAround,
                groupsSpace: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryProfitDonut extends StatelessWidget {
  const _CategoryProfitDonut(
      {required this.rows, required this.tt, required this.inr});

  final List<Map<String, dynamic>> rows;
  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HexaColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HexaColors.border),
        ),
        child: Text('No categories in this range',
            style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary)),
      );
    }
    final profits = rows
        .map((r) => (r['total_profit'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final sumProfit = profits.fold<double>(0, (a, b) => a + b);
    final n = math.min(8, rows.length);
    if (sumProfit <= 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HexaColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HexaColors.border),
        ),
        child: Text('No profit in categories for this range',
            style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary)),
      );
    }
    final sliceVals = [for (var i = 0; i < n; i++) profits[i].clamp(0.0, 1e18)];
    final sumSlices = sliceVals.fold<double>(0, (a, b) => a + b);
    if (sumSlices <= 0) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: HexaColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HexaColors.border),
        boxShadow: HexaColors.cardShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category profit',
              style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800, color: HexaColors.textPrimary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
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
                          color: HexaColors
                              .chartPalette[i % HexaColors.chartPalette.length],
                          value: sliceVals[i],
                          title:
                              '${((sliceVals[i] / sumSlices) * 100).toStringAsFixed(0)}%',
                          radius: 54,
                          titleStyle: tt.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11),
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total profit',
                        style: tt.labelSmall
                            ?.copyWith(color: HexaColors.textSecondary)),
                    Text(
                      inr(sumProfit),
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: HexaColors.textPrimary),
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
                  avatar: CircleAvatar(
                    backgroundColor: HexaColors
                        .chartPalette[i % HexaColors.chartPalette.length],
                    radius: 6,
                  ),
                  label: Text(
                    rows[i]['category']?.toString() ?? '',
                    style:
                        tt.labelSmall?.copyWith(color: HexaColors.textPrimary),
                  ),
                  backgroundColor: HexaColors.surfaceElevated,
                  side: const BorderSide(color: HexaColors.border),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierMarginPerformers extends StatelessWidget {
  const _SupplierMarginPerformers({required this.rows, required this.tt});

  final List<Map<String, dynamic>> rows;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final ranked = List<Map<String, dynamic>>.from(rows);
    ranked.sort((a, b) => ((b['margin_pct'] as num?) ?? 0)
        .compareTo((a['margin_pct'] as num?) ?? 0));
    final top = ranked.take(5).toList();
    final maxM = top
        .map((r) => (r['margin_pct'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, math.max);
    final scale = maxM > 0 ? maxM : 1.0;
    return Container(
      decoration: BoxDecoration(
        color: HexaColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HexaColors.border),
        boxShadow: HexaColors.cardShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Supplier margin',
                  style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: HexaColors.textPrimary)),
              const Spacer(),
              if (top.isNotEmpty)
                Chip(
                  avatar: const Text('🥇', style: TextStyle(fontSize: 12)),
                  label: Text(top.first['supplier_name']?.toString() ?? '',
                      style: tt.labelSmall),
                  backgroundColor:
                      HexaColors.primaryLight.withValues(alpha: 0.9),
                  side: BorderSide(
                      color: HexaColors.primaryMid.withValues(alpha: 0.4)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          top[i]['supplier_name']?.toString() ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: HexaColors.textPrimary),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: HexaColors.surfaceElevated,
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: (((top[i]['margin_pct'] as num?)
                                              ?.toDouble() ??
                                          0) /
                                      scale)
                                  .clamp(0.0, 1.0),
                              child: Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  gradient: const LinearGradient(colors: [
                                    HexaColors.primaryMid,
                                    HexaColors.primaryDeep
                                  ]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${((top[i]['margin_pct'] as num?) ?? 0).toStringAsFixed(1)}%',
                        style: tt.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: HexaColors.primaryMid),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
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
  static const _modes = [
    'name',
    'qty',
    'lines',
    'avg',
    'margin',
    'trend',
    'profit'
  ];
  static const _modeLabels = [
    'Name',
    'Qty',
    'Lines',
    'Avg',
    'Margin',
    'Trend',
    'Profit'
  ];
  int _sortColumnIndex = 6;
  bool _asc = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsItemsTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(analyticsItemsTableProvider),
      ),
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
        final filtered = _filterQuery(sorted, _search.text, 'item_name');
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium?.copyWith(color: HexaColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search items…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: HexaColors.surfaceElevated,
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_modeLabels[i]),
                        selected: _sortColumnIndex == i,
                        onSelected: (_) => setState(() {
                          if (_sortColumnIndex == i) {
                            _asc = !_asc;
                          } else {
                            _sortColumnIndex = i;
                            _asc = i == 0;
                          }
                        }),
                        selectedColor:
                            HexaColors.primaryLight.withValues(alpha: 0.95),
                        checkmarkColor: HexaColors.primaryDeep,
                        labelStyle: tt.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} items',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title:
                          '${AppConfig.appName} Items ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Item',
                        'Qty',
                        'Lines',
                        'Avg landing',
                        'Margin %',
                        'Trend',
                        'Profit'
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['item_name']?.toString() ?? '',
                        (r) => ((r['total_qty'] as num?) ?? 0).toString(),
                        (r) => ((r['line_count'] as num?) ?? 0).toString(),
                        (r) => ((r['avg_landing'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) =>
                            ((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1),
                        (r) => r['trend']?.toString() ?? '',
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
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
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                              child: Text('No matches',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final al =
                              (r['avg_landing'] as num?)?.toDouble() ?? 0;
                          final tq = (r['total_qty'] as num?)?.toDouble() ?? 0;
                          final tp =
                              (r['total_profit'] as num?)?.toDouble() ?? 0;
                          final land = al * tq;
                          final sell = land + tp;
                          final maxBar = math.max(land, sell);
                          final fLand = maxBar > 0
                              ? (land / maxBar).clamp(0.0, 1.0)
                              : 0.0;
                          final fProfit = maxBar > 0
                              ? ((sell - land).abs() / maxBar).clamp(0.0, 1.0)
                              : 0.0;
                          final name = r['item_name']?.toString() ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: HexaColors.surfaceCard,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: name.isEmpty
                                    ? null
                                    : () => context.push(
                                        '/item-analytics/${Uri.encodeComponent(name)}'),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border:
                                        Border.all(color: HexaColors.border),
                                    boxShadow: HexaColors.cardShadow(context),
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 4,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: _marginStripeColor(
                                                  (r['margin_pct'] as num?)
                                                      ?.toDouble()),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name.isEmpty ? '—' : name,
                                                  style: tt.titleSmall
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: HexaColors
                                                              .textPrimary),
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    _trendCell(
                                                        r['trend']?.toString()),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      '${((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1)}% margin',
                                                      style: tt.labelSmall
                                                          ?.copyWith(
                                                              color: HexaColors
                                                                  .textSecondary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            widget.inr(tp),
                                            style: tt.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              color: tp >= 0
                                                  ? HexaColors.profit
                                                  : HexaColors.loss,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          height: 10,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: math.max(
                                                    1, (fLand * 1000).round()),
                                                child: Container(
                                                    color: HexaColors
                                                        .chartLandingCost),
                                              ),
                                              Expanded(
                                                flex: math.max(1,
                                                    (fProfit * 1000).round()),
                                                child: Container(
                                                    color: HexaColors
                                                        .chartSellingCost),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text('Qty ${tq.toStringAsFixed(1)}',
                                              style: tt.labelSmall?.copyWith(
                                                  color: HexaColors
                                                      .textSecondary)),
                                          const SizedBox(width: 12),
                                          Text(
                                              '${r['line_count'] ?? '—'} lines',
                                              style: tt.labelSmall?.copyWith(
                                                  color: HexaColors
                                                      .textSecondary)),
                                          const Spacer(),
                                          Text('Avg ${widget.inr(al)}',
                                              style: tt.labelSmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      HexaColors.textPrimary)),
                                        ],
                                      ),
                                    ],
                                  ),
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
  static const _modeLabels = [
    'Category',
    'Best item',
    'Qty',
    'Lines',
    'Profit'
  ];
  int _sortColumnIndex = 4;
  bool _asc = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsCategoriesTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(analyticsCategoriesTableProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No categories in this range'));
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = _sortedRows(
            rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final filtered = _filterQuery(sorted, _search.text, 'category');
        final profits = sorted
            .map((r) => (r['total_profit'] as num?)?.toDouble() ?? 0.0)
            .toList();
        final maxP = profits.fold<double>(0, math.max);
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium?.copyWith(color: HexaColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search categories…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: HexaColors.surfaceElevated,
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_modeLabels[i]),
                        selected: _sortColumnIndex == i,
                        onSelected: (_) => setState(() {
                          if (_sortColumnIndex == i) {
                            _asc = !_asc;
                          } else {
                            _sortColumnIndex = i;
                            _asc = i == 0;
                          }
                        }),
                        selectedColor:
                            HexaColors.primaryLight.withValues(alpha: 0.95),
                        checkmarkColor: HexaColors.primaryDeep,
                        labelStyle: tt.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} categories',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title:
                          '${AppConfig.appName} Categories ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Category',
                        'Best item',
                        'Qty',
                        'Lines',
                        'Profit'
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['category']?.toString() ?? '',
                        (r) => r['best_item_name']?.toString() ?? '',
                        (r) => ((r['total_qty'] as num?) ?? 0).toString(),
                        (r) => ((r['line_count'] as num?) ?? 0).toString(),
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
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
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                              child: Text('No matches',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final r = filtered[idx];
                          final cat = r['category']?.toString() ?? '—';
                          final profit =
                              ((r['total_profit'] as num?) ?? 0).toDouble();
                          final share =
                              maxP > 0 ? (profit / maxP).clamp(0.0, 1.0) : 0.0;
                          final color = HexaColors.chartPalette[
                              idx % HexaColors.chartPalette.length];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: HexaColors.surfaceCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: HexaColors.border),
                                boxShadow: HexaColors.cardShadow(context),
                              ),
                              child: Theme(
                                data: Theme.of(context)
                                    .copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 4),
                                  childrenPadding:
                                      const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor:
                                        color.withValues(alpha: 0.25),
                                    child: Text(
                                      cat.isNotEmpty
                                          ? cat[0].toUpperCase()
                                          : '?',
                                      style: tt.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: color),
                                    ),
                                  ),
                                  title: Text(cat,
                                      style: tt.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: HexaColors.textPrimary)),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: share,
                                        minHeight: 8,
                                        backgroundColor:
                                            HexaColors.surfaceElevated,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                            child: Text('Profit',
                                                style: tt.labelSmall?.copyWith(
                                                    color: HexaColors
                                                        .textSecondary))),
                                        Text(
                                          widget.inr(profit),
                                          style: tt.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: profit >= 0
                                                ? HexaColors.profit
                                                : HexaColors.loss,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            size: 18,
                                            color: HexaColors.accentAmber),
                                        const SizedBox(width: 6),
                                        Text('Best mover',
                                            style: tt.labelSmall?.copyWith(
                                                color:
                                                    HexaColors.textSecondary)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    _categoryBestChip(
                                        r['best_item_name']?.toString(), tt),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        _catMiniStat(Icons.scale_outlined,
                                            'Qty ${r['total_qty'] ?? '—'}', tt),
                                        const SizedBox(width: 12),
                                        _catMiniStat(
                                            Icons.receipt_long_outlined,
                                            '${r['line_count'] ?? '—'} lines',
                                            tt),
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

Widget _catMiniStat(IconData icon, String text, TextTheme tt) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: HexaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HexaColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: HexaColors.primaryMid),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    ),
  );
}

class _SuppliersTab extends ConsumerStatefulWidget {
  const _SuppliersTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends ConsumerState<_SuppliersTab> {
  static const _modes = ['name', 'deals', 'avg', 'margin', 'profit'];
  static const _modeLabels = ['Name', 'Deals', 'Avg ₹', 'Margin', 'Profit'];
  int _sortColumnIndex = 4;
  bool _asc = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsSuppliersTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(analyticsSuppliersTableProvider);
          ref.invalidate(analyticsBestSupplierInsightProvider);
        },
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
              child: Text('No supplier-linked entries in this range'));
        }
        final profitRank = <String, int>{};
        final ranked = List<Map<String, dynamic>>.from(rows);
        ranked.sort((a, b) => ((b['total_profit'] as num?) ?? 0)
            .compareTo((a['total_profit'] as num?) ?? 0));
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
        final sorted = _sortedRows(
            rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final filtered = _filterQuery(sorted, _search.text, 'supplier_name');
        final tt = Theme.of(context).textTheme;
        final insight = ref.watch(analyticsBestSupplierInsightProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Supplier Intelligence',
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: HexaColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    'Which supplier gives best price for each item?',
                    style:
                        tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
                  ),
                ],
              ),
            ),
            insight.when(
              data: (msg) {
                if (msg == null || msg.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          HexaColors.heroGradientEnd,
                          HexaColors.primaryDeep,
                          HexaColors.primaryMid
                        ],
                      ),
                      border: Border.all(
                          color: HexaColors.primaryMid.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      msg,
                      style: tt.bodySmall?.copyWith(
                          color: HexaColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.35),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _overviewSliceError(
                  context,
                  'Supplier insight',
                  () => ref.invalidate(analyticsBestSupplierInsightProvider),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium?.copyWith(color: HexaColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search suppliers…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: HexaColors.surfaceElevated,
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_modeLabels[i]),
                        selected: _sortColumnIndex == i,
                        onSelected: (_) => setState(() {
                          if (_sortColumnIndex == i) {
                            _asc = !_asc;
                          } else {
                            _sortColumnIndex = i;
                            _asc = i == 0;
                          }
                        }),
                        selectedColor:
                            HexaColors.primaryLight.withValues(alpha: 0.95),
                        checkmarkColor: HexaColors.primaryDeep,
                        labelStyle: tt.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} suppliers',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title:
                          '${AppConfig.appName} Suppliers ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Supplier',
                        'Deals',
                        'Avg landing',
                        'Margin %',
                        'Profit'
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['supplier_name']?.toString() ?? '',
                        (r) => ((r['deals'] as num?) ?? 0).toString(),
                        (r) => ((r['avg_landing'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) =>
                            ((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1),
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
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
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                              child: Text('No matches',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final sid = r['supplier_id']?.toString();
                          final m = (r['margin_pct'] as num?)?.toDouble() ?? 0;
                          final profit =
                              ((r['total_profit'] as num?) ?? 0).toDouble();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: HexaColors.surfaceCard,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: sid == null
                                    ? null
                                    : () => context.push('/supplier/$sid'),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border:
                                        Border.all(color: HexaColors.border),
                                    boxShadow: HexaColors.cardShadow(context),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      tilePadding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 4),
                                      childrenPadding:
                                          const EdgeInsets.fromLTRB(
                                              14, 0, 14, 14),
                                      title: Text(
                                        '${medalFor(sid)}${r['supplier_name']?.toString() ?? '—'}',
                                        style: tt.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w800),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          children: [
                                            Text('${r['deals'] ?? '—'} deals',
                                                style: tt.labelSmall?.copyWith(
                                                    color: HexaColors
                                                        .textSecondary)),
                                            const Text(' · ',
                                                style: TextStyle(
                                                    color: HexaColors
                                                        .textSecondary)),
                                            Text(
                                              widget.inr(profit),
                                              style: tt.labelSmall?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: profit >= 0
                                                    ? HexaColors.profit
                                                    : HexaColors.loss,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      children: [
                                        Text('Margin profile',
                                            style: tt.labelSmall?.copyWith(
                                                color: HexaColors.textSecondary,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: (m / 30).clamp(0.0, 1.0),
                                            minHeight: 10,
                                            backgroundColor:
                                                HexaColors.surfaceElevated,
                                            color: m >= 15
                                                ? HexaColors.profit
                                                : (m >= 5
                                                    ? HexaColors.accentAmber
                                                    : HexaColors.loss),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                                '${m.toStringAsFixed(1)}% margin',
                                                style: tt.labelSmall?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Text(
                                                'Avg ${widget.inr(((r['avg_landing'] as num?) ?? 0).toDouble())}',
                                                style: tt.labelSmall?.copyWith(
                                                    color: HexaColors
                                                        .textSecondary)),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text('Activity (relative)',
                                            style: tt.labelSmall?.copyWith(
                                                color: HexaColors.textSecondary,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          height: 48,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: [
                                              for (var k = 0; k < 5; k++)
                                                _SupplierSparkBar(
                                                    seed: '${sid}_$k',
                                                    marginHint: m,
                                                    index: k),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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

/// Decorative mini bars (no per-day API); deterministic from supplier id.
class _SupplierSparkBar extends StatelessWidget {
  const _SupplierSparkBar(
      {required this.seed, required this.marginHint, required this.index});

  final String seed;
  final double marginHint;
  final int index;

  @override
  Widget build(BuildContext context) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final jitter = ((h >> (index * 5)) & 0xff) / 255.0;
    final base = (marginHint / 25).clamp(0.15, 1.0);
    final fh = (28 * base * (0.65 + 0.35 * jitter)).clamp(8.0, 44.0);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          height: fh,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                HexaColors.primaryDeep.withValues(alpha: 0.5),
                HexaColors.primaryMid
              ],
            ),
          ),
        ),
      ),
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
  static const _modes = [
    'name',
    'deals',
    'commission',
    'commission_pct',
    'profit'
  ];
  static const _modeLabels = [
    'Name',
    'Deals',
    'Commission',
    'Comm %',
    'Profit'
  ];
  int _sortColumnIndex = 4;
  bool _asc = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsBrokersTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(analyticsBrokersTableProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
              child: Text('No broker-linked entries in this range'));
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = _sortedRows(
            rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final filtered = _filterQuery(sorted, _search.text, 'broker_name');
        final tt = Theme.of(context).textTheme;
        final chartRows = List<Map<String, dynamic>>.from(sorted)
          ..sort((a, b) {
            final ca = ((a['total_commission'] as num?) ?? 0).toDouble() +
                ((a['total_profit'] as num?) ?? 0).toDouble();
            final cb = ((b['total_commission'] as num?) ?? 0).toDouble() +
                ((b['total_profit'] as num?) ?? 0).toDouble();
            return cb.compareTo(ca);
          });
        final top6 = chartRows.take(6).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Commission vs profit (top 6)',
                style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: HexaColors.textPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _BrokerStackedCompare(top: top6, tt: tt),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium?.copyWith(color: HexaColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search brokers…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: HexaColors.surfaceElevated,
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: HexaColors.border)),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_modeLabels[i]),
                        selected: _sortColumnIndex == i,
                        onSelected: (_) => setState(() {
                          if (_sortColumnIndex == i) {
                            _asc = !_asc;
                          } else {
                            _sortColumnIndex = i;
                            _asc = i == 0;
                          }
                        }),
                        selectedColor:
                            HexaColors.primaryLight.withValues(alpha: 0.95),
                        checkmarkColor: HexaColors.primaryDeep,
                        labelStyle: tt.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} brokers',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _shareCsv(
                      title:
                          '${AppConfig.appName} Brokers ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Broker',
                        'Deals',
                        'Commission',
                        'Comm % of profit',
                        'Profit'
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['broker_name']?.toString() ?? '',
                        (r) => ((r['deals'] as num?) ?? 0).toString(),
                        (r) => ((r['total_commission'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) => ((r['commission_pct_of_profit'] as num?) ?? 0)
                            .toStringAsFixed(1),
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
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
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                              child: Text('No matches',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final comm =
                              ((r['total_commission'] as num?) ?? 0).toDouble();
                          final profit =
                              ((r['total_profit'] as num?) ?? 0).toDouble();
                          final cp =
                              ((r['commission_pct_of_profit'] as num?) ?? 0)
                                  .toDouble();
                          final warn = cp > 10;
                          final bid = r['broker_id']?.toString();
                          final name = r['broker_name']?.toString() ?? '—';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: HexaColors.surfaceCard,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: bid == null
                                    ? null
                                    : () => context.push('/broker/$bid'),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border:
                                        Border.all(color: HexaColors.border),
                                    boxShadow: HexaColors.cardShadow(context),
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.handshake_outlined,
                                              color: HexaColors.primaryMid,
                                              size: 22),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(name,
                                                style: tt.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    color: HexaColors
                                                        .textPrimary)),
                                          ),
                                          Text(
                                            widget.inr(profit),
                                            style: tt.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              color: profit >= 0
                                                  ? HexaColors.profit
                                                  : HexaColors.loss,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          height: 10,
                                          child: Builder(
                                            builder: (context) {
                                              final a = comm.abs();
                                              final b = profit.abs();
                                              final sum = a + b;
                                              final fa =
                                                  sum > 0 ? a / sum : 0.5;
                                              return Row(
                                                children: [
                                                  Expanded(
                                                    flex: math.max(
                                                        1, (fa * 1000).round()),
                                                    child: Container(
                                                        color: HexaColors
                                                            .chartOrange),
                                                  ),
                                                  Expanded(
                                                    flex: math.max(
                                                        1,
                                                        ((1 - fa) * 1000)
                                                            .round()),
                                                    child: Container(
                                                        color: HexaColors.profit
                                                            .withValues(
                                                                alpha: 0.85)),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text('${r['deals'] ?? '—'} deals',
                                              style: tt.labelSmall?.copyWith(
                                                  color: HexaColors
                                                      .textSecondary)),
                                          const Spacer(),
                                          Text(
                                            'Comm ${widget.inr(comm)}',
                                            style: tt.labelSmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: HexaColors.chartOrange),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '${cp.toStringAsFixed(1)}% of profit',
                                            style: tt.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: warn
                                                  ? HexaColors.accentAmber
                                                  : HexaColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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

class _BrokerStackedCompare extends StatelessWidget {
  const _BrokerStackedCompare({required this.top, required this.tt});

  final List<Map<String, dynamic>> top;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) {
      return const SizedBox.shrink();
    }
    var maxY = 1.0;
    for (final r in top) {
      final c = ((r['total_commission'] as num?) ?? 0).toDouble().abs();
      final p = ((r['total_profit'] as num?) ?? 0).toDouble().abs();
      maxY = math.max(maxY, math.max(c, p));
    }
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < top.length; i++) {
      final r = top[i];
      final c = ((r['total_commission'] as num?) ?? 0).toDouble();
      final p = ((r['total_profit'] as num?) ?? 0).toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 4,
          barRods: [
            BarChartRodData(
              toY: c.abs(),
              width: 10,
              color: HexaColors.chartOrange,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            BarChartRodData(
              toY: p.abs(),
              width: 10,
              color: HexaColors.profit,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HexaColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HexaColors.border),
        boxShadow: HexaColors.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: HexaColors.chartOrange, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Commission',
                  style:
                      tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
              const SizedBox(width: 14),
              Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: HexaColors.profit, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Profit',
                  style:
                      tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.1,
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) => FlLine(
                        color: HexaColors.border.withValues(alpha: 0.4))),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      reservedSize: 36,
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(
                        v >= 100000
                            ? '₹${(v / 1000).toStringAsFixed(0)}k'
                            : '₹${v.toStringAsFixed(0)}',
                        style: tt.labelSmall?.copyWith(
                            fontSize: 8, color: HexaColors.textSecondary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= top.length) {
                          return const SizedBox.shrink();
                        }
                        final raw = top[idx]['broker_name']?.toString() ?? '';
                        final t =
                            raw.length > 6 ? '${raw.substring(0, 6)}…' : raw;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(t,
                              style: tt.labelSmall?.copyWith(
                                  fontSize: 8,
                                  color: HexaColors.textSecondary)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: groups,
                alignment: BarChartAlignment.spaceAround,
                groupsSpace: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
