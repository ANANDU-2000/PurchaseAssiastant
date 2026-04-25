import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/analytics_breakdown_providers.dart'
    show fullReportsTradeBundleProvider;
import '../../../core/providers/analytics_kpi_provider.dart'
    show AnalyticsKpi, analyticsDateRangeProvider;
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateAnalyticsData, invalidatePurchaseWorkspace;
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';

/// Aligns with [HomePeriod] on the dashboard: Today / Week / Month / Year.
enum _DatePreset { today, week, month, year }

enum _ViewType { item, supplier, category }

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

String _presetUiLabel(_DatePreset p) => switch (p) {
      _DatePreset.today => 'Today',
      _DatePreset.week => 'Week',
      _DatePreset.month => 'Month',
      _DatePreset.year => 'Year',
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
  /// Primary table shows this many rows; "View more" increases the cap.
  int _tableRowCap = 8;
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
      final range = ref.read(analyticsDateRangeProvider);
      final df = DateFormat('yyyy-MM-dd');
      final qf = _tableQuery.trim().toLowerCase();
      final b = await ref.read(fullReportsTradeBundleProvider.future);

      switch (_viewType) {
        case _ViewType.item:
          var rows = List<Map<String, dynamic>>.from(b.items);
          if (qf.isNotEmpty) {
            rows = rows
                .where((r) => _itemLabel(r).toLowerCase().contains(qf))
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
            subject:
                'Reports Items ${df.format(range.from)}–${df.format(range.to)}',
          );
        case _ViewType.supplier:
          var rows = List<Map<String, dynamic>>.from(b.suppliers);
          if (qf.isNotEmpty) {
            rows = rows
                .where((r) =>
                    (r['supplier_name']?.toString() ?? '')
                        .toLowerCase()
                        .contains(qf))
                .toList();
          }
          rows = List<Map<String, dynamic>>.from(rows)
            ..sort((a, b) => ((b['total_purchase'] as num?) ?? 0)
                .compareTo((a['total_purchase'] as num?) ?? 0));
          if (rows.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          final buf = StringBuffer();
          buf.writeln(
            '# Purchase Assistant — Suppliers — ${df.format(range.from)} to ${df.format(range.to)}',
          );
          buf.writeln('supplier_name,purchase_count,total_purchase_inr');
          for (final r in rows) {
            final name = r['supplier_name']?.toString() ?? '—';
            final deals = (r['purchase_count'] as num?)?.toInt() ?? 0;
            final buy = (r['total_purchase'] as num?)?.toDouble() ?? 0;
            buf.writeln(
              '${_csvCell(name)},$deals,${buy.toStringAsFixed(2)}',
            );
          }
          await Share.share(
            buf.toString(),
            subject:
                'Reports Suppliers ${df.format(range.from)}–${df.format(range.to)}',
          );
        case _ViewType.category:
          var rows = List<Map<String, dynamic>>.from(b.categories);
          if (qf.isNotEmpty) {
            rows = rows
                .where((r) =>
                    (r['category_name']?.toString() ?? '')
                        .toLowerCase()
                        .contains(qf))
                .toList();
          }
          rows = List<Map<String, dynamic>>.from(rows)
            ..sort((a, b) => ((b['total_purchase'] as num?) ?? 0)
                .compareTo((a['total_purchase'] as num?) ?? 0));
          if (rows.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          final buf = StringBuffer();
          buf.writeln(
            '# Purchase Assistant — Categories — ${df.format(range.from)} to ${df.format(range.to)}',
          );
          buf.writeln('category_name,total_qty,total_purchase_inr');
          for (final r in rows) {
            final name = r['category_name']?.toString() ?? '—';
            final qty = (r['total_qty'] as num?)?.toDouble() ?? 0;
            final buy = (r['total_purchase'] as num?)?.toDouble() ?? 0;
            buf.writeln(
              '${_csvCell(name)},${qty.toStringAsFixed(2)},${buy.toStringAsFixed(2)}',
            );
          }
          await Share.share(
            buf.toString(),
            subject:
                'Reports Categories ${df.format(range.from)}–${df.format(range.to)}',
          );
      }
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
      final b = await ref.read(fullReportsTradeBundleProvider.future);
      final kpi = b.kpi;
      var itemRows = List<Map<String, dynamic>>.from(b.items)
        ..sort((a, b) => _itemMetric(b).compareTo(_itemMetric(a)));
      final catRows = b.categories;
      final supRows = b.suppliers;
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
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _DatePreset.today => (from: today, to: today),
      _DatePreset.week => (
          from: today.subtract(const Duration(days: 6)),
          to: today,
        ),
      _DatePreset.month => (
          from: DateTime(n.year, n.month, 1),
          to: today,
        ),
      _DatePreset.year => (
          from: DateTime(n.year, 1, 1),
          to: today,
        ),
    };
    setState(() {
      _preset = p;
      _tableRowCap = 8;
    });
    _invalidateAnalytics();
  }

  void _invalidateAnalytics() {
    invalidateAnalyticsData(ref);
  }

  String _itemLabel(Map<String, dynamic> r) =>
      r['item_name']?.toString() ?? '—';

  num _itemMetric(Map<String, dynamic> r) =>
      (r['total_purchase'] as num?) ??
      (r['total_profit'] as num?) ??
      0;

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(fullReportsTradeBundleProvider);
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
              invalidatePurchaseWorkspace(ref);
            },
          ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : RefreshIndicator(
              onRefresh: () async {
                invalidatePurchaseWorkspace(ref);
                await ref.read(fullReportsTradeBundleProvider.future);
              },
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                children: [
                  _filterBar(),
                  const SizedBox(height: 8),
                  bundle.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => FriendlyLoadError(
                      onRetry: () =>
                          ref.invalidate(fullReportsTradeBundleProvider),
                    ),
                    data: (b) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (b.kpi.purchaseCount == 0)
                            _noPurchasesInRangeCard(context),
                          _kpiStrip(context, b.kpi),
                          const SizedBox(height: 8),
                          if (_viewType == _ViewType.item)
                            _cappedForBundle(
                              b.items,
                              buildPrimary: (page) => _itemsTable(context, page),
                              nameForFilter: (r) => _itemLabel(r),
                              sortByItemMetric: true,
                            )
                          else if (_viewType == _ViewType.supplier)
                            _cappedForBundle(
                              b.suppliers,
                              buildPrimary: (page) =>
                                  _supplierTable(context, page),
                              nameForFilter: (r) =>
                                  r['supplier_name']?.toString() ?? '',
                              sortByItemMetric: false,
                            )
                          else
                            _cappedForBundle(
                              b.categories,
                              buildPrimary: (page) =>
                                  _categoryTable(context, page),
                              nameForFilter: (r) =>
                                  r['category_name']?.toString() ?? '',
                              sortByItemMetric: false,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  /// Filter/sort/cap for snapshot-backed tables; [rows.length] drives “View more”.
  Widget _cappedForBundle(
    List<Map<String, dynamic>> source, {
    required Widget Function(List<Map<String, dynamic>> page) buildPrimary,
    required String Function(Map<String, dynamic> r) nameForFilter,
    required bool sortByItemMetric,
  }) {
    var rows = List<Map<String, dynamic>>.from(source);
    if (_tableQuery.isNotEmpty) {
      final q = _tableQuery.toLowerCase();
      rows = rows
          .where((r) => nameForFilter(r).toLowerCase().contains(q))
          .toList();
    }
    if (sortByItemMetric) {
      rows.sort((a, b) => _itemMetric(b).compareTo(_itemMetric(a)));
    } else {
      rows.sort(
        (a, b) => ((b['total_purchase'] as num?) ?? 0)
            .compareTo((a['total_purchase'] as num?) ?? 0),
      );
    }
    return _cappedPrimaryTable(
      buildPrimary(rows.take(_tableRowCap).toList()),
      rows.length,
    );
  }

  Widget _cappedPrimaryTable(Widget table, int totalRows) {
    if (totalRows <= _tableRowCap) return table;
    final more = totalRows - _tableRowCap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        table,
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _tableRowCap += 8),
              child: Text('View more ($more more)'),
            ),
          ),
        ),
      ],
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
      header: const ['Category', 'Total qty', 'Total ₹'],
      flexes: const [3, 1, 2],
      rows: rows.map((r) {
        final name = r['category_name']?.toString() ?? '—';
        final qty = (r['total_qty'] as num?)?.toDouble() ?? 0;
        final total = (r['total_purchase'] as num?)?.toDouble() ?? 0;
        final qtyStr = qty == qty.roundToDouble()
            ? qty.toInt().toString()
            : qty.toStringAsFixed(1);
        return [name, qtyStr, _inr(total.round())];
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
    Widget cell(
      String v, {
      required bool isHeader,
      bool rightAlign = false,
      bool isLastCol = false,
      bool isFirstCol = false,
    }) {
      final TextStyle? style;
      if (isHeader) {
        style = HexaDsType.label(12, color: cs.onSurface).copyWith(
          fontWeight: FontWeight.w800,
        );
      } else if (isLastCol) {
        style = HexaDsType.reportTableMoney;
      } else if (isFirstCol) {
        style = HexaDsType.reportTableRowPrimary;
      } else {
        style = tt.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Text(
          v,
          textAlign: rightAlign ? TextAlign.end : TextAlign.start,
          style: style,
        ),
      );
    }
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
                    child: cell(
                      header[i],
                      isHeader: true,
                      rightAlign: i == header.length - 1,
                    ),
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
                        isHeader: false,
                        rightAlign: i == rows[ri].length - 1,
                        isLastCol: i == rows[ri].length - 1,
                        isFirstCol: i == 0,
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
                selectedColor: const Color(0xFF0D9488),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  fontWeight: _preset == p ? FontWeight.w700 : FontWeight.w500,
                  color: _preset == p ? Colors.white : const Color(0xFF475569),
                ),
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
                  _tableRowCap = 8;
                }),
                visualDensity: VisualDensity.compact,
                selectedColor: const Color(0xFF0D9488),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  fontWeight: _viewType == v ? FontWeight.w700 : FontWeight.w500,
                  color: _viewType == v ? Colors.white : const Color(0xFF475569),
                ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 8),
            Text(
              'No purchases in this period',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try selecting a different date range above',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
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

  Widget _kpiStrip(BuildContext context, AnalyticsKpi k) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill('Spend', _inr(k.totalPurchase.round())),
            _pill('Deals', '${k.purchaseCount}'),
            if (k.totalKg > 0) _pill('Total kg', k.totalKg.toStringAsFixed(0)),
            if (k.totalBags > 0) _pill('Total bags', k.totalBags.toStringAsFixed(0)),
            if (k.totalBoxes > 0) _pill('Total boxes', k.totalBoxes.toStringAsFixed(0)),
            if (k.totalTins > 0) _pill('Total tins', k.totalTins.toStringAsFixed(0)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Spend = sum of trade line amounts in this range (matches PDF summary and home snapshot for the same dates).',
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            color: cs.onSurfaceVariant,
          ),
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
