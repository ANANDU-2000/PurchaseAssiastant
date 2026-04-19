import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/full_reports_insights_providers.dart';
import '../../../core/providers/reports_prior_period_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';

enum _ReportMode { overview, category, supplier, broker, item }

enum _DatePreset { today, d7, d30, month }

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

String _modeUiLabel(_ReportMode m) => switch (m) {
      _ReportMode.overview => 'Overview',
      _ReportMode.category => 'Categories',
      _ReportMode.supplier => 'Suppliers',
      _ReportMode.broker => 'Brokers',
      _ReportMode.item => 'Items',
    };

String _presetUiLabel(_DatePreset p) => switch (p) {
      _DatePreset.today => 'Today',
      _DatePreset.d7 => '7 days',
      _DatePreset.d30 => '30 days',
      _DatePreset.month => 'This month',
    };

/// Full-screen reports (also used as shell Reports tab at `/reports`).
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
  bool _exporting = false;
  bool _exportingPdf = false;

  static String _csvCell(String raw) {
    final s = raw.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
    if (s.contains(',') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  Future<void> _exportTableCsv() async {
    if (_exporting || _exportingPdf) return;
    setState(() => _exporting = true);
    try {
      final items = await ref.read(analyticsItemsTableProvider.future);
      final cats = await ref.read(analyticsCategoriesTableProvider.future);
      final sups = await ref.read(analyticsSuppliersTableProvider.future);
      final bros = await ref.read(analyticsBrokersTableProvider.future);
      var rows = _rows(items, cats, sups, bros);
      if (_tableQuery.trim().isNotEmpty) {
        final q = _tableQuery.toLowerCase();
        rows = rows.where((r) => _label(r).toLowerCase().contains(q)).toList();
      }
      rows = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) => _metric(b).compareTo(_metric(a)));
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing to export for this view.')),
          );
        }
        return;
      }
      final range = ref.read(analyticsDateRangeProvider);
      final df = DateFormat('yyyy-MM-dd');
      final buf = StringBuffer();
      buf.writeln(
        '# Purchase Assistant — ${_modeUiLabel(_mode)} — ${df.format(range.from)} to ${df.format(range.to)}',
      );
      buf.writeln('name,total_purchase_inr,total_profit_inr');
      for (final r in rows) {
        final name = _label(r);
        final buy = (r['total_purchase'] as num?)?.toDouble() ?? 0;
        final prof = (r['total_profit'] as num?)?.toDouble() ?? 0;
        buf.writeln(
          '${_csvCell(name)},${buy.toStringAsFixed(2)},${prof.toStringAsFixed(2)}',
        );
      }
      await Share.share(
        buf.toString(),
        subject:
            'Reports ${_modeUiLabel(_mode)} ${df.format(range.from)}–${df.format(range.to)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportReportsPdf() async {
    if (_exportingPdf || _exporting) return;
    setState(() => _exportingPdf = true);
    try {
      final kpi = await ref.read(analyticsKpiProvider.future);
      final items = await ref.read(analyticsItemsTableProvider.future);
      final cats = await ref.read(analyticsCategoriesTableProvider.future);
      final sups = await ref.read(analyticsSuppliersTableProvider.future);
      final bros = await ref.read(analyticsBrokersTableProvider.future);
      var rows = _rows(items, cats, sups, bros);
      if (_tableQuery.trim().isNotEmpty) {
        final q = _tableQuery.toLowerCase();
        rows = rows.where((r) => _label(r).toLowerCase().contains(q)).toList();
      }
      rows = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) => _metric(b).compareTo(_metric(a)));
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing to export for this view.')),
          );
        }
        return;
      }
      final range = ref.read(analyticsDateRangeProvider);
      final biz = ref.read(invoiceBusinessProfileProvider);
      String? priorNote;
      try {
        final d = await ref.read(reportsPriorPeriodDeltaProvider.future);
        priorNote = _priorPeriodStringForPdf(d);
      } catch (_) {}
      await shareReportsSummaryPdf(
        business: biz,
        from: range.from,
        to: range.to,
        modeLabel: _modeUiLabel(_mode),
        totalPurchase: kpi.totalPurchase,
        totalProfit: kpi.totalProfit,
        purchaseCount: kpi.purchaseCount,
        tableRows: rows,
        rowLabel: _label,
        rowMetricPurchase: (r) => (r['total_purchase'] as num?) ?? 0,
        rowMetricProfit: (r) => (r['total_profit'] as num?) ?? 0,
        priorPeriodNote: priorNote,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

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
    invalidateAnalyticsData(ref);
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
    final insights = ref.watch(fullReportsInsightsProvider);
    final goals = ref.watch(fullReportsGoalsProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: GoRouter.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text('Reports'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'Export summary PDF',
            onPressed: (_exporting || _exportingPdf) ? null : _exportReportsPdf,
            icon: _exportingPdf
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
          IconButton(
            tooltip: 'Export table as CSV',
            onPressed: (_exporting || _exportingPdf) ? null : _exportTableCsv,
            icon: _exporting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
          ShellQuickRefActions(
            onRefresh: () {
              ref.invalidate(tradePurchasesListProvider);
              invalidateBusinessAggregates(ref);
            },
          ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(tradePurchasesListProvider);
                invalidateBusinessAggregates(ref);
              },
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                children: [
                  _filterBar(),
                  const SizedBox(height: 8),
                  kpi.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => FriendlyLoadError(
                      onRetry: () => ref.invalidate(analyticsKpiProvider),
                    ),
                    data: (k) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (k.purchaseCount == 0) _noPurchasesInRangeCard(context),
                        _kpiStrip(k),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ref.watch(reportsPriorPeriodDeltaProvider).when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (d) => _priorPeriodVersusCard(context, d),
                  ),
                  items.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: _lowMarginWatchlist,
                  ),
                  items.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (iRows) => sups.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (sRows) => _topMoversCards(context, iRows, sRows),
                    ),
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
                ],
              ),
            ),
    );
  }

  /// Compact “who / what moved money” — same window as the main table, no extra API.
  Widget _topMoversCards(
    BuildContext context,
    List<Map<String, dynamic>> itemRows,
    List<Map<String, dynamic>> supRows,
  ) {
    final sList = List<Map<String, dynamic>>.from(supRows)
      ..sort((a, b) => _metric(b).compareTo(_metric(a)));
    final iList = List<Map<String, dynamic>>.from(itemRows)
      ..sort((a, b) => _metric(b).compareTo(_metric(a)));
    final topS = sList.where((r) => _metric(r) > 0).take(5).toList();
    final topI = iList.where((r) => _metric(r) > 0).take(5).toList();
    if (topS.isEmpty && topI.isEmpty) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top suppliers',
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'By profit in this period',
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    if (topS.isEmpty)
                      Text('—', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                    else
                      for (final r in topS)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r['supplier_name']?.toString() ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                _inr(_metric(r).round()),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top items',
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'By profit in this period',
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    if (topI.isEmpty)
                      Text('—', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                    else
                      for (final r in topI)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r['item_name']?.toString() ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                _inr(_metric(r).round()),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('View', style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final m in _ReportMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(_modeUiLabel(m)),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('Period', style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in _DatePreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(_presetUiLabel(p)),
                    selected: _preset == p,
                    onSelected: (_) => _applyPreset(p),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilterChip(
              label: const Text('Charts'),
              selected: _visual,
              onSelected: (_) => setState(() => _visual = true),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Table'),
              selected: !_visual,
              onSelected: (_) => setState(() => _visual = false),
            ),
          ],
        ),
        if (!_visual) ...[
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Filter table…',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (s) => setState(() => _tableQuery = s),
          ),
        ],
      ],
    );
  }

  /// Surfaces item lines with weak markup (same [margin_pct] as analytics API).
  Widget _lowMarginWatchlist(List<Map<String, dynamic>> itemRows) {
    final scored = <Map<String, dynamic>>[];
    for (final r in itemRows) {
      final m = (r['margin_pct'] as num?)?.toDouble();
      if (m == null || !m.isFinite) continue;
      final profit = (r['total_profit'] as num?)?.toDouble() ?? 0;
      final lines = (r['line_count'] as num?)?.toInt() ?? 0;
      if (lines < 1) continue;
      if (profit < 0 || m < 8) {
        scored.add(r);
      }
    }
    scored.sort((a, b) {
      final ma = (a['margin_pct'] as num?)?.toDouble() ?? 0;
      final mb = (b['margin_pct'] as num?)?.toDouble() ?? 0;
      return ma.compareTo(mb);
    });
    final pick = scored.take(6).toList();
    if (pick.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: cs.tertiary),
                  const SizedBox(width: 8),
                  const Text(
                    'Low margin watchlist',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Items in this period with markup under 8% vs line cost (or negative). '
                'Review sell vs landing on these lines.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              for (final r in pick)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['item_name']?.toString() ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            if ((r['category_name']?.toString() ?? '').trim().isNotEmpty)
                              Text(
                                r['category_name'].toString(),
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${(r['margin_pct'] as num?)?.toStringAsFixed(1) ?? '—'}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: ((r['margin_pct'] as num?)?.toDouble() ?? 0) < 0
                              ? HexaColors.loss
                              : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noPurchasesInRangeCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nothing to report yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: HexaColors.brandPrimary,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'This date range has no purchases. Insights, charts, and trends '
              'appear after you record buys.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/purchase/new'),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New purchase'),
                ),
                OutlinedButton(
                  onPressed: () => context.go('/purchase'),
                  child: const Text('Open purchase list'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _noChartRowsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No breakdown to chart',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another period, switch to Table view, or add purchases so '
              '${_modeUiLabel(_mode).toLowerCase()} totals are non-zero.',
              style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => context.go('/purchase/new'),
              child: const Text('Record a purchase'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDeltaPct(double? pct) {
    if (pct == null) return 'No prior baseline';
    if (pct.abs() > 999) return pct > 0 ? 'Up sharply vs prior' : 'Down sharply vs prior';
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(1)}%';
  }

  String _priorPeriodStringForPdf(ReportsPriorPeriodDelta d) {
    final df = DateFormat('dd MMM yyyy');
    final profit = _formatDeltaPct(d.profitPctVsPrior());
    final spend = _formatDeltaPct(d.purchasePctVsPrior());
    return 'Compared to ${df.format(d.priorFrom)} – ${df.format(d.priorTo)}. Profit $profit; spend $spend.';
  }

  Widget _priorPeriodVersusCard(BuildContext context, ReportsPriorPeriodDelta d) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('dd MMM yyyy');
    final profit = d.profitPctVsPrior();
    final spend = d.purchasePctVsPrior();
    final profitLabel = _formatDeltaPct(profit);
    final spendLabel = _formatDeltaPct(spend);
    final profitColor = profit == null
        ? cs.onSurfaceVariant
        : (profit >= 0 ? const Color(0xFF15803D) : const Color(0xFFDC2626));
    final spendColor = spend == null
        ? cs.onSurfaceVariant
        : (spend <= 0 ? const Color(0xFF15803D) : const Color(0xFFDC2626));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vs previous period (same length)',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Compared to ${df.format(d.priorFrom)} – ${df.format(d.priorTo)}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profit',
                        style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        profitLabel,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: profitColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spend',
                        style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        spendLabel,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: spendColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
      return _noChartRowsCard(context);
    }
    // < 3 slices: ring chart looks degenerate — show a readable bar comparison instead.
    if (usable.length < 3) {
      final palette = HexaColors.chartPalette;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _modeUiLabel(_mode),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < usable.length; i++) ...[
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette[i % palette.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_label(usable[i]), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(_inr(_metric(usable[i]).round()), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Text(
                      '${((_metric(usable[i]).toDouble() / total) * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _metric(usable[i]).toDouble() / total,
                    minHeight: 8,
                    backgroundColor: palette[i % palette.length].withAlpha(40),
                    valueColor: AlwaysStoppedAnimation(palette[i % palette.length]),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (usable.length == 1)
                Text(
                  'Only one row has data in this period. Pick a longer range to compare more.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      );
    }
    final palette = HexaColors.chartPalette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(_modeUiLabel(_mode),
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
    final hasBest = m['best_item'] != null;
    final hasCheap = m['cheapest_supplier'] != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Insights',
                style: TextStyle(fontWeight: FontWeight.w800)),
            if (!hasBest && !hasCheap)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No insight highlights for this range yet. Try a longer period or add more purchase lines with sell prices.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (hasBest)
              ListTile(
                dense: true,
                leading:
                    const Icon(Icons.trending_up_rounded, color: Colors.green),
                title: Text('Best: ${m['best_item']}'),
              ),
            if (hasCheap)
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
    if (pts.isEmpty) return const SizedBox.shrink();
    final spots = <FlSpot>[];
    for (var i = 0; i < pts.length; i++) {
      spots.add(FlSpot(i.toDouble(), pts[i].profit));
    }
    final profits = pts.map((p) => p.profit).toList();
    final maxY = profits.reduce((a, b) => a > b ? a : b);
    final minY = profits.reduce((a, b) => a < b ? a : b);
    final hasRange = (maxY - minY).abs() > 1;
    final totalProfit = profits.fold(0.0, (a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Profit trend',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text(
                  'Total: ${_inr(totalProfit.round())}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minY: hasRange ? minY * 0.9 : null,
                  maxY: hasRange ? maxY * 1.1 : null,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: hasRange ? (maxY - minY) / 3 : null,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: Colors.grey.withAlpha(40),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        getTitlesWidget: (v, _) => Text(
                          _inr(v.round()),
                          style: const TextStyle(fontSize: 8.5),
                        ),
                        interval: hasRange ? (maxY - minY) / 3 : null,
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: HexaColors.brandPrimary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: HexaColors.brandPrimary.withAlpha(28),
                      ),
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

}
