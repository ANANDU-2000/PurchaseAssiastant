import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/analytics_kpi_provider.dart' show analyticsDateRangeProvider, analyticsKpiProvider;

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
    return kpi.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e', style: TextStyle(color: cs.error))),
      data: (d) {
        return ListView(
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

class _ItemsTab extends ConsumerWidget {
  const _ItemsTab({required this.inr});

  final String Function(num n) inr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsItemsTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No data in this range'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            final name = r['item_name']?.toString() ?? '';
            return Card(
              child: ListTile(
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Qty ${r['total_qty']} · Avg landing ${inr((r['avg_landing'] as num?)?.toDouble() ?? 0)} · P/L ${inr((r['total_profit'] as num?)?.toDouble() ?? 0)}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/item-analytics/${Uri.encodeComponent(name)}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab({required this.inr});

  final String Function(num n) inr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsCategoriesTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No categories in this range'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            return Card(
              child: ListTile(
                title: Text(r['category']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Qty ${r['total_qty']} · Lines ${r['line_count']} · Profit ${inr((r['total_profit'] as num?)?.toDouble() ?? 0)}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab({required this.inr});

  final String Function(num n) inr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsSuppliersTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No supplier-linked entries in this range'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            final id = r['supplier_id']?.toString();
            return Card(
              child: ListTile(
                title: Text(r['supplier_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Deals ${r['deals']} · Avg ${inr((r['avg_landing'] as num?)?.toDouble() ?? 0)} · P/L ${inr((r['total_profit'] as num?)?.toDouble() ?? 0)}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: id == null ? null : () => context.push('/supplier/$id'),
              ),
            );
          },
        );
      },
    );
  }
}

class _BrokersTab extends ConsumerWidget {
  const _BrokersTab({required this.inr});

  final String Function(num n) inr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsBrokersTableProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No broker-linked entries in this range'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            final bid = r['broker_id']?.toString();
            return Card(
              child: ListTile(
                title: Text(r['broker_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Deals ${r['deals']} · Commission ${inr((r['total_commission'] as num?)?.toDouble() ?? 0)} · P/L ${inr((r['total_profit'] as num?)?.toDouble() ?? 0)}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: bid == null ? null : () => context.push('/broker/$bid'),
              ),
            );
          },
        );
      },
    );
  }
}
