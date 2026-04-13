import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/tenant_branding_provider.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/notifications_provider.dart';
import '../../../core/providers/dashboard_period_provider.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/home_insights_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../entries/presentation/entry_create_sheet.dart';
import '../../../shared/widgets/app_settings_action.dart';

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(dashboardProvider);
      ref.invalidate(homeInsightsProvider);
      ref.invalidate(homeSevenDayProfitProvider);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(homeInsightsProvider);
    ref.invalidate(homeSevenDayProfitProvider);
    await Future.wait([
      ref.read(dashboardProvider.future),
      ref.read(homeInsightsProvider.future),
      ref.read(homeSevenDayProfitProvider.future),
    ]);
  }

  String _inr(num n) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(n);

  String _rangeCaption(DashboardPeriod period) {
    final r = dashboardDateRange(period);
    final a = DateFormat.MMMd().format(r.$1);
    final b = DateFormat.MMMd().format(r.$2);
    return '$a – $b, ${r.$2.year}';
  }

  static Future<void> _mediaOcrSnack(
      BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final r = await ref
          .read(hexaApiProvider)
          .mediaOcrPreview(businessId: session.primaryBusiness.id);
      if (!context.mounted) return;
      final note = r['note']?.toString() ?? 'OCR preview';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final period = ref.watch(dashboardPeriodProvider);
    final dash = ref.watch(dashboardProvider);
    final insights = ref.watch(homeInsightsProvider);
    final hi = insights.valueOrNull;
    final branding = ref.watch(tenantBrandingProvider);

    final cs = Theme.of(context).colorScheme;
    final appBarIconColor = cs.onSurfaceVariant;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            if (branding.logoUrl != null && branding.logoUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  branding.logoUrl!,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                branding.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        scrolledUnderElevation: 0,
        elevation: 0,
        actions: [
          IconTheme(
            data: IconThemeData(color: appBarIconColor),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const _HomeNotificationsButton(),
                const AppSettingsAction(),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: 80,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in DashboardPeriod.values) ...[
                        _DatePeriodPill(
                          label: dashboardPeriodLabel(p),
                          selected: period == p,
                          onTap: () {
                            ref.read(dashboardPeriodProvider.notifier).state =
                                p;
                            ref.invalidate(dashboardProvider);
                            ref.invalidate(homeInsightsProvider);
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  _rangeCaption(period),
                  style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Material(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.go('/entries?focusSearch=1'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded,
                              color: cs.onSurfaceVariant, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Search purchase log…',
                              style: tt.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: cs.onSurfaceVariant, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                72 + MediaQuery.of(context).padding.bottom,
              ),
              sliver: SliverToBoxAdapter(
                child: dash.when(
                  loading: () => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _HeroProfitLoading(),
                      const SizedBox(height: 16),
                      _StatsGridSkeleton(),
                    ],
                  ),
                  error: (_, __) => Card(
                    clipBehavior: Clip.antiAlias,
                    child: FriendlyLoadError(
                      message: 'Could not load dashboard',
                      onRetry: () => unawaited(_refresh()),
                    ),
                  ),
                  data: (d) {
                    final marginPct = d.totalPurchase > 0
                        ? (d.totalProfit / d.totalPurchase) * 100.0
                        : null;
                    final mom = hi?.profitChangePctPriorMtd;
                    final empty = d.purchaseCount == 0 && d.totalPurchase <= 0;
                    final avgPurchase = d.purchaseCount > 0
                        ? d.totalPurchase / d.purchaseCount
                        : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroProfitCard(
                          profitText: empty ? _inr(0) : _inr(d.totalProfit),
                          changePct: mom,
                          periodLabel: dashboardPeriodLabel(period),
                          rangeCaption: _rangeCaption(period),
                        ),
                        const SizedBox(height: 16),
                        _StatsGrid(
                          purchase: empty ? null : d.totalPurchase,
                          profit: empty ? null : d.totalProfit,
                          marginPct: empty ? null : marginPct,
                          count: d.purchaseCount,
                          qtyBase: empty ? null : d.totalQtyBase,
                          avgPurchase: avgPurchase,
                          inr: _inr,
                        ),
                        if (!empty)
                          insights.maybeWhen(
                            data: (ins) {
                              if (ins.topItem == null &&
                                  ins.bestSupplierName == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 16),
                                child: _HomeDecisionStrip(
                                  insights: ins,
                                  inr: _inr,
                                ),
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.notifications_active_rounded,
                                size: 20, color: HexaColors.warning),
                            const SizedBox(width: 8),
                            Text(
                              'Signals',
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (empty)
                          _SignalsEmptyState(
                              onAdd: () => showEntryCreateSheet(context))
                        else
                          insights.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            error: (_, __) => FriendlyLoadError(
                              message: 'Could not load signals',
                              onRetry: () =>
                                  ref.invalidate(homeInsightsProvider),
                            ),
                            data: (ins) =>
                                _SignalsContent(insights: ins, inr: _inr),
                          ),
                        const SizedBox(height: 24),
                        Text(
                          'Quick actions',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _QuickActionCards(
                          onAddEntry: () => showEntryCreateSheet(context),
                          onScan: () => unawaited(_mediaOcrSnack(context, ref)),
                          onReports: () => context.go('/analytics'),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SecondaryChip(
                              icon: Icons.receipt_long_outlined,
                              label: 'History',
                              onTap: () => context.go('/entries'),
                            ),
                            _SecondaryChip(
                              icon: Icons.inventory_2_outlined,
                              label: 'Catalog',
                              onTap: () => context.push('/catalog'),
                            ),
                          ],
                        ),
                        const _WeekTrendExpansion(),
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
}

class _SevenDayProfitChartRow extends ConsumerWidget {
  const _SevenDayProfitChartRow({this.showFooterCaption = true});

  final bool showFooterCaption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final series = ref.watch(homeSevenDayProfitProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              if (maxW <= 0 || !maxW.isFinite) {
                return const SizedBox(height: 80);
              }
              return series.when(
                  loading: () => SizedBox(
                    height: 80,
                    width: maxW,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (_, __) => SizedBox(
                    width: maxW,
                    height: 168,
                    child: FriendlyLoadError(
                      message: 'Could not load week chart',
                      onRetry: () =>
                          ref.invalidate(homeSevenDayProfitProvider),
                    ),
                  ),
                  data: (pts) {
                    if (pts.isEmpty ||
                        pts.every((p) => p.profit == 0)) {
                      return SizedBox(height: 80, width: maxW);
                    }
                    final spots = <FlSpot>[];
                    var maxY = 1.0;
                    for (var i = 0; i < pts.length; i++) {
                      final y = pts[i].profit;
                      if (y > maxY) maxY = y;
                      spots.add(FlSpot(i.toDouble(), y));
                    }
                    if (maxY <= 0) maxY = 1;
                    return SizedBox(
                      height: 80,
                      width: maxW,
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: maxY * 1.05,
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: const LineTouchData(enabled: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: HexaColors.accentInfo,
                              barWidth: 2.5,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: HexaColors.accentInfo
                                    .withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
            },
          ),
        ),
        if (showFooterCaption) ...[
          const SizedBox(height: 6),
          Text(
            '7-day profit trend',
            style: tt.bodySmall?.copyWith(
                color: isDark ? HexaColors.textSecondary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }
}

class _HomeDecisionStrip extends StatelessWidget {
  const _HomeDecisionStrip({
    required this.insights,
    required this.inr,
  });

  final HomeInsightsData insights;
  final String Function(num) inr;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final top = insights.topItem;
    final bs = insights.bestSupplierName;
    if (top == null && bs == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Highlights',
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (top != null)
              Expanded(
                child: _DecisionHighlightCard(
                  icon: Icons.star_rounded,
                  iconColor: HexaColors.warning,
                  label: 'Top item',
                  line1: top,
                  line2: inr(insights.topItemProfit ?? 0),
                ),
              ),
            if (top != null && bs != null) const SizedBox(width: 10),
            if (bs != null)
              Expanded(
                child: _DecisionHighlightCard(
                  icon: Icons.storefront_rounded,
                  iconColor: HexaColors.profit,
                  label: 'Best supplier',
                  line1: bs,
                  line2: inr(insights.bestSupplierProfit ?? 0),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DecisionHighlightCard extends StatelessWidget {
  const _DecisionHighlightCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.line1,
    required this.line2,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String line1;
  final String line2;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.85)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.4,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              line1,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              line2,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekTrendExpansion extends StatelessWidget {
  const _WeekTrendExpansion();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          title: Text(
            'Week profit trend',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Last 7 days (tap to expand)',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          initiallyExpanded: false,
          children: const [
            _SevenDayProfitChartRow(showFooterCaption: false),
          ],
        ),
      ),
    );
  }
}

class _HomeNotificationsButton extends ConsumerWidget {
  const _HomeNotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsUnreadCountProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Alerts',
          onPressed: () => context.push('/notifications'),
          icon: Icon(unread > 0
              ? Icons.notifications_rounded
              : Icons.notifications_outlined),
        ),
        if (unread > 0)
          const Positioned(
            right: 10,
            top: 10,
            child: SizedBox(
              width: 8,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DatePeriodPill extends StatelessWidget {
  const _DatePeriodPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = selected
        ? HexaColors.brandTeal
        : (isDark
            ? const Color(0x20FFFFFF)
            : cs.outline.withValues(alpha: 0.45));
    final unselectedLabel =
        isDark ? HexaColors.textSecondary : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? HexaColors.brandTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: tt.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : unselectedLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroProfitLoading extends StatefulWidget {
  const _HeroProfitLoading();

  @override
  State<_HeroProfitLoading> createState() => _HeroProfitLoadingState();
}

class _HeroProfitLoadingState extends State<_HeroProfitLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
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
      builder: (context, child) {
        final t = _c.value;
        return Container(
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Color.lerp(
              const Color(0xFFF1F5F9),
              HexaColors.primaryMid.withValues(alpha: 0.08),
              t,
            ),
            border: Border.all(
              color: HexaColors.primaryMid.withValues(alpha: 0.25),
            ),
          ),
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: HexaColors.primaryMid.withValues(alpha: 0.85),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatsGridSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Row(
            children: [
              Expanded(child: _statSkeletonCell(context)),
              const SizedBox(width: 10),
              Expanded(child: _statSkeletonCell(context)),
            ],
          ),
          if (i < 2) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _statSkeletonCell(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HexaColors.border.withValues(alpha: 0.5)),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.purchase,
    required this.profit,
    required this.marginPct,
    required this.count,
    required this.qtyBase,
    required this.avgPurchase,
    required this.inr,
  });

  final double? purchase;
  final double? profit;
  final double? marginPct;
  final int count;
  final double? qtyBase;
  final double? avgPurchase;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Purchase ₹',
                value: purchase != null ? inr(purchase!) : inr(0),
                stripe: HexaColors.chartLandingCost,
                icon: Icons.shopping_bag_outlined,
                iconTint: HexaColors.chartLandingCost,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Profit ₹',
                value: profit != null ? inr(profit!) : inr(0),
                stripe: HexaColors.profit,
                icon: Icons.trending_up_rounded,
                iconTint: HexaColors.profit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Margin %',
                value: marginPct != null
                    ? '${marginPct!.toStringAsFixed(1)}%'
                    : '0%',
                stripe: HexaColors.accentAmber,
                icon: Icons.percent_rounded,
                iconTint: HexaColors.accentAmber,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Count',
                value: '$count',
                stripe: HexaColors.chartPurple,
                icon: Icons.receipt_long_outlined,
                iconTint: HexaColors.chartPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Qty (base)',
                value: qtyBase != null ? qtyBase!.toStringAsFixed(1) : '0',
                stripe: HexaColors.chartOrange,
                icon: Icons.scale_outlined,
                iconTint: HexaColors.chartOrange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Avg/Purchase',
                value: avgPurchase != null ? inr(avgPurchase!) : inr(0),
                stripe: HexaColors.chartPink,
                icon: Icons.bar_chart_rounded,
                iconTint: HexaColors.chartPink,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor =
        isDark ? HexaColors.textSecondary : cs.onSurfaceVariant;
    final valueColor = isDark ? HexaColors.textPrimary : cs.onSurface;
    return Material(
      color: isDark ? HexaColors.surfaceCard : cs.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark
                  ? HexaColors.border
                  : cs.outlineVariant.withValues(alpha: 0.85)),
          boxShadow: HexaColors.cardShadow(context),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 44,
              decoration: BoxDecoration(
                color: stripe,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconTint.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: iconTint),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 10,
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: tt.titleMedium?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: valueColor,
                      letterSpacing: -0.3,
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
}

class _SignalsEmptyState extends StatelessWidget {
  const _SignalsEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: HexaColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.85)),
        boxShadow: HexaColors.cardShadow(context),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 48, color: HexaColors.primaryMid.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(
            'Record a purchase to see profit signals here.',
            textAlign: TextAlign.center,
            style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                fontSize: 15),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: Material(
              color: HexaColors.primaryMid.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onAdd,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: HexaColors.primaryMid.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_shopping_cart_rounded,
                          color: HexaColors.primaryMid, size: 20),
                      SizedBox(width: 6),
                      Text(
                        '+ New purchase',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: HexaColors.primaryMid,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalsContent extends StatelessWidget {
  const _SignalsContent({required this.insights, required this.inr});

  final HomeInsightsData insights;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    final hi = insights;
    final chips = <Widget>[];

    if (hi.negativeLineCount > 0) {
      chips.add(
        _SignalChip(
          color: HexaColors.loss.withValues(alpha: 0.12),
          border: HexaColors.loss.withValues(alpha: 0.35),
          icon: Icons.warning_amber_rounded,
          iconColor: HexaColors.loss,
          title: '${hi.negativeLineCount} loss lines',
          subtitle: 'Check selling vs landing',
        ),
      );
    }
    if (hi.topItem != null) {
      chips.add(
        _SignalChip(
          color: HexaColors.warning.withValues(alpha: 0.12),
          border: HexaColors.warning.withValues(alpha: 0.3),
          icon: Icons.emoji_events_rounded,
          iconColor: HexaColors.warning,
          title: 'Top item',
          subtitle: '${hi.topItem!}, ${inr(hi.topItemProfit ?? 0)}',
        ),
      );
    }
    if (hi.worstItem != null &&
        hi.worstItemProfit != null &&
        (hi.worstItem != hi.topItem || hi.worstItemProfit! < 0)) {
      chips.add(
        _SignalChip(
          color: HexaColors.loss.withValues(alpha: 0.1),
          border: HexaColors.loss.withValues(alpha: 0.28),
          icon: Icons.trending_down_rounded,
          iconColor: HexaColors.loss,
          title: 'Needs attention',
          subtitle: '${hi.worstItem!}, ${inr(hi.worstItemProfit!)}',
        ),
      );
    }
    if (hi.bestSupplierName != null) {
      chips.add(
        _SignalChip(
          color: HexaColors.primaryLight,
          border: HexaColors.primaryMid.withValues(alpha: 0.25),
          icon: Icons.storefront_rounded,
          iconColor: HexaColors.primaryMid,
          title: 'Best supplier',
          subtitle:
              '${hi.bestSupplierName!}, ${inr(hi.bestSupplierProfit ?? 0)}',
        ),
      );
    }
    for (final a in hi.alerts) {
      final sev = a['severity']?.toString() ?? 'info';
      final warn = sev == 'warning';
      chips.add(
        _SignalChip(
          color: warn
              ? HexaColors.loss.withValues(alpha: 0.08)
              : HexaColors.primaryLight,
          border: warn
              ? HexaColors.loss.withValues(alpha: 0.25)
              : HexaColors.primaryMid.withValues(alpha: 0.2),
          icon: warn ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          iconColor: warn ? HexaColors.loss : HexaColors.primaryMid,
          title: 'Alert',
          subtitle: a['message']?.toString() ?? '',
        ),
      );
    }

    if (chips.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Text(
        'Signals will appear after you record purchases in this period.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark ? HexaColors.textSecondary : cs.onSurfaceVariant,
            ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.color,
    required this.border,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final Color border;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style:
                        tt.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(
                      color: isDark
                          ? HexaColors.textSecondary
                          : cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCards extends StatelessWidget {
  const _QuickActionCards({
    required this.onAddEntry,
    required this.onScan,
    required this.onReports,
  });

  final VoidCallback onAddEntry;
  final VoidCallback onScan;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sideCardBg = HexaColors.surfaceCard;
    final sideBorder = isDark
        ? HexaColors.border
        : cs.outlineVariant.withValues(alpha: 0.85);
    final sideIcon = isDark ? Colors.white : cs.primary;
    final sideLabel =
        isDark ? HexaColors.textSecondary : cs.onSurfaceVariant;
    const h = 64.0;
    Widget cell({
      required VoidCallback onTap,
      required Widget child,
      Color? fill,
      Color? borderC,
    }) {
      return Expanded(
        child: Material(
          color: fill ?? sideCardBg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              height: h,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: borderC ?? sideBorder,
                ),
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        cell(
          onTap: onAddEntry,
          fill: HexaColors.primaryMid.withValues(alpha: 0.12),
          borderC: HexaColors.primaryMid.withValues(alpha: 0.4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_shopping_cart_rounded,
                  size: 22, color: HexaColors.primaryMid),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'New purchase',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelLarge?.copyWith(
                    color: HexaColors.primaryMid,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        cell(
          onTap: onScan,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.document_scanner_outlined,
                  size: 22, color: sideIcon),
              const SizedBox(height: 4),
              Text(
                'Scan',
                style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: sideLabel,
                    fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        cell(
          onTap: onReports,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart_rounded, size: 22, color: sideIcon),
              const SizedBox(height: 4),
              Text(
                'Reports',
                style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: sideLabel,
                    fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SecondaryChip extends StatelessWidget {
  const _SecondaryChip(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? HexaColors.surfaceElevated : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? HexaColors.border
                    : cs.outlineVariant.withValues(alpha: 0.85)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(label,
                  style: tt.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? HexaColors.textSecondary : cs.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroProfitCard extends StatelessWidget {
  const _HeroProfitCard({
    required this.profitText,
    required this.changePct,
    required this.periodLabel,
    required this.rangeCaption,
  });

  final String profitText;
  final double? changePct;
  final String periodLabel;
  final String rangeCaption;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final up = changePct != null && changePct! >= 0;
    final badgeColor = up ? HexaColors.profit : HexaColors.loss;

    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 140,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: HexaColors.primaryMid.withValues(alpha: 0.35)),
          boxShadow: HexaColors.cardShadow(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.trending_up_rounded,
                            color: HexaColors.primaryMid.withValues(alpha: 0.9),
                            size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Total Profit',
                          style: tt.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      profitText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.headlineMedium?.copyWith(
                        height: 1.0,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$periodLabel · $rangeCaption',
                      style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (changePct != null)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: badgeColor, width: 0.5),
                  ),
                  child: Text(
                    '${up ? '+' : ''}${changePct!.toStringAsFixed(1)}%',
                    style: tt.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
