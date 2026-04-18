import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/dashboard_period_provider.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/home_insights_provider.dart';
import '../../../core/providers/notifications_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart'
    show
        purchaseAlertsProvider,
        purchaseUnitTotalsProvider,
        tradePurchasesListProvider;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/app_settings_action.dart';

// ─── Formatter helpers ────────────────────────────────────────────────────────

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _formatPct(double? pct) {
  if (pct == null) return '';
  if (pct.abs() > 999) return pct > 0 ? '+new' : '–new';
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(1)}%';
}

String _itemQtyLabel(Map<String, dynamic> r) {
  final u = (r['unit'] ?? r['primary_unit'] ?? 'kg').toString();
  final tq = (r['total_qty'] as num?)?.toDouble() ?? 0;
  final ul = u.toUpperCase();
  if (ul.contains('BAG')) return '${tq.round()} bags';
  if (ul.contains('BOX')) return '${tq.round()} boxes';
  if (ul.contains('TIN')) return '${tq.round()} tins';
  return '${tq.toStringAsFixed(0)} $u';
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(homeInsightsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && mounted) {
      ref.invalidate(dashboardProvider);
      ref.invalidate(homeInsightsProvider);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(homeInsightsProvider);
    ref.invalidate(tradePurchasesListProvider);
    await Future.wait([
      ref.read(dashboardProvider.future),
      ref.read(homeInsightsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final period   = ref.watch(dashboardPeriodProvider);
    final dash     = ref.watch(dashboardProvider);
    final insights = ref.watch(homeInsightsProvider);
    final hi       = insights.valueOrNull;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: _buildAppBar(context),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: HexaColors.brandPrimary,
          edgeOffset: 80,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // Filter chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _FilterChips(
                    selected: period,
                    onSelect: (p) {
                      ref.read(dashboardPeriodProvider.notifier).state = p;
                      ref.invalidate(dashboardProvider);
                      ref.invalidate(homeInsightsProvider);
                    },
                  ),
                ),
              ),

              // Dashboard body
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    16, 14, 16, 96 + MediaQuery.of(context).padding.bottom),
                sliver: SliverToBoxAdapter(
                  child: dash.when(
                    loading: () => const _LoadingShimmer(),
                    error: (_, __) => Card(
                      clipBehavior: Clip.antiAlias,
                      child: FriendlyLoadError(
                        message: 'Could not load dashboard',
                        onRetry: () => unawaited(_refresh()),
                      ),
                    ),
                    data: (d) {
                      final mom     = hi?.profitChangePctPriorMtd;
                      final trend   = ref.watch(homeSevenDayProfitProvider);
                      final topItems =
                          ref.watch(_homeTopItemsProvider(period));
                      final topSups =
                          ref.watch(_homeTopSuppliersProvider(period));
                      final topCats =
                          ref.watch(_homeTopCategoriesProvider(period));
                      final recentAsync =
                          ref.watch(tradePurchasesListProvider);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Hero summary card ──
                          _HeroSummaryCard(
                            profitText: _inr(d.totalProfit),
                            changePct:  mom,
                            purchaseCount: d.purchaseCount,
                            revenue: d.totalPurchase,
                            period: dashboardPeriodLabel(period),
                          ),
                          const SizedBox(height: 12),
                          _PurchaseAlertsRow(
                            counts: ref.watch(purchaseAlertsProvider),
                            onOverdue: () =>
                                context.go('/purchase?filter=overdue'),
                            onDueSoon: () =>
                                context.go('/purchase?filter=due_soon'),
                            onPaid: () => context.go('/purchase?filter=paid'),
                          ),
                          const SizedBox(height: 10),
                          _UnitTotalsStrip(
                              totals: ref.watch(purchaseUnitTotalsProvider)),
                          const SizedBox(height: 14),

                          // ── Sparkline ──
                          if (trend.hasValue && (trend.value?.length ?? 0) > 1)
                            _SparklineCard(trend: trend),

                          const SizedBox(height: 16),

                          // ── Top Items ──
                          _SectionList(
                            title: 'Top Items',
                            icon: Icons.inventory_2_outlined,
                            rows: topItems.maybeWhen(
                                data: (v) => v, orElse: () => const []),
                            nameOf: (r) => r['item_name']?.toString() ?? '—',
                            valueOf: (r) => _inr(
                                ((r['total_profit'] as num?) ?? 0).round()),
                            metaOf: (r) {
                              final m = (r['margin_pct'] as num?) ?? 0;
                              return '${_itemQtyLabel(r)} · ${m.toStringAsFixed(1)}%';
                            },
                            accentColor: HexaColors.brandPrimary,
                            onViewAll: () => context.go('/analytics'),
                          ),
                          const SizedBox(height: 14),

                          // ── Top Suppliers ──
                          _SectionList(
                            title: 'Top Suppliers',
                            icon: Icons.storefront_outlined,
                            rows: topSups.maybeWhen(
                                data: (v) => v, orElse: () => const []),
                            nameOf: (r) =>
                                r['supplier_name']?.toString() ?? '—',
                            valueOf: (r) => _inr(
                                ((r['avg_landing'] as num?) ?? 0).round()),
                            metaOf: (r) {
                              final m = (r['margin_pct'] as num?) ?? 0;
                              return m >= 8 ? 'High margin' : 'Best price';
                            },
                            accentColor: HexaColors.brandAccent,
                            onViewAll: () => context.go('/analytics'),
                          ),
                          const SizedBox(height: 14),

                          // ── Categories ──
                          _SectionList(
                            title: 'Categories',
                            icon: Icons.category_outlined,
                            rows: topCats.maybeWhen(
                                data: (v) => v, orElse: () => const []),
                            nameOf: (r) => r['category']?.toString() ?? '—',
                            valueOf: (r) =>
                                '${((r['total_qty'] as num?) ?? 0).toStringAsFixed(0)} kg',
                            metaOf: (_) => 'volume',
                            accentColor: HexaColors.brandGold,
                            onViewAll: () => context.go('/analytics'),
                          ),
                          const SizedBox(height: 14),

                          // ── Recent Purchases ──
                          _RecentPurchasesSection(
                            async: recentAsync,
                            onViewAll: () => context.go('/purchase'),
                            onAdd: () => context.push('/purchase/new'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final icon = cs.onSurfaceVariant;
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: HexaColors.brandBackground,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Catalog',
          onPressed: () => context.push('/catalog'),
          icon: Icon(Icons.inventory_2_outlined, color: icon, size: 22),
          padding: const EdgeInsets.all(8),
        ),
        IconButton(
          tooltip: 'Contacts',
          onPressed: () => context.push('/contacts'),
          icon: Icon(Icons.groups_outlined, color: icon, size: 22),
          padding: const EdgeInsets.all(8),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: Icon(Icons.refresh_rounded, color: icon, size: 22),
          padding: const EdgeInsets.all(8),
        ),
        IconButton(
          tooltip: 'Search',
          onPressed: () => context.push('/search'),
          icon: Icon(Icons.search_rounded, color: icon, size: 22),
          padding: const EdgeInsets.all(8),
        ),
        _NotifButton(icon: icon),
        const AppSettingsAction(),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─── Filter chips ─────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});
  final DashboardPeriod selected;
  final void Function(DashboardPeriod) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: DashboardPeriod.values.map((p) {
          final active = p == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  gradient: active ? HexaColors.ctaGradient : null,
                  color: active ? null : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? Colors.transparent
                        : HexaColors.brandBorder,
                    width: 1,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: HexaColors.brandPrimary
                                .withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  dashboardPeriodLabel(p),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : HexaColors.neutral,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Hero Summary Card ────────────────────────────────────────────────────────

class _HeroSummaryCard extends StatelessWidget {
  const _HeroSummaryCard({
    required this.profitText,
    required this.changePct,
    required this.purchaseCount,
    required this.revenue,
    required this.period,
  });

  final String profitText;
  final double? changePct;
  final int purchaseCount;
  final double revenue;
  final String period;

  @override
  Widget build(BuildContext context) {
    final up         = (changePct ?? 0) >= 0;
    final badgeColor = up ? const Color(0xFF4ADE80) : const Color(0xFFFC8181);
    final pctText    = _formatPct(changePct);

    return Container(
      decoration: BoxDecoration(
        gradient: HexaColors.heroCardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: HexaColors.heroShadow(),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  period,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (pctText.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: badgeColor.withValues(alpha: 0.50), width: 0.8),
                  ),
                  child: Text(
                    '${up ? '↑' : '↓'} $pctText',
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Profit
          const Text(
            'Total Profit',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profitText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 18),

          // Stats row
          Row(
            children: [
              _StatChip(
                icon: Icons.shopping_bag_outlined,
                label: 'Purchases',
                value: purchaseCount.toString(),
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.payments_outlined,
                label: 'Revenue',
                value: _inr(revenue.round()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Sparkline ────────────────────────────────────────────────────────────────

class _SparklineCard extends StatelessWidget {
  const _SparklineCard({required this.trend});
  final AsyncValue<List<AnalyticsDailyProfitPoint>> trend;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: trend.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (pts) {
          if (pts.length < 2) return const SizedBox.shrink();
          final spots = <FlSpot>[];
          var minY = pts.first.profit, maxY = pts.first.profit;
          for (var i = 0; i < pts.length; i++) {
            final y = pts[i].profit;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            spots.add(FlSpot(i.toDouble(), y));
          }
          final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
          return Row(
            children: [
              Expanded(
                child: LineChart(
                  LineChartData(
                    minY: minY - span * 0.1,
                    maxY: maxY + span * 0.1,
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        gradient: HexaColors.ctaGradient,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              HexaColors.brandPrimary.withValues(alpha: 0.18),
                              HexaColors.brandPrimary.withValues(alpha: 0.02),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('7-day',
                      style: TextStyle(
                          fontSize: 10,
                          color: HexaColors.neutral,
                          fontWeight: FontWeight.w500)),
                  Text('profit',
                      style: TextStyle(
                          fontSize: 10,
                          color: HexaColors.neutral.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w400)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Section list ─────────────────────────────────────────────────────────────

class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.title,
    required this.icon,
    required this.rows,
    required this.nameOf,
    required this.valueOf,
    required this.metaOf,
    required this.accentColor,
    required this.onViewAll,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) nameOf;
  final String Function(Map<String, dynamic>) valueOf;
  final String Function(Map<String, dynamic>) metaOf;
  final Color accentColor;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: accentColor),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: HexaColors.brandPrimary)),
                const Spacer(),
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('View all',
                      style: TextStyle(
                          fontSize: 12,
                          color: accentColor,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text('No data for this period',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            )
          else
            ...List.generate(rows.length, (i) {
              final r = rows[i];
              return Column(
                children: [
                  if (i > 0)
                    Divider(
                        height: 1,
                        color: HexaColors.brandBorder
                            .withValues(alpha: 0.6),
                        indent: 14,
                        endIndent: 14),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: accentColor)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            nameOf(r),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(valueOf(r),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: HexaColors.brandPrimary)),
                            Text(metaOf(r),
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: HexaColors.neutral,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

// ─── Recent Purchases ─────────────────────────────────────────────────────────

class _RecentPurchasesSection extends StatelessWidget {
  const _RecentPurchasesSection({
    required this.async,
    required this.onViewAll,
    required this.onAdd,
  });

  final AsyncValue<List<Map<String, dynamic>>> async;
  final VoidCallback onViewAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: HexaColors.brandGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_outlined,
                      size: 16, color: HexaColors.brandGold),
                ),
                const SizedBox(width: 10),
                const Text('Recent Purchases',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: HexaColors.brandPrimary)),
                const Spacer(),
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('View all',
                      style: TextStyle(
                          fontSize: 12,
                          color: HexaColors.brandGold,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child:
                      CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Could not load purchases',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500)),
            ),
            data: (items) {
              if (items.isEmpty) return _EmptyPurchaseState(onAdd: onAdd);
              final recent = items.take(5).toList();
              return Column(
                children: List.generate(recent.length, (i) {
                  final r      = recent[i];
                  final hid    = r['human_id']?.toString() ?? '';
                  final date   = r['purchase_date']?.toString() ?? '';
                  final total  = (r['total_amount'] as num?)?.toDouble() ?? 0;
                  final supp   = r['supplier_name']?.toString() ??
                      r['supplier_id']?.toString() ??
                      '—';
                  final status = r['derived_status']?.toString() ??
                      r['status']?.toString() ??
                      'draft';

                  return Column(
                    children: [
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: HexaColors.brandBorder
                              .withValues(alpha: 0.6),
                          indent: 14,
                          endIndent: 14,
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: HexaColors.ctaGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  supp.isNotEmpty
                                      ? supp[0].toUpperCase()
                                      : 'P',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(supp,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                    '$hid  ·  $date',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: HexaColors.neutral),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_inr(total.round()),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: HexaColors.brandPrimary)),
                                _StatusBadge(status),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PurchaseAlertsRow extends StatelessWidget {
  const _PurchaseAlertsRow({
    required this.counts,
    required this.onOverdue,
    required this.onDueSoon,
    required this.onPaid,
  });

  final Map<String, int> counts;
  final VoidCallback onOverdue;
  final VoidCallback onDueSoon;
  final VoidCallback onPaid;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AlertMini(
            label: 'Overdue',
            value: '${counts['overdue'] ?? 0}',
            color: HexaColors.loss,
            onTap: onOverdue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _AlertMini(
            label: 'Due soon',
            value: '${counts['dueSoon'] ?? 0}',
            color: const Color(0xFFF59E0B),
            onTap: onDueSoon,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _AlertMini(
            label: 'Paid',
            value: '${counts['paid'] ?? 0}',
            color: HexaColors.brandAccent,
            onTap: onPaid,
          ),
        ),
      ],
    );
  }
}

class _AlertMini extends StatelessWidget {
  const _AlertMini({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HexaColors.brandBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitTotalsStrip extends StatelessWidget {
  const _UnitTotalsStrip({required this.totals});
  final ({int bags, int boxes, int tins}) totals;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Text(
        '${totals.bags} bags  •  ${totals.boxes} boxes  •  ${totals.tins} tins',
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: HexaColors.brandPrimary),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status.toLowerCase()) {
      'confirmed' => (HexaColors.profit, 'Pending'),
      'paid' => (HexaColors.brandAccent, 'Paid'),
      'partially_paid' => (const Color(0xFFF59E0B), 'Partial'),
      'overdue' => (HexaColors.loss, 'Overdue'),
      'draft' => (HexaColors.neutral, 'Draft'),
      'saved' => (HexaColors.neutral, 'Saved'),
      'cancelled' => (HexaColors.loss, 'Cancelled'),
      _ => (HexaColors.neutral, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _EmptyPurchaseState extends StatelessWidget {
  const _EmptyPurchaseState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: HexaColors.ctaGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 32, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'No purchases yet',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: HexaColors.brandPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add your first purchase to see data here',
            style: TextStyle(fontSize: 13, color: HexaColors.neutral),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Purchase'),
              style: FilledButton.styleFrom(
                backgroundColor: HexaColors.brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading shimmer ──────────────────────────────────────────────────────────

class _LoadingShimmer extends StatefulWidget {
  const _LoadingShimmer();
  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final shimmer = Color.lerp(
          const Color(0xFFF1F5F9),
          HexaColors.brandPrimary.withValues(alpha: 0.07),
          t,
        )!;
        return Column(
          children: [
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: shimmer,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: shimmer,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: shimmer,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Notifications button ─────────────────────────────────────────────────────

class _NotifButton extends ConsumerWidget {
  const _NotifButton({required this.icon});
  final Color icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsUnreadCountProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Alerts',
          onPressed: () => context.push('/notifications'),
          icon: Icon(
            unread > 0
                ? Icons.notifications_rounded
                : Icons.notifications_outlined,
            color: icon,
            size: 22,
          ),
          padding: const EdgeInsets.all(8),
        ),
        if (unread > 0)
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: HexaColors.loss, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

// ─── Data providers ───────────────────────────────────────────────────────────

final _homeTopItemsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DashboardPeriod>((ref, period) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final range = dashboardDateRange(period);
  final fmt   = DateFormat('yyyy-MM-dd');
  final rows  = await ref.read(hexaApiProvider).analyticsItems(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.$1),
        to: fmt.format(range.$2),
      );
  final out = List<Map<String, dynamic>>.from(rows);
  out.sort((a, b) => ((b['total_profit'] as num?) ?? 0)
      .compareTo((a['total_profit'] as num?) ?? 0));
  return out.take(3).toList();
});

final _homeTopSuppliersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DashboardPeriod>((ref, period) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final range = dashboardDateRange(period);
  final fmt   = DateFormat('yyyy-MM-dd');
  final rows  = await ref.read(hexaApiProvider).analyticsSuppliers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.$1),
        to: fmt.format(range.$2),
      );
  final out = List<Map<String, dynamic>>.from(rows);
  out.sort((a, b) => ((b['total_profit'] as num?) ?? 0)
      .compareTo((a['total_profit'] as num?) ?? 0));
  return out.take(3).toList();
});

final _homeTopCategoriesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DashboardPeriod>((ref, period) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final range = dashboardDateRange(period);
  final fmt   = DateFormat('yyyy-MM-dd');
  final rows  = await ref.read(hexaApiProvider).analyticsCategories(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.$1),
        to: fmt.format(range.$2),
      );
  final out = List<Map<String, dynamic>>.from(rows);
  out.sort((a, b) => ((b['total_profit'] as num?) ?? 0)
      .compareTo((a['total_profit'] as num?) ?? 0));
  return out.take(3).toList();
});
