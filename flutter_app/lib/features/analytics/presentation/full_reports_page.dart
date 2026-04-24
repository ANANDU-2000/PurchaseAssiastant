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
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';

enum _DatePreset { today, d7, d30, month }

enum _ViewType { item, supplier, category }

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

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
  _DatePreset _preset = _DatePreset.month;
  _ViewType _viewType = _ViewType.item;
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
      var rows = await ref.read(analyticsItemsTableProvider.future);
      if (_tableQuery.trim().isNotEmpty) {
        final q = _tableQuery.toLowerCase();
        rows = rows
            .where((r) => _itemLabel(r).toLowerCase().contains(q))
            .toList();
      }
      rows = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) => _itemMetric(b).compareTo(_itemMetric(a)));
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
        '# Purchase Assistant — Items — ${df.format(range.from)} to ${df.format(range.to)}',
      );
      buf.writeln('name,total_purchase_inr,total_profit_inr');
      for (final r in rows) {
        final name = _itemLabel(r);
        final buy = (r['total_purchase'] as num?)?.toDouble() ?? 0;
        final prof = (r['total_profit'] as num?)?.toDouble() ?? 0;
        buf.writeln(
          '${_csvCell(name)},${buy.toStringAsFixed(2)},${prof.toStringAsFixed(2)}',
        );
      }
      await Share.share(
        buf.toString(),
        subject: 'Reports Items ${df.format(range.from)}–${df.format(range.to)}',
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
      var itemRows = await ref.read(analyticsItemsTableProvider.future);
      itemRows = List<Map<String, dynamic>>.from(itemRows)
        ..sort((a, b) => _itemMetric(b).compareTo(_itemMetric(a)));
      final catRows =
          await ref.read(analyticsCategoriesTableProvider.future);
      final supRows =
          await ref.read(analyticsSuppliersTableProvider.future);
      if (itemRows.isEmpty && catRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Nothing to export for this view.')),
          );
        }
        return;
      }
      final range = ref.read(analyticsDateRangeProvider);
      final biz = ref.read(invoiceBusinessProfileProvider);
      await shareReportsSummaryPdf(
        business: biz,
        from: range.from,
        to: range.to,
        modeLabel: _viewTypeLabel(_viewType),
        totalPurchase: kpi.totalPurchase,
        totalProfit: kpi.totalProfit,
        purchaseCount: kpi.purchaseCount,
        tableRows: itemRows,
        rowLabel: _itemLabel,
        rowMetricPurchase: (r) => (r['total_purchase'] as num?) ?? 0,
        rowMetricProfit: (r) => (r['total_profit'] as num?) ?? 0,
        categoryRows: catRows,
        supplierRows: supRows,
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

  String _itemLabel(Map<String, dynamic> r) =>
      r['item_name']?.toString() ?? '—';

  num _itemMetric(Map<String, dynamic> r) =>
      (r['total_profit'] as num?) ??
      (r['total_purchase'] as num?) ??
      0;

  @override
  Widget build(BuildContext context) {
    final kpi = ref.watch(analyticsKpiProvider);
    final items = ref.watch(analyticsItemsTableProvider);
    final suppliers = ref.watch(analyticsSuppliersTableProvider);
    final categories = ref.watch(analyticsCategoriesTableProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: GoRouter.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text('Reports'),
        backgroundColor: HexaColors.brandBackground,
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
              invalidateTradePurchaseCaches(ref);
              invalidateBusinessAggregates(ref);
            },
          ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : RefreshIndicator(
              onRefresh: () async {
                invalidateTradePurchaseCaches(ref);
                invalidateBusinessAggregates(ref);
                await ref.read(analyticsKpiProvider.future);
              },
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
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
                        if (k.purchaseCount == 0)
                          _noPurchasesInRangeCard(context),
                        _kpiStrip(k),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── VIEW TABLE ─────────────────────────────────────────
                  if (_viewType == _ViewType.item)
                    items.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => FriendlyLoadError(
                        onRetry: () =>
                            ref.invalidate(analyticsItemsTableProvider),
                      ),
                      data: (iRows) {
                        var rows = List<Map<String, dynamic>>.from(iRows);
                        if (_tableQuery.isNotEmpty) {
                          final q = _tableQuery.toLowerCase();
                          rows = rows
                              .where((r) =>
                                  _itemLabel(r).toLowerCase().contains(q))
                              .toList();
                        }
                        rows.sort((a, b) =>
                            _itemMetric(b).compareTo(_itemMetric(a)));
                        return _itemsTable(context, rows);
                      },
                    )
                  else if (_viewType == _ViewType.supplier)
                    suppliers.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => FriendlyLoadError(
                        onRetry: () =>
                            ref.invalidate(analyticsSuppliersTableProvider),
                      ),
                      data: (sRows) {
                        var rows = List<Map<String, dynamic>>.from(sRows);
                        if (_tableQuery.isNotEmpty) {
                          final q = _tableQuery.toLowerCase();
                          rows = rows
                              .where((r) => (r['supplier_name']
                                      ?.toString() ??
                                  '')
                                  .toLowerCase()
                                  .contains(q))
                              .toList();
                        }
                        rows.sort((a, b) =>
                            ((b['total_purchase'] as num?) ?? 0)
                                .compareTo(
                                    (a['total_purchase'] as num?) ?? 0));
                        return _supplierTable(context, rows);
                      },
                    )
                  else
                    categories.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => FriendlyLoadError(
                        onRetry: () =>
                            ref.invalidate(analyticsCategoriesTableProvider),
                      ),
                      data: (cRows) {
                        var rows = List<Map<String, dynamic>>.from(cRows);
                        if (_tableQuery.isNotEmpty) {
                          final q = _tableQuery.toLowerCase();
                          rows = rows
                              .where((r) =>
                                  (r['category_name']?.toString() ?? '')
                                      .toLowerCase()
                                      .contains(q))
                              .toList();
                        }
                        rows.sort((a, b) =>
                            ((b['total_purchase'] as num?) ?? 0)
                                .compareTo(
                                    (a['total_purchase'] as num?) ?? 0));
                        return _categoryTable(context, rows);
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _itemsTable(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _noItemsRowsCard(context);
    return _reportTable(
      context,
      header: const ['Item', 'Qty', 'Unit', 'Total ₹'],
      flexes: const [3, 1, 1, 2],
      rows: rows.map((r) {
        final name = r['item_name']?.toString() ?? '—';
        final qty = (r['total_qty'] as num?)?.toDouble() ?? 0;
        final unit = r['unit']?.toString() ?? '';
        final total = (r['total_purchase'] as num?)?.toDouble() ?? 0;
        final qtyStr = qty == qty.roundToDouble()
            ? qty.toInt().toString()
            : qty.toStringAsFixed(1);
        return [name, qtyStr, unit, _inr(total.round())];
      }).toList(),
    );
  }

  Widget _supplierTable(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _noItemsRowsCard(context);
    return _reportTable(
      context,
      header: const ['Supplier', 'Deals', 'Total ₹'],
      flexes: const [3, 1, 2],
      rows: rows.map((r) {
        final name = r['supplier_name']?.toString() ?? '—';
        final deals = (r['purchase_count'] as num?)?.toInt() ?? 0;
        final total = (r['total_purchase'] as num?)?.toDouble() ?? 0;
        return [name, '$deals', _inr(total.round())];
      }).toList(),
    );
  }

  Widget _categoryTable(
      BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _noItemsRowsCard(context);
    return _reportTable(
      context,
      header: const ['Category', 'Items', 'Total ₹'],
      flexes: const [3, 1, 2],
      rows: rows.map((r) {
        final name = r['category_name']?.toString() ?? '—';
        final items = (r['item_count'] as num?)?.toInt() ??
            (r['line_count'] as num?)?.toInt() ??
            0;
        final total = (r['total_purchase'] as num?)?.toDouble() ?? 0;
        return [name, '$items', _inr(total.round())];
      }).toList(),
    );
  }

  Widget _reportTable(
    BuildContext context, {
    required List<String> header,
    required List<int> flexes,
    required List<List<String>> rows,
  }) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget cell(String v,
            {bool bold = false,
            bool rightAlign = false,
            Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Text(
            v,
            textAlign: rightAlign ? TextAlign.end : TextAlign.start,
            style: tt.bodySmall?.copyWith(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                color: color),
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < header.length; i++)
                  Expanded(
                    flex: flexes[i],
                    child: cell(header[i],
                        bold: true,
                        rightAlign: i == header.length - 1),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Rows
          for (var ri = 0; ri < rows.length; ri++) ...[
            Container(
              color: ri.isOdd
                  ? cs.surfaceContainerLowest.withValues(alpha: 0.4)
                  : null,
              child: Row(
                children: [
                  for (var i = 0; i < rows[ri].length; i++)
                    Expanded(
                      flex: flexes[i],
                      child: cell(
                        rows[ri][i],
                        rightAlign: i == rows[ri].length - 1,
                        bold: i == rows[ri].length - 1,
                        color: i == rows[ri].length - 1
                            ? HexaColors.brandPrimary
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (ri < rows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _filterBar() {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Period',
            style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final p in _DatePreset.values)
              FilterChip(
                label: Text(_presetUiLabel(p)),
                selected: _preset == p,
                onSelected: (_) => _applyPreset(p),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('View',
            style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final v in _ViewType.values)
              FilterChip(
                label: Text(_viewTypeLabel(v)),
                selected: _viewType == v,
                onSelected: (_) => setState(() {
                  _viewType = v;
                  _tableQuery = '';
                }),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: 'Filter ${_viewTypeLabel(_viewType)}…',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
          ),
          key: ValueKey(_viewType),
          onChanged: (s) => setState(() => _tableQuery = s),
        ),
      ],
    );
  }

  String _viewTypeLabel(_ViewType v) => switch (v) {
        _ViewType.item => 'Item',
        _ViewType.supplier => 'Supplier',
        _ViewType.category => 'Category',
      };


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

  Widget _noItemsRowsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No items in this period',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another date range, clear the filter, or add purchases with item lines.',
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

  Widget _kpiStrip(AnalyticsKpi k) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _pill('Spend', _inr(k.totalPurchase.round())),
        _pill('Deals', '${k.purchaseCount}'),
        _pill(
          'Avg',
          k.purchaseCount > 0
              ? _inr((k.totalPurchase / k.purchaseCount).round())
              : '—',
        ),
      ],
    );
  }

  Widget _pill(String t, String v) {
    return Container(
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
    );
  }


}
