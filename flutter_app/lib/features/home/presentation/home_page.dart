import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/tenant_branding_provider.dart';
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
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(homeInsightsProvider);
    await Future.wait([
      ref.read(dashboardProvider.future),
      ref.read(homeInsightsProvider.future),
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
                IconButton(
                  tooltip: 'Search',
                  onPressed: () => context.push('/search'),
                  icon: const Icon(Icons.search_rounded),
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
              child: insights.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (ins) {
                  final parts = <String>[];
                  if (ins.topItem != null &&
                      ins.topItemProfit != null &&
                      ins.topItem!.isNotEmpty) {
                    parts.add(
                      'Top item: ${ins.topItem} (${_inr(ins.topItemProfit!.round())})',
                    );
                  }
                  if (ins.bestSupplierName != null &&
                      ins.bestSupplierName!.isNotEmpty) {
                    parts.add('Best supplier: ${ins.bestSupplierName}');
                  }
                  if (ins.negativeLineCount > 0) {
                    parts.add(
                      '${ins.negativeLineCount} line${ins.negativeLineCount == 1 ? '' : 's'} below cost',
                    );
                  }
                  if (parts.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Material(
                      color: HexaColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.tips_and_updates_outlined,
                              size: 18,
                              color: HexaColors.accentInfo,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                parts.join(' · '),
                                style: tt.bodySmall?.copyWith(
                                  color: HexaColors.textBody,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
                  loading: () => const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroProfitLoading(),
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
                    final mom = hi?.profitChangePctPriorMtd;
                    final trendAsync = ref.watch(homeSevenDayProfitProvider);
                    final topItemsAsync = ref.watch(_homeTopItemsProvider(period));
                    final topSuppliersAsync =
                        ref.watch(_homeTopSuppliersProvider(period));
                    final topCategoriesAsync =
                        ref.watch(_homeTopCategoriesProvider(period));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CompactHeader(
                          ownerName: branding.title,
                          periodLabel: dashboardPeriodLabel(period),
                        ),
                        const SizedBox(height: 8),
                        _CompactProfitHead(
                          profitText: _inr(d.totalProfit),
                          changePct: mom,
                          topItem: hi?.topItem,
                          bestSupplier: hi?.bestSupplierName,
                        ),
                        const SizedBox(height: 8),
                        _ThinSparkline(
                          trend: trendAsync,
                          stroke: HexaColors.accentInfo,
                        ),
                        const SizedBox(height: 8),
                        _CompactInsightsStrip(
                          alerts: hi?.alerts ?? const [],
                          negativeLines: hi?.negativeLineCount ?? 0,
                        ),
                        const SizedBox(height: 8),
                        _SmallActions(
                          onAdd: () => showEntryCreateSheet(context),
                          onAssistant: () => context.go('/assistant'),
                        ),
                        const SizedBox(height: 8),
                        _CompactEntityList(
                          title: 'Top items',
                          rows: topItemsAsync.maybeWhen(
                            data: (v) => v,
                            orElse: () => const <Map<String, dynamic>>[],
                          ),
                          nameOf: (r) => r['item_name']?.toString() ?? '—',
                          valueOf: (r) =>
                              _inr(((r['total_profit'] as num?) ?? 0).round()),
                          metaOf: (r) => ((r['margin_pct'] as num?) ?? 0) >= 0
                              ? 'up'
                              : 'down',
                        ),
                        const SizedBox(height: 8),
                        _CompactEntityList(
                          title: 'Suppliers',
                          rows: topSuppliersAsync.maybeWhen(
                            data: (v) => v,
                            orElse: () => const <Map<String, dynamic>>[],
                          ),
                          nameOf: (r) => r['supplier_name']?.toString() ?? '—',
                          valueOf: (r) => _inr(
                              ((r['avg_landing'] as num?) ?? 0).round()),
                          metaOf: (r) => ((r['margin_pct'] as num?) ?? 0) >= 8
                              ? 'high margin'
                              : 'best price',
                        ),
                        const SizedBox(height: 8),
                        _CompactEntityList(
                          title: 'Categories',
                          rows: topCategoriesAsync.maybeWhen(
                            data: (v) => v,
                            orElse: () => const <Map<String, dynamic>>[],
                          ),
                          nameOf: (r) => r['category']?.toString() ?? '—',
                          valueOf: (r) =>
                              '${((r['total_qty'] as num?) ?? 0).toStringAsFixed(0)}%',
                          metaOf: (_) => 'share',
                        ),
                        const SizedBox(height: 10),
                        _HeroProfitCard(
                          profitText: _inr(d.totalProfit),
                          changePct: mom,
                          periodLabel: dashboardPeriodLabel(period),
                          rangeCaption: _rangeCaption(period),
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
}

final _homeTopItemsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DashboardPeriod>((ref, period) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final range = dashboardDateRange(period);
  final fmt = DateFormat('yyyy-MM-dd');
  final rows = await ref.read(hexaApiProvider).analyticsItems(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.$1),
        to: fmt.format(range.$2),
      );
  final out = List<Map<String, dynamic>>.from(rows);
  out.sort((a, b) =>
      ((b['total_profit'] as num?) ?? 0).compareTo((a['total_profit'] as num?) ?? 0));
  return out.take(3).toList();
});

final _homeTopSuppliersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DashboardPeriod>((ref, period) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final range = dashboardDateRange(period);
  final fmt = DateFormat('yyyy-MM-dd');
  final rows = await ref.read(hexaApiProvider).analyticsSuppliers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.$1),
        to: fmt.format(range.$2),
      );
  final out = List<Map<String, dynamic>>.from(rows);
  out.sort((a, b) =>
      ((b['total_profit'] as num?) ?? 0).compareTo((a['total_profit'] as num?) ?? 0));
  return out.take(3).toList();
});

final _homeTopCategoriesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DashboardPeriod>((ref, period) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final range = dashboardDateRange(period);
  final fmt = DateFormat('yyyy-MM-dd');
  final rows = await ref.read(hexaApiProvider).analyticsCategories(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.$1),
        to: fmt.format(range.$2),
      );
  final out = List<Map<String, dynamic>>.from(rows);
  out.sort((a, b) =>
      ((b['total_profit'] as num?) ?? 0).compareTo((a['total_profit'] as num?) ?? 0));
  return out.take(3).toList();
});

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

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.ownerName,
    required this.periodLabel,
  });

  final String ownerName;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$ownerName 👋',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
        Text(
          '$periodLabel ▾',
          style: tt.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CompactProfitHead extends StatelessWidget {
  const _CompactProfitHead({
    required this.profitText,
    required this.changePct,
    required this.topItem,
    required this.bestSupplier,
  });

  final String profitText;
  final double? changePct;
  final String? topItem;
  final String? bestSupplier;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final up = (changePct ?? 0) >= 0;
    final pctText = changePct == null ? '' : _formatMomPercent(changePct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              profitText,
              style: tt.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            if (pctText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${up ? '↑' : '↓'} $pctText',
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: up ? HexaColors.profit : HexaColors.loss,
                ),
              ),
            ],
          ],
        ),
        Text(
          'Profit today',
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Top: ${topItem ?? '—'}  •  Best: ${bestSupplier ?? '—'}',
          style: tt.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ThinSparkline extends StatelessWidget {
  const _ThinSparkline({
    required this.trend,
    required this.stroke,
  });

  final AsyncValue<List<AnalyticsDailyProfitPoint>> trend;
  final Color stroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: trend.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => const Center(child: Text('Trend unavailable')),
        data: (pts) {
          if (pts.length < 2) return const Center(child: Text('Add entries'));
          final spots = <FlSpot>[];
          var minY = pts.first.profit;
          var maxY = pts.first.profit;
          for (var i = 0; i < pts.length; i++) {
            final y = pts[i].profit;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            spots.add(FlSpot(i.toDouble(), y));
          }
          final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
          return LineChart(
            LineChartData(
              minY: minY - span * 0.08,
              maxY: maxY + span * 0.08,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: stroke,
                  barWidth: 1.8,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CompactInsightsStrip extends StatelessWidget {
  const _CompactInsightsStrip({
    required this.alerts,
    required this.negativeLines,
  });

  final List<Map<String, dynamic>> alerts;
  final int negativeLines;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final base = <String>[
      if (negativeLines > 0) 'Risk: $negativeLines lines below cost',
      for (final a in alerts.take(4)) (a['message']?.toString() ?? '').trim(),
    ].where((e) => e.isNotEmpty).toList();
    final items = base.isEmpty
        ? <String>['Insight: Keep adding entries to improve recommendations']
        : base;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: HexaColors.primaryLight.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              items[i],
              style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        },
      ),
    );
  }
}

class _SmallActions extends StatelessWidget {
  const _SmallActions({
    required this.onAdd,
    required this.onAssistant,
  });

  final VoidCallback onAdd;
  final VoidCallback onAssistant;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add'),
        ),
        const SizedBox(width: 6),
        TextButton.icon(
          onPressed: onAssistant,
          icon: const Icon(Icons.smart_toy_outlined, size: 18),
          label: const Text('AI'),
        ),
      ],
    );
  }
}

