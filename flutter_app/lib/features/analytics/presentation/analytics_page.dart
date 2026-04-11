import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/analytics_kpi_provider.dart' show analyticsDateRangeProvider, analyticsKpiProvider;
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/app_settings_action.dart';

List<Map<String, dynamic>> _sortedRows(
  List<Map<String, dynamic>> rows,
  String mode,
  bool asc,
  num Function(Map<String, dynamic> r) profitKey,
) {
  final o = List<Map<String, dynamic>>.from(rows);
  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (mode) {
      case 'name':
        return (a['item_name'] ?? a['category'] ?? a['supplier_name'] ?? a['broker_name'] ?? '')
            .toString()
            .compareTo((b['item_name'] ?? b['category'] ?? b['supplier_name'] ?? b['broker_name'] ?? '').toString());
      case 'qty':
        return ((a['total_qty'] as num?) ?? 0).compareTo((b['total_qty'] as num?) ?? 0);
      case 'deals':
        return ((a['deals'] as num?) ?? 0).compareTo((b['deals'] as num?) ?? 0);
      case 'avg':
        return ((a['avg_landing'] as num?) ?? 0).compareTo((b['avg_landing'] as num?) ?? 0);
      case 'commission':
        return ((a['total_commission'] as num?) ?? 0).compareTo((b['total_commission'] as num?) ?? 0);
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
          title: const Text('Reports'),
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
    final items = ref.watch(analyticsItemsTableProvider);
    final cats = ref.watch(analyticsCategoriesTableProvider);
    return kpi.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e', style: TextStyle(color: cs.error))),
      data: (d) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(analyticsKpiProvider);
            ref.invalidate(analyticsItemsTableProvider);
            ref.invalidate(analyticsCategoriesTableProvider);
            await ref.read(analyticsKpiProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Summary', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      _row('Total profit', inr(d.totalProfit)),
                      _row('Total purchase', inr(d.totalPurchase)),
                      _row('Purchase count', '${d.purchaseCount}'),
                      _row('Qty (base)', d.totalQtyBase.toStringAsFixed(1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              cats.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rows) {
                  if (rows.isEmpty) return const SizedBox.shrink();
                  final profits = rows.map((r) => (r['total_profit'] as num?)?.toDouble() ?? 0.0).toList();
                  final total = profits.fold<double>(0, (a, b) => a + b);
                  if (total <= 0) return const SizedBox.shrink();
                  final pieColors = [
                    HexaColors.primaryMid,
                    HexaColors.accentAmber,
                    HexaColors.profit,
                    const Color(0xFF5C6BC0),
                    const Color(0xFF00897B),
                    const Color(0xFFAD1457),
                  ];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Profit by category', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 200,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 44,
                                sections: [
                                  for (var i = 0; i < rows.length && i < 8; i++)
                                    PieChartSectionData(
                                      color: pieColors[i % pieColors.length],
                                      value: (profits[i]).clamp(0, 1e18),
                                      title: '${((profits[i] / total) * 100).toStringAsFixed(0)}%',
                                      radius: 58,
                                      titleStyle: tt.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (var i = 0; i < rows.length && i < 8; i++)
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
                },
              ),
              const SizedBox(height: 12),
              items.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (rows) {
                if (rows.isEmpty) return const SizedBox.shrink();
                final top = rows.take(5).toList();
                final profits = top.map((r) => (r['total_profit'] as num?)?.toDouble() ?? 0.0).toList();
                final maxY = profits.fold<double>(1, (a, b) => a > b ? a : b);
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
                          child: BarChart(
                            BarChartData(
                              maxY: maxY * 1.15,
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 28,
                                    getTitlesWidget: (v, meta) {
                                      final i = v.toInt();
                                      if (i < 0 || i >= top.length) return const SizedBox.shrink();
                                      final name = top[i]['item_name']?.toString() ?? '';
                                      final short = name.length > 6 ? '${name.substring(0, 6)}…' : name;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(short, style: tt.labelSmall),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 36,
                                    getTitlesWidget: (v, meta) => Text(
                                      v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                                      style: tt.labelSmall,
                                    ),
                                  ),
                                ),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              barGroups: [
                                for (var i = 0; i < top.length; i++)
                                  BarChartGroupData(
                                    x: i,
                                    barRods: [
                                      BarChartRodData(
                                        toY: profits[i],
                                        width: 18,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                        color: cs.primary,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
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
  String _sort = 'profit';
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsItemsTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No data in this range'));
        }
        final sorted = _sortedRows(
          rows,
          _sort,
          _asc,
          (r) => (r['total_profit'] as num?) ?? 0,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Sort: '),
                  DropdownButton<String>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: 'profit', child: Text('Profit')),
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                      DropdownMenuItem(value: 'qty', child: Text('Qty')),
                      DropdownMenuItem(value: 'avg', child: Text('Avg landing')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _sort = v);
                    },
                  ),
                  IconButton(
                    tooltip: 'Direction',
                    onPressed: () => setState(() => _asc = !_asc),
                    icon: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward),
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
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = sorted[i];
                    final name = r['item_name']?.toString() ?? '';
                    return Card(
                      child: ListTile(
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Qty ${r['total_qty']} · Avg landing ${widget.inr((r['avg_landing'] as num?)?.toDouble() ?? 0)} · P/L ${widget.inr((r['total_profit'] as num?)?.toDouble() ?? 0)}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/item-analytics/${Uri.encodeComponent(name)}'),
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
  String _sort = 'profit';
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsCategoriesTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No categories in this range'));
        }
        final sorted = _sortedRows(rows, _sort, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Sort: '),
                  DropdownButton<String>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: 'profit', child: Text('Profit')),
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                      DropdownMenuItem(value: 'qty', child: Text('Qty')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _sort = v);
                    },
                  ),
                  IconButton(
                    onPressed: () => setState(() => _asc = !_asc),
                    icon: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward),
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
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = sorted[i];
                    return Card(
                      child: ListTile(
                        title: Text(r['category']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Qty ${r['total_qty']} · Lines ${r['line_count']} · Profit ${widget.inr((r['total_profit'] as num?)?.toDouble() ?? 0)}',
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
  String _sort = 'profit';
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsSuppliersTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No supplier-linked entries in this range'));
        }
        final sorted = _sortedRows(rows, _sort, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Sort: '),
                  DropdownButton<String>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: 'profit', child: Text('Profit')),
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                      DropdownMenuItem(value: 'deals', child: Text('Deals')),
                      DropdownMenuItem(value: 'avg', child: Text('Avg landing')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _sort = v);
                    },
                  ),
                  IconButton(
                    onPressed: () => setState(() => _asc = !_asc),
                    icon: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward),
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
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = sorted[i];
                    final id = r['supplier_id']?.toString();
                    return Card(
                      child: ListTile(
                        title: Text(r['supplier_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Deals ${r['deals']} · Avg ${widget.inr((r['avg_landing'] as num?)?.toDouble() ?? 0)} · P/L ${widget.inr((r['total_profit'] as num?)?.toDouble() ?? 0)}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: id == null ? null : () => context.push('/supplier/$id'),
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
  String _sort = 'commission';
  bool _asc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsBrokersTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No broker-linked entries in this range'));
        }
        final sorted = _sortedRows(rows, _sort, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Sort: '),
                  DropdownButton<String>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: 'commission', child: Text('Commission')),
                      DropdownMenuItem(value: 'profit', child: Text('Profit')),
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                      DropdownMenuItem(value: 'deals', child: Text('Deals')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _sort = v);
                    },
                  ),
                  IconButton(
                    onPressed: () => setState(() => _asc = !_asc),
                    icon: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward),
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
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = sorted[i];
                    final bid = r['broker_id']?.toString();
                    return Card(
                      child: ListTile(
                        title: Text(r['broker_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Deals ${r['deals']} · Commission ${widget.inr((r['total_commission'] as num?)?.toDouble() ?? 0)} · P/L ${widget.inr((r['total_profit'] as num?)?.toDouble() ?? 0)}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: bid == null ? null : () => context.push('/broker/$bid'),
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
