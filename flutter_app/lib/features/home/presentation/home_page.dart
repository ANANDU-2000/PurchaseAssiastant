import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
                    final empty = d.purchaseCount == 0 && d.totalPurchase <= 0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroProfitCard(
                          profitText: empty ? _inr(0) : _inr(d.totalProfit),
                          changePct: mom,
                          periodLabel: dashboardPeriodLabel(period),
                          rangeCaption: _rangeCaption(period),
                        ),
                        const SizedBox(height: 10),
                        if (empty)
                          _SignalsEmptyState(
                              onAdd: () => showEntryCreateSheet(context))
                        else
                          insights.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            ),
                            error: (_, __) => FriendlyLoadError(
                              message: 'Could not load signals',
                              onRetry: () =>
                                  ref.invalidate(homeInsightsProvider),
                            ),
                            data: (ins) =>
                                _SignalsContent(insights: ins, inr: _inr),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          'Quick actions',
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _QuickActionRow(
                          onAddEntry: () => showEntryCreateSheet(context),
                          onAssistant: () => context.push('/ai'),
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