class _CompactEntityList extends StatelessWidget {
  const _CompactEntityList({
    required this.title,
    required this.rows,
    required this.nameOf,
    required this.valueOf,
    required this.metaOf,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) nameOf;
  final String Function(Map<String, dynamic>) valueOf;
  final String Function(Map<String, dynamic>) metaOf;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Text(
            'No data yet',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      nameOf(r),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    valueOf(r),
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    metaOf(r),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
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
        color: cs.surfaceContainerLow,
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

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.onAddEntry,
    required this.onAssistant,
  });

  final VoidCallback onAddEntry;
  final VoidCallback onAssistant;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget tile({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      required Color accent,
    }) {
      return Expanded(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(
          icon: Icons.add_rounded,
          label: 'Add entry',
          onTap: onAddEntry,
          accent: HexaColors.accentInfo,
        ),
        const SizedBox(width: 10),
        tile(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Assistant',
          onTap: onAssistant,
          accent: HexaColors.accentInfo,
        ),
      ],
    );
  }
}

class _HomeChartsPanel extends StatelessWidget {
  const _HomeChartsPanel({
    required this.dash,
    required this.trend,
    required this.inr,
  });

  final DashboardData dash;
  final AsyncValue<List<AnalyticsDailyProfitPoint>> trend;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxBase = [
      dash.totalPurchase.abs(),
      dash.totalProfit.abs(),
      dash.totalQtyBase.abs(),
    ].fold<double>(0, (p, c) => c > p ? c : p);
    final m = maxBase <= 0 ? 1.0 : maxBase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'KPI bars',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _homeBar(context, 'Purchase', dash.totalPurchase / m,
                    inr(dash.totalPurchase.round()), HexaColors.primaryMid),
                _homeBar(context, 'Profit', dash.totalProfit / m,
                    inr(dash.totalProfit.round()), HexaColors.profit),
                _homeBar(context, 'Qty', dash.totalQtyBase / m,
                    dash.totalQtyBase.toStringAsFixed(1), HexaColors.accentAmber),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '7-day profit line',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                trend.when(
                  loading: () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const SizedBox(
                    height: 120,
                    child: Center(child: Text('Could not load trend')),
                  ),
                  data: (pts) {
                    if (pts.length < 2) {
                      return const SizedBox(
                        height: 120,
                        child: Center(child: Text('Add more entries for trend')),
                      );
                    }
                    final spots = <FlSpot>[];
                    var minY = pts.first.profit;
                    var maxY = pts.first.profit;
                    for (var i = 0; i < pts.length; i++) {
                      final y = pts[i].profit;
                      if (y < minY) minY = y;
                      if (y > maxY) maxY = y;
                      spots.add(FlSpot(i.toDouble(), y));
                    }
                    final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
                    return SizedBox(
                      height: 120,
                      child: LineChart(
                        LineChartData(
                          minY: minY - span * 0.08,
                          maxY: maxY + span * 0.08,
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
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (a, b, c, d) =>
                                    FlDotCirclePainter(radius: 2.5, color: HexaColors.primaryNavy),
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
          ),
        ),
      ],
    );
  }

  Widget _homeBar(
    BuildContext context,
    String label,
    double rawPct,
    String value,
    Color color,
  ) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(value,
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: rawPct.clamp(0.0, 1.0),
              minHeight: 7,
              color: color,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMomPercent(double? pct) {
  if (pct == null) return '';
  if (pct.abs() > 999) {
    return pct > 0 ? '↑ new' : '↓ new';
  }
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(1)}%';
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
    final pctLabel = _formatMomPercent(changePct);

    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 88,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
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
                      style: tt.titleLarge?.copyWith(
                        height: 1.0,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.5,
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
            if (changePct != null && pctLabel.isNotEmpty)
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
                    pctLabel,
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
