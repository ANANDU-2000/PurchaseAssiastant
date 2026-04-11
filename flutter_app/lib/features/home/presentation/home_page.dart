import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/dashboard_period_provider.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/home_insights_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../entries/presentation/entry_create_sheet.dart';
import '../../../shared/widgets/app_settings_action.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(minutes: 3), (_) {
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

  String _inr(num n) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

  String _rangeCaption(DashboardPeriod period) {
    final r = dashboardDateRange(period);
    final a = DateFormat.MMMd().format(r.$1);
    final b = DateFormat.MMMd().format(r.$2);
    return '$a – $b, ${r.$2.year}';
  }

  static Future<void> _mediaVoiceSnack(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final r = await ref.read(hexaApiProvider).mediaVoicePreview(businessId: session.primaryBusiness.id);
      if (!context.mounted) return;
      final note = r['note']?.toString() ?? 'Voice preview';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Voice preview: $e')));
      }
    }
  }

  static Future<void> _mediaOcrSnack(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final r = await ref.read(hexaApiProvider).mediaOcrPreview(businessId: session.primaryBusiness.id);
      if (!context.mounted) return;
      final note = r['note']?.toString() ?? 'OCR preview';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR preview: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final period = ref.watch(dashboardPeriodProvider);
    final dash = ref.watch(dashboardProvider);
    final insights = ref.watch(homeInsightsProvider);
    final hi = insights.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        leading: ModalRoute.of(context)?.canPop == true
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppSettingsAction(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 80,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Decision snapshot',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: DashboardPeriod.values.map((p) {
                          final sel = period == p;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(dashboardPeriodLabel(p)),
                              selected: sel,
                              onSelected: (_) {
                                ref.read(dashboardPeriodProvider.notifier).state = p;
                                ref.invalidate(dashboardProvider);
                                ref.invalidate(homeInsightsProvider);
                              },
                              selectedColor: cs.primary,
                              labelStyle: TextStyle(
                                color: sel ? Colors.white : cs.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              sliver: SliverToBoxAdapter(
                child: dash.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Could not load dashboard', style: tt.titleSmall),
                          const SizedBox(height: 8),
                          Text(e.toString(), style: tt.bodySmall?.copyWith(color: cs.error)),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => ref.invalidate(dashboardProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (d) {
                    final marginPct = d.totalPurchase > 0 ? (d.totalProfit / d.totalPurchase) * 100.0 : null;
                    final mom = hi?.profitChangePctPriorMtd;
                    final empty = d.purchaseCount == 0 && d.totalPurchase <= 0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _rangeCaption(period),
                          style: tt.labelLarge?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        _HeroProfitCard(
                          profitText: _inr(d.totalProfit),
                          profitValue: d.totalProfit,
                          changePct: mom,
                          subtitle: '${dashboardPeriodLabel(period)} · pull to refresh',
                        ),
                        const SizedBox(height: 16),
                        if (empty)
                          _DashboardEmptyCta(onAdd: () => showEntryCreateSheet(context))
                        else ...[
                          Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  label: 'Purchase',
                                  value: _inr(d.totalPurchase),
                                  tone: _MetricTone.cost,
                                  marginValue: null,
                                  icon: Icons.shopping_bag_outlined,
                                  iconColor: const Color(0xFF2563EB),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  label: 'Profit',
                                  value: _inr(d.totalProfit),
                                  tone: _MetricTone.profit,
                                  marginValue: null,
                                  icon: Icons.trending_up_rounded,
                                  iconColor: HexaColors.profit,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  label: 'Margin',
                                  value: marginPct != null ? '${marginPct.toStringAsFixed(1)}%' : '—',
                                  tone: _MetricTone.margin,
                                  marginValue: marginPct,
                                  icon: Icons.pie_chart_outline_rounded,
                                  iconColor: HexaColors.accentAmber,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  label: 'Purchases',
                                  value: d.purchaseCount.toString(),
                                  tone: _MetricTone.neutral,
                                  marginValue: null,
                                  icon: Icons.receipt_long_rounded,
                                  iconColor: HexaColors.primaryMid,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  label: 'Qty (base)',
                                  value: d.totalQtyBase.toStringAsFixed(1),
                                  tone: _MetricTone.neutral,
                                  marginValue: null,
                                  icon: Icons.scale_rounded,
                                  iconColor: const Color(0xFF7C3AED),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  label: 'Avg / purchase',
                                  value: d.purchaseCount > 0 ? _inr(d.totalProfit / d.purchaseCount) : '—',
                                  tone: _MetricTone.neutral,
                                  marginValue: null,
                                  icon: Icons.analytics_outlined,
                                  iconColor: const Color(0xFFEA580C),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (hi != null &&
                            (hi.topItem != null ||
                                hi.worstItem != null ||
                                hi.bestSupplierName != null ||
                                hi.alerts.isNotEmpty)) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Icon(Icons.notifications_active_outlined, size: 22, color: cs.primary),
                              const SizedBox(width: 8),
                              Text('Insights & alerts', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (hi.negativeLineCount > 0)
                            _AlertSummaryCard(
                              count: hi.negativeLineCount,
                              title: 'Lines with loss',
                              body: 'Review selling vs landing on these rows.',
                            ),
                          if (hi.topItem != null)
                            _InsightTile(
                              icon: Icons.emoji_events_rounded,
                              iconColor: HexaColors.warning,
                              title: 'Top item',
                              name: hi.topItem!,
                              amount: hi.topItemProfit ?? 0,
                            ),
                          if (hi.worstItem != null &&
                              hi.worstItemProfit != null &&
                              (hi.worstItem != hi.topItem || hi.worstItemProfit! < 0)) ...[
                            const SizedBox(height: 8),
                            _InsightTile(
                              icon: Icons.trending_down_rounded,
                              iconColor: HexaColors.loss,
                              title: 'Needs attention',
                              name: hi.worstItem!,
                              amount: hi.worstItemProfit!,
                              valueColor: hi.worstItemProfit! < 0 ? HexaColors.loss : HexaColors.warning,
                            ),
                          ],
                          if (hi.bestSupplierName != null) ...[
                            const SizedBox(height: 8),
                            _InsightTile(
                              icon: Icons.storefront_rounded,
                              iconColor: HexaColors.brand,
                              title: 'Best supplier',
                              name: hi.bestSupplierName!,
                              amount: hi.bestSupplierProfit ?? 0,
                            ),
                          ],
                          for (final a in hi.alerts) ...[
                            const SizedBox(height: 8),
                            _AlertMessageCard(
                              message: a['message']?.toString() ?? 'Alert',
                              severity: a['severity']?.toString() ?? 'info',
                            ),
                          ],
                        ],
                        const SizedBox(height: 24),
                        Text('Quick actions', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        _QuickActions(
                          onAddEntry: () => showEntryCreateSheet(context),
                          onViewEntries: () => context.go('/entries'),
                          onCatalog: () => context.push('/catalog'),
                          onReports: () => context.go('/analytics'),
                          onVoice: () => unawaited(_mediaVoiceSnack(context, ref)),
                          onScan: () => unawaited(_mediaOcrSnack(context, ref)),
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
    );
  }
}

class _HeroProfitCard extends StatelessWidget {
  const _HeroProfitCard({
    required this.profitText,
    required this.profitValue,
    required this.changePct,
    required this.subtitle,
  });

  final String profitText;
  final double profitValue;
  final double? changePct;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final up = changePct != null && changePct! >= 0;
    final trendColor = changePct == null
        ? Colors.white.withValues(alpha: 0.85)
        : (up ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HexaColors.primaryDeep,
            HexaColors.primaryMid,
            HexaColors.heroGradientEnd,
          ],
          stops: [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: HexaColors.primaryMid.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_rounded, color: Colors.white.withValues(alpha: 0.92), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Total profit',
                  style: tt.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              profitText,
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 40,
                height: 1.05,
                color: profitValue == 0 ? Colors.white.withValues(alpha: 0.95) : Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
              ),
            ),
            if (changePct != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 18,
                          color: trendColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${up ? '+' : ''}${changePct!.toStringAsFixed(1)}% vs last month MTD',
                          style: tt.labelLarge?.copyWith(
                            color: trendColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MetricTone { cost, profit, margin, warning, neutral }

class _DashboardEmptyCta extends StatelessWidget {
  const _DashboardEmptyCta({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.receipt_long_rounded, size: 48, color: cs.primary),
            const SizedBox(height: 12),
            Text('No purchases in this range', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Add your first purchase or pick another date chip above.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add first purchase'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.tone,
    required this.marginValue,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String value;
  final _MetricTone tone;
  final double? marginValue;
  final IconData? icon;
  final Color? iconColor;

  Color _accent(bool dark) {
    switch (tone) {
      case _MetricTone.cost:
        return HexaColors.cost;
      case _MetricTone.profit:
        return HexaColors.profit;
      case _MetricTone.margin:
        final m = marginValue ?? 0;
        return m >= 0 ? HexaColors.profit : HexaColors.loss;
      case _MetricTone.warning:
        return HexaColors.warning;
      case _MetricTone.neutral:
        return HexaColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(dark);

    return Material(
      color: Theme.of(context).cardTheme.color,
      elevation: Theme.of(context).cardTheme.elevation ?? 0,
      shadowColor: Theme.of(context).cardTheme.shadowColor,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HexaColors.border.withValues(alpha: dark ? 0.25 : 0.7)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                if (icon != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (iconColor ?? accent).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: iconColor ?? accent),
                  ),
                if (icon != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      color: HexaColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertSummaryCard extends StatelessWidget {
  const _AlertSummaryCard({required this.count, required this.title, required this.body});

  final int count;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HexaColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HexaColors.warning.withValues(alpha: 0.35)),
        boxShadow: HexaColors.cardShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: HexaColors.warning, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count $title',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(body, style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.name,
    required this.amount,
    this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String name;
  final double amount;
  /// When null, green if [amount] ≥ 0 else red.
  final Color? valueColor;

  String _fmt(num n) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final amtColor = valueColor ?? (amount >= 0 ? HexaColors.profit : HexaColors.loss);
    return Material(
      color: Theme.of(context).cardTheme.color,
      elevation: Theme.of(context).cardTheme.elevation ?? 0,
      shadowColor: Theme.of(context).cardTheme.shadowColor,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w600)),
                  Text(name, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Text(
              '${amount >= 0 ? '+' : ''}${_fmt(amount)}',
              style: tt.titleMedium?.copyWith(color: amtColor, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertMessageCard extends StatelessWidget {
  const _AlertMessageCard({required this.message, required this.severity});

  final String message;
  final String severity;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isWarn = severity == 'warning';
    return Material(
      color: isWarn ? HexaColors.loss.withValues(alpha: 0.08) : HexaColors.primaryLight.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isWarn ? HexaColors.loss.withValues(alpha: 0.25) : HexaColors.primaryMid.withValues(alpha: 0.2),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isWarn ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: isWarn ? HexaColors.loss : HexaColors.primaryMid,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: tt.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddEntry,
    required this.onViewEntries,
    required this.onCatalog,
    required this.onReports,
    required this.onVoice,
    required this.onScan,
  });

  final VoidCallback onAddEntry;
  final VoidCallback onViewEntries;
  final VoidCallback onCatalog;
  final VoidCallback onReports;
  final VoidCallback onVoice;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    Widget chip({required IconData icon, required String label, required VoidCallback onTap, bool primary = false}) {
      final child = primary
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [HexaColors.primaryDeep, HexaColors.primaryMid],
                ),
                boxShadow: [
                  BoxShadow(
                    color: HexaColors.primaryMid.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: tt.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 20),
              label: Text(label),
            );

      return primary
          ? child
          : SizedBox(width: double.infinity, child: child);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PressScale(
          child: chip(
            icon: Icons.add_rounded,
            label: 'Add entry',
            onTap: onAddEntry,
            primary: true,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionChipButton(icon: Icons.mic_rounded, label: 'Voice', onTap: onVoice),
            _ActionChipButton(icon: Icons.document_scanner_outlined, label: 'Scan bill', onTap: onScan),
            _ActionChipButton(icon: Icons.insights_outlined, label: 'Reports', onTap: onReports),
            _ActionChipButton(icon: Icons.receipt_long_outlined, label: 'History', onTap: onViewEntries),
            _ActionChipButton(icon: Icons.inventory_2_outlined, label: 'Catalog', onTap: onCatalog),
          ],
        ),
      ],
    );
  }
}

class _ActionChipButton extends StatefulWidget {
  const _ActionChipButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ActionChipButton> createState() => _ActionChipButtonState();
}

class _ActionChipButtonState extends State<_ActionChipButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? cs.primary.withValues(alpha: 0.08) : cs.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: _hover ? 1.0 : 0.7)),
              boxShadow: _hover
                  ? [
                      BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});

  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
