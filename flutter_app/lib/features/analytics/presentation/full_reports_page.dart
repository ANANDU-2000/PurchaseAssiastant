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
  /// Vertical rhythm for Reports list and cards.
  static const double _sectionGap = 24;
  static const double _filterGap = 12;
  static const double _cardPad = 18;
  static const double _buttonGap = 14;

  _ReportMode _mode = _ReportMode.overview;
  _DatePreset _preset = _DatePreset.month;
  bool _visual = true;
  String _tableQuery = '';
  bool _exporting = false;
  bool _exportingPdf = false;

  final _tableSearchCtrl = TextEditingController();
  final _tableFilterFocus = FocusNode();

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    _tableFilterFocus.dispose();
    super.dispose();
  }

  void _focusReportsTableSearch() {
    setState(() => _visual = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tableFilterFocus.requestFocus();
      }
    });
  }

  void _refreshReportsData() {
    ref.invalidate(tradePurchasesListProvider);
    invalidateBusinessAggregates(ref);
  }

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

    final onSurface = Theme.of(context).colorScheme.onSurface;

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
        titleSpacing: 16,
        title: Text(
          'Reports',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: onSurface,
          ),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actionsIconTheme: IconThemeData(
          size: 23,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: HexaColors.brandBorder.withValues(alpha: 0.65),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search table',
            onPressed: _focusReportsTableSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            padding: EdgeInsets.zero,
            offset: const Offset(0, kToolbarHeight - 12),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'pdf',
                enabled: !_exporting && !_exportingPdf,
                child: ListTile(
                  leading: _exportingPdf
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Export summary PDF'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                enabled: !_exporting && !_exportingPdf,
                child: ListTile(
                  leading: _exporting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                  title: const Text('Export table as CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('Refresh data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'global_search',
                child: ListTile(
                  leading: Icon(Icons.travel_explore_outlined),
                  title: Text('Global search'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'catalog',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Catalog'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'contacts',
                child: ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Contacts'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'notifications',
                child: ListTile(
                  leading: Icon(Icons.notifications_outlined),
                  title: Text('Alerts'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (v) {
              switch (v) {
                case 'pdf':
                  _exportReportsPdf();
                case 'csv':
                  _exportTableCsv();
                case 'refresh':
                  _refreshReportsData();
                case 'global_search':
                  context.push('/search');
                case 'catalog':
                  context.push('/catalog');
                case 'contacts':
                  context.push('/contacts');
                case 'notifications':
                  context.push('/notifications');
                case 'settings':
                  context.go('/settings');
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : RefreshIndicator(
              onRefresh: () async {
                _refreshReportsData();
              },
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16)
                    .copyWith(bottom: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  _filterBar(),
                  const SizedBox(height: _sectionGap),
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
                  const SizedBox(height: _sectionGap),
                  ref.watch(reportsPriorPeriodDeltaProvider).when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (d) => _priorPeriodVersusCard(context, d),
                  ),
                  const SizedBox(height: _sectionGap),
                  items.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: _lowMarginWatchlist,
                  ),
                  const SizedBox(height: _sectionGap),
                  items.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (iRows) => sups.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (sRows) => _topMoversCards(context, iRows, sRows),
                    ),
                  ),
                  const SizedBox(height: _sectionGap),
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
                              final tt = Theme.of(context).textTheme;
                              final cs = Theme.of(context).colorScheme;
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: Padding(
                                  padding: const EdgeInsets.all(_cardPad),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Profit goal (this month)',
                                        style: tt.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          height: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: _filterGap),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: p,
                                          minHeight: 8,
                                          backgroundColor:
                                              cs.surfaceContainerHighest.withValues(alpha: 0.6),
                                        ),
                                      ),
                                      const SizedBox(height: _filterGap),
                                      Text(
                                        '${(p * 100).toStringAsFixed(0)}% of ${_inr(pg.round())}',
                                        style: tt.bodyMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          ),
                  ),
                  const SizedBox(height: _sectionGap),
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
                  const SizedBox(height: _sectionGap),
                  insights.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: _insightCards,
                  ),
                  const SizedBox(height: _sectionGap),
                  trend.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: _trend,
                  ),
                  ],
                ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(_cardPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top suppliers',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'By profit in this period',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: _filterGap),
                  if (topS.isEmpty)
                    Text('—', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                  else
                    for (final r in topS)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _filterGap),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                r['supplier_name']?.toString() ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            Text(
                              _inr(_metric(r).round()),
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: _filterGap),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(_cardPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top items',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'By profit in this period',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: _filterGap),
                  if (topI.isEmpty)
                    Text('—', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                  else
                    for (final r in topI)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _filterGap),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                r['item_name']?.toString() ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            Text(
                              _inr(_metric(r).round()),
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
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
    );
  }

  static const TextStyle _filterChipLabelStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  /// Calmer than body text so chips stay the focal control.
  TextStyle _filterSectionLabelStyle(ColorScheme cs, TextTheme tt) {
    return tt.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.2,
          height: 1.2,
        ) ??
        TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: cs.onSurfaceVariant,
          height: 1.2,
        );
  }

  Widget _compactFilterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label, style: _filterChipLabelStyle),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant,
      ),
      selectedColor: cs.primaryContainer.withValues(alpha: 0.55),
    );
  }

  Widget _filterBar() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final groupStyle = _filterSectionLabelStyle(cs, tt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('View', style: groupStyle),
        const SizedBox(height: _filterGap),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              for (final m in _ReportMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: _filterGap),
                  child: _compactFilterChip(
                    label: _modeUiLabel(m),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: _filterGap),
        Text('Period', style: groupStyle),
        const SizedBox(height: _filterGap),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              for (final p in _DatePreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: _filterGap),
                  child: _compactFilterChip(
                    label: _presetUiLabel(p),
                    selected: _preset == p,
                    onSelected: (_) => _applyPreset(p),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: _filterGap),
        Text('Mode', style: groupStyle),
        const SizedBox(height: _filterGap),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _compactFilterChip(
                label: 'Charts',
                selected: _visual,
                onSelected: (_) => setState(() => _visual = true),
              ),
              const SizedBox(width: _filterGap),
              _compactFilterChip(
                label: 'Table',
                selected: !_visual,
                onSelected: (_) => setState(() => _visual = false),
              ),
            ],
          ),
        ),
        if (!_visual) ...[
          const SizedBox(height: _filterGap),
          TextField(
            controller: _tableSearchCtrl,
            focusNode: _tableFilterFocus,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            decoration: InputDecoration(
              hintText: 'Filter table…',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    final tt = Theme.of(context).textTheme;
    return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(_cardPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 22, color: cs.tertiary),
                  const SizedBox(width: _filterGap),
                  Expanded(
                    child: Text(
                      'Low margin watchlist',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _filterGap),
              Text(
                'Items in this period with markup under 8% vs line cost (or negative). '
                'Review sell vs landing on these lines.',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: _filterGap),
              for (final r in pick)
                Padding(
                  padding: const EdgeInsets.only(bottom: _filterGap),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['item_name']?.toString() ?? '—',
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            if ((r['category_name']?.toString() ?? '').trim().isNotEmpty)
                              Text(
                                r['category_name'].toString(),
                                style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: _filterGap),
                      Text(
                        '${(r['margin_pct'] as num?)?.toStringAsFixed(1) ?? '—'}%',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ((r['margin_pct'] as num?)?.toDouble() ?? 0) < 0
                              ? HexaColors.loss
                              : cs.onSurface,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    );
  }

  Widget _noPurchasesInRangeCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: _sectionGap),
      child: Material(
        color: cs.surface,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nothing to report yet',
                style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      height: 1.25,
                      letterSpacing: -0.2,
                      color: HexaColors.brandPrimary,
                    ) ??
                    const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      letterSpacing: -0.2,
                      color: HexaColors.brandPrimary,
                    ),
              ),
              const SizedBox(height: _filterGap),
              Text(
                'This date range has no purchases. Insights, charts, and trends '
                'appear after you record buys.',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: _sectionGap),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go('/purchase/new'),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('New purchase'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      elevation: 3,
                      shadowColor: Colors.black.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: _buttonGap),
                  OutlinedButton(
                    onPressed: () => context.go('/purchase'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      foregroundColor: cs.onSurfaceVariant,
                      side: BorderSide(
                        color: HexaColors.brandBorder.withValues(alpha: 0.75),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Open purchase list',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
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
  }

  Widget _noChartRowsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
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
            const SizedBox(height: _filterGap),
            Text(
              'Try another period, switch to Table view, or add purchases so '
              '${_modeUiLabel(_mode).toLowerCase()} totals are non-zero.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: _buttonGap),
            FilledButton(
              onPressed: () => context.go('/purchase/new'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(_cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vs previous period (same length)',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: _filterGap),
            Text(
              'Compared to ${df.format(d.priorFrom)} – ${df.format(d.priorTo)}',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: _filterGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profit',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        profitLabel,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: profitColor,
                          height: 1.2,
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
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        spendLabel,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: spendColor,
                          height: 1.2,
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
      clipBehavior: Clip.none,
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: _filterGap),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HexaColors.brandBorder.withValues(alpha: 0.85)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              v,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
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
      final tt = Theme.of(context).textTheme;
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(_cardPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _modeUiLabel(_mode),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: _filterGap),
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
                    const SizedBox(width: _filterGap),
                    Expanded(
                      child: Text(
                        _label(usable[i]),
                        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _inr(_metric(usable[i]).round()),
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: _filterGap),
                    Text(
                      '${((_metric(usable[i]).toDouble() / total) * 100).toStringAsFixed(0)}%',
                      style: tt.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: _filterGap),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _metric(usable[i]).toDouble() / total,
                    minHeight: 8,
                    backgroundColor: palette[i % palette.length].withAlpha(40),
                    valueColor: AlwaysStoppedAnimation(palette[i % palette.length]),
                  ),
                ),
                const SizedBox(height: _filterGap),
              ],
              if (usable.length == 1)
                Text(
                  'Only one row has data in this period. Pick a longer range to compare more.',
                  style: tt.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final palette = HexaColors.chartPalette;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(_cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _modeUiLabel(_mode),
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: _filterGap),
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
            const SizedBox(height: _filterGap),
            Text(
              _inr(total.round()),
              textAlign: TextAlign.center,
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            cs.surfaceContainerHighest.withValues(alpha: 0.45),
          ),
          headingTextStyle: tt.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
            letterSpacing: 0.2,
          ),
          dataTextStyle: tt.bodyMedium,
          columnSpacing: 28,
          horizontalMargin: _cardPad,
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

  Widget _insightRow({
    required IconData icon,
    required String text,
    Color? iconColor,
  }) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: iconColor ?? cs.primary),
        const SizedBox(width: _filterGap),
        Expanded(
          child: Text(
            text,
            style: tt.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _insightCards(Map<String, dynamic> m) {
    final hasBest = m['best_item'] != null;
    final hasCheap = m['cheapest_supplier'] != null;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(_cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Insights',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (!hasBest && !hasCheap)
              Padding(
                padding: const EdgeInsets.only(top: _filterGap),
                child: Text(
                  'No insight highlights for this range yet. Try a longer period or add more purchase lines with sell prices.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            if (hasBest) ...[
              const SizedBox(height: _filterGap),
              _insightRow(
                icon: Icons.trending_up_rounded,
                iconColor: const Color(0xFF15803D),
                text: 'Best: ${m['best_item']}',
              ),
            ],
            if (hasCheap) ...[
              const SizedBox(height: _filterGap),
              _insightRow(
                icon: Icons.savings_outlined,
                text: 'Lowest cost supplier: ${m['cheapest_supplier']}',
              ),
            ],
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(_cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    'Profit trend',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  'Total: ${_inr(totalProfit.round())}',
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: _filterGap),
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
                      color: cs.outlineVariant.withValues(alpha: 0.45),
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
                          style: tt.labelSmall?.copyWith(
                            fontSize: 9,
                            color: cs.onSurfaceVariant,
                          ),
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
