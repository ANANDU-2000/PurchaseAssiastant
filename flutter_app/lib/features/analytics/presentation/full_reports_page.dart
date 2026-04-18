import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

enum _ReportMode { overview, category, supplier, broker, item }

enum _DatePreset { today, d7, d30, month }

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

final _insightsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final range = ref.watch(analyticsDateRangeProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsInsights(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final _goalsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  final n = DateTime.now();
  final period =
      '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}';
  return ref.read(hexaApiProvider).getAnalyticsGoals(
        businessId: session.primaryBusiness.id,
        period: period,
      );
});

/// Full-screen reports (outside shell).
class FullReportsPage extends ConsumerStatefulWidget {
  const FullReportsPage({super.key});

  @override
  ConsumerState<FullReportsPage> createState() => _FullReportsPageState();
}

class _FullReportsPageState extends ConsumerState<FullReportsPage> {
  _ReportMode _mode = _ReportMode.overview;
  _DatePreset _preset = _DatePreset.month;
  bool _visual = true;
  String _tableQuery = '';

  void _applyPreset(_DatePreset p) {
    final n = DateTime.now();
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _DatePreset.today => (
          from: DateTime(n.year, n.month, n.day),
          to: DateTime(n.year, n.month, n.day),
        ),
      _DatePreset.d7 => (
          from: n.subtract(const Duration(days: 6)),
          to: DateTime(n.year, n.month, n.day),
        ),
      _DatePreset.d30 => (
          from: n.subtract(const Duration(days: 29)),
          to: DateTime(n.year, n.month, n.day),
        ),
      _DatePreset.month => (
          from: DateTime(n.year, n.month, 1),
          to: DateTime(n.year, n.month, n.day),
        ),
    };
    setState(() => _preset = p);
    _invalidateAnalytics();
  }

  void _invalidateAnalytics() {
    ref.invalidate(analyticsKpiProvider);
    ref.invalidate(analyticsItemsTableProvider);
    ref.invalidate(analyticsCategoriesTableProvider);
    ref.invalidate(analyticsSuppliersTableProvider);
    ref.invalidate(analyticsBrokersTableProvider);
    ref.invalidate(analyticsDailyProfitProvider);
    ref.invalidate(_insightsProvider);
    ref.invalidate(_goalsProvider);
  }

  List<Map<String, dynamic>> _rows(
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> cats,
    List<Map<String, dynamic>> sups,
    List<Map<String, dynamic>> bros,
  ) {
    switch (_mode) {
      case _ReportMode.overview:
      case _ReportMode.category:
        return cats;
      case _ReportMode.supplier:
        return sups;
      case _ReportMode.broker:
        return bros;
      case _ReportMode.item:
        return items;
    }
  }

  String _label(Map<String, dynamic> r) {
    switch (_mode) {
      case _ReportMode.category:
      case _ReportMode.overview:
        return r['category']?.toString() ?? '—';
      case _ReportMode.supplier:
        return r['supplier_name']?.toString() ?? '—';
      case _ReportMode.broker:
        return r['broker_name']?.toString() ?? '—';
      case _ReportMode.item:
        return r['item_name']?.toString() ?? '—';
    }
  }

  num _metric(Map<String, dynamic> r) {
    switch (_mode) {
      case _ReportMode.supplier:
      case _ReportMode.broker:
        return (r['total_profit'] as num?) ?? 0;
      default:
        return (r['total_profit'] as num?) ??
            (r['total_purchase'] as num?) ??
            0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kpi = ref.watch(analyticsKpiProvider);
    final items = ref.watch(analyticsItemsTableProvider);
    final cats = ref.watch(analyticsCategoriesTableProvider);
    final sups = ref.watch(analyticsSuppliersTableProvider);
    final bros = ref.watch(analyticsBrokersTableProvider);
    final trend = ref.watch(analyticsDailyProfitProvider);
    final insights = ref.watch(_insightsProvider);
    final goals = ref.watch(_goalsProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Reports'),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : RefreshIndicator(
              onRefresh: () async => _invalidateAnalytics(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                children: [
                  _filterBar(),
                  const SizedBox(height: 8),
                  kpi.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => FriendlyLoadError(
                      onRetry: () => ref.invalidate(analyticsKpiProvider),
                    ),
                    data: _kpiStrip,
                  ),
                  goals.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (g) => g == null
                        ? const SizedBox.shrink()
                        : kpi.maybeWhen(
                            data: (k) {
                              final pg = g['profit_goal'] as num?;
                              if (pg == null || pg <= 0) {
                                return const SizedBox.shrink();
                              }
                              final p = (k.totalProfit / pg.toDouble())
                                  .clamp(0.0, 1.0);
                              return Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Profit goal (this month)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 6),
                                        LinearProgressIndicator(value: p),
                                        Text(
                                            '${(p * 100).toStringAsFixed(0)}% of ${_inr(pg.round())}'),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Visual'),
                        selected: _visual,
                        onSelected: (v) => setState(() => _visual = v),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Table'),
                        selected: !_visual,
                        onSelected: (v) => setState(() => _visual = !v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  items.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const Text('Could not load'),
                    data: (iRows) => cats.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (cRows) => sups.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (sRows) => bros.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (bRows) {
                            var rows = _rows(iRows, cRows, sRows, bRows);
                            if (_tableQuery.isNotEmpty) {
                              final q = _tableQuery.toLowerCase();
                              rows = rows
                                  .where((r) =>
                                      _label(r).toLowerCase().contains(q))
                                  .toList();
                            }
                            rows = List<Map<String, dynamic>>.from(rows)
                              ..sort((a, b) =>
                                  _metric(b).compareTo(_metric(a)));
                            return _visual
                                ? _donut(rows)
                                : _table(rows);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  insights.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: _insightCards,
                  ),
                  const SizedBox(height: 12),
                  trend.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: _trend,
                  ),
                  const SizedBox(height: 12),
                  items.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: _compareMini,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _filterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final m in _ReportMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(m.name),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in _DatePreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(p.name),
                    selected: _preset == p,
                    onSelected: (_) => _applyPreset(p),
                  ),
                ),
            ],
          ),
        ),
        if (!_visual)
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (s) => setState(() => _tableQuery = s),
          ),
      ],
    );
  }

  Widget _kpiStrip(AnalyticsKpi k) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _pill('Spend', _inr(k.totalPurchase.round())),
          _pill('Profit', _inr(k.totalProfit.round())),
          _pill('Deals', '${k.purchaseCount}'),
          _pill(
            'Avg',
            k.purchaseCount > 0
                ? _inr((k.totalPurchase / k.purchaseCount).round())
                : '—',
          ),
        ],
      ),
    );
  }

  Widget _pill(String t, String v) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HexaColors.brandBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t,
                style:
                    const TextStyle(fontSize: 11, color: HexaColors.neutral)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _donut(List<Map<String, dynamic>> rows) {
    final usable =
        rows.where((r) => _metric(r).toDouble() > 0).take(6).toList();
    final total =
        usable.fold<double>(0, (s, r) => s + _metric(r).toDouble());
    if (usable.isEmpty || total <= 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No chart data'),
        ),
      );
    }
    final palette = HexaColors.chartPalette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(_mode.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 48,
                  sections: [
                    for (var i = 0; i < usable.length; i++)
                      PieChartSectionData(
                        value: _metric(usable[i]).toDouble(),
                        color: palette[i % palette.length],
                        radius: 44,
                        title:
                            '${((_metric(usable[i]).toDouble() / total) * 100).toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Text(_inr(total.round()),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Amount')),
          ],
          rows: [
            for (final r in rows.take(50))
              DataRow(
                cells: [
                  DataCell(Text(_label(r))),
                  DataCell(Text(_inr(_metric(r).round()))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _insightCards(Map<String, dynamic> m) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Insights',
                style: TextStyle(fontWeight: FontWeight.w800)),
            if (m['best_item'] != null)
              ListTile(
                dense: true,
                leading:
                    const Icon(Icons.trending_up_rounded, color: Colors.green),
                title: Text('Best: ${m['best_item']}'),
              ),
            if (m['cheapest_supplier'] != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.savings_outlined),
                title: Text('Lowest cost supplier: ${m['cheapest_supplier']}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trend(List<AnalyticsDailyProfitPoint> pts) {
    final spots = <FlSpot>[];
    for (var i = 0; i < pts.length; i++) {
      spots.add(FlSpot(i.toDouble(), pts[i].profit));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Profit trend',
                style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: HexaColors.brandPrimary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compareMini(List<Map<String, dynamic>> rows) {
    final top = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => ((b['total_profit'] as num?) ?? 0)
          .compareTo((a['total_profit'] as num?) ?? 0));
    final pick = top.take(4).toList();
    if (pick.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top items',
                style: TextStyle(fontWeight: FontWeight.w800)),
            for (final r in pick)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(r['item_name']?.toString() ?? '—')),
                    Text(_inr(((r['total_profit'] as num?) ?? 0).round())),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
