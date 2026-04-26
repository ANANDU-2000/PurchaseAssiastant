import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/config/app_config.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/cloud_expense_provider.dart';
import '../../../core/providers/purchase_post_save_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';
import '../../purchase/presentation/widgets/purchase_saved_sheet.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import 'spend_ring_chart.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);

String _fmtDate(DateTime d) =>
    DateFormat.MMMd().format(d); // e.g. Apr 23

String _periodCenterLabel(HomePeriod p) => switch (p) {
      HomePeriod.today => 'Today',
      HomePeriod.week => 'This week',
      HomePeriod.month => 'This month',
      HomePeriod.year => 'This year',
      HomePeriod.custom => 'Selected range',
    };

/// Purchase + item flow only — no revenue/profit finance cards.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  Timer? _poll;
  /// Debounced: resume must not mass-invalidate [FutureProvider]s while
  /// in-flight requests complete (avoids defunct element / markNeedsBuild).
  Timer? _resumeRefreshDebounce;
  bool _handlingPurchasePostSave = false;

  static const _donutColors = <Color>[
    Color(0xFF0D9488),
    Color(0xFF6366F1),
    Color(0xFFEA580C),
    Color(0xFF7C3AED),
    Color(0xFF0EA5E9),
    Color(0xFFDB2777),
    Color(0xFFCA8A04),
    Color(0xFF16A34A),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!mounted) return;
      ref.invalidate(homeDashboardDataProvider);
      invalidateTradePurchaseCaches(ref);
      invalidateBusinessAggregates(ref);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _resumeRefreshDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) return;
    _resumeRefreshDebounce?.cancel();
    // Let pending Dio/interceptor work and the frame settle; only refresh
    // dashboard + purchase lists here. Full [invalidateBusinessAggregates] on
    // resume can stampede 10+ refetches and race disposed providers on web.
    _resumeRefreshDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      ref.invalidate(homeDashboardDataProvider);
      invalidateTradePurchaseCaches(ref);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(homeDashboardDataProvider);
    invalidateTradePurchaseCaches(ref);
    invalidateBusinessAggregates(ref);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final prev = ref.read(homeCustomDateRangeProvider);
    final initial = prev != null
        ? DateTimeRange(start: prev.start, end: prev.endInclusive)
        : DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          );
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (!mounted || r == null) return;
    ref.read(homePeriodProvider.notifier).state = HomePeriod.custom;
    ref.read(homeCustomDateRangeProvider.notifier).state = (
      start: r.start,
      endInclusive: r.end,
    );
  }

  void _selectPeriod(HomePeriod p) {
    ref.read(homePeriodProvider.notifier).state = p;
    if (p != HomePeriod.custom) {
      ref.read(homeCustomDateRangeProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _handlePurchasePostSave();

    final period = ref.watch(homePeriodProvider);
    final custom = ref.watch(homeCustomDateRangeProvider);
    final async = ref.watch(homeDashboardDataProvider);
    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _PeriodStrip(
                selected: period,
                custom: custom,
                onSelect: _selectPeriod,
                onPickCustom: _pickCustomRange,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const LinearProgressIndicator(minHeight: 3),
                error: (_, __) => FriendlyLoadError(
                  message: 'Unable to load cloud data',
                  onRetry: () => unawaited(_refresh()),
                ),
                data: (_) => const SizedBox.shrink(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Consumer(
                builder: (context, ref, _) {
                  final cc = ref.watch(cloudCostProvider);
                  return cc.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (m) {
                      if (m.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final showCard = m['show_home_card'] != false;
                      if (!showCard) {
                        return const SizedBox.shrink();
                      }
                      final name = m['name']?.toString() ?? 'Cloud Cost';
                      final amt = (m['amount_inr'] as num?)?.toDouble() ?? 0;
                      final next = m['next_due_date']?.toString() ?? '—';
                      final needPay = m['show_alert'] == true;
                      final inPre = m['in_pre_due_window'] == true;
                      final iconColor = needPay
                          ? const Color(0xFFDC2626)
                          : (inPre
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF16A34A));
                      Future<void> markPaid() async {
                        final s = ref.read(sessionProvider);
                        if (s == null) return;
                        try {
                          await ref.read(hexaApiProvider).postCloudCostPay(
                                businessId: s.primaryBusiness.id,
                                provider: 'manual',
                              );
                          if (!context.mounted) return;
                          ref.invalidate(cloudCostProvider);
                          invalidateBusinessAggregates(ref);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(friendlyApiError(e))),
                          );
                        }
                      }

                      Future<void> openUpi() async {
                        if (AppConfig.cloudUpiVpa.isEmpty) return;
                        final uri = Uri.parse(
                          'upi://pay?pa=${Uri.encodeComponent(AppConfig.cloudUpiVpa)}'
                          '&pn=${Uri.encodeComponent(AppConfig.cloudUpiPayeeName)}'
                          '&am=${amt.toStringAsFixed(0)}'
                          '&cu=INR',
                        );
                        if (!await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Could not open a UPI app. Try again or pay manually.')),
                          );
                        }
                      }

                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.cloud_outlined,
                                    size: 18,
                                    color: iconColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          needPay
                                              ? 'Overdue · due $next'
                                              : (inPre
                                                  ? 'Due soon · $next'
                                                  : 'Due $next'),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: HexaColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Rs. ${amt.round()}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                alignment: WrapAlignment.end,
                                children: [
                                  if (AppConfig.cloudUpiVpa.isNotEmpty)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: openUpi,
                                      child: const Text('UPI',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  if (needPay || inPre)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: markPaid,
                                      child: const Text('Mark paid',
                                          style: TextStyle(fontSize: 12)),
                                    )
                                  else
                                    Text(
                                      'Paid up',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
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
            Expanded(
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _LoadingPlaceholder(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (d) => _HomeFixedHeaderBody(
                  data: d,
                  period: period,
                  categoryColors: _donutColors,
                  listBottomPadding: 8 + viewBottom,
                  onRefresh: _refresh,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePurchasePostSave() {
    final postSave = ref.watch(purchasePostSaveProvider);
    if (postSave == null || _handlingPurchasePostSave) return;
    _handlingPurchasePostSave = true;
    final payload = postSave;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _handlingPurchasePostSave = false;
        return;
      }
      ref.read(purchasePostSaveProvider.notifier).state = null;
      _handlingPurchasePostSave = false;
      final route = await showPurchaseSavedSheet(
        context,
        ref,
        savedJson: payload.savedJson,
        wasEdit: payload.wasEdit,
      );
      if (!mounted) return;
      final sid = payload.savedJson['id']?.toString();
      if (route == 'detail' && sid != null && sid.isNotEmpty) {
        context.go('/purchase/detail/$sid');
      }
    });
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: HexaColors.brandBackground,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      title: const SizedBox.shrink(),
      actions: [
        ShellQuickRefActions(onRefresh: _refresh),
      ],
    );
  }
}

class _PeriodStrip extends StatelessWidget {
  const _PeriodStrip({
    required this.selected,
    required this.custom,
    required this.onSelect,
    required this.onPickCustom,
  });

  final HomePeriod selected;
  final ({DateTime start, DateTime endInclusive})? custom;
  final ValueChanged<HomePeriod> onSelect;
  final VoidCallback onPickCustom;

  static const _chips = <HomePeriod>[
    HomePeriod.today,
    HomePeriod.week,
    HomePeriod.month,
    HomePeriod.year,
  ];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in _chips) ...[
                _PeriodChip(
                  label: p.label,
                  selected: selected == p,
                  onTap: () => onSelect(p),
                ),
                const SizedBox(width: 8),
              ],
              IconButton.filledTonal(
                tooltip: 'Custom dates',
                onPressed: onPickCustom,
                icon: const Icon(Icons.date_range_rounded, size: 22),
              ),
            ],
          ),
        ),
        if (selected == HomePeriod.custom) ...[
          if (custom case final c?) ...[
            const SizedBox(height: 6),
            Text(
              '${_fmtDate(c.start)} – ${_fmtDate(c.endInclusive)}',
              style: tt.labelMedium?.copyWith(
                color: HexaColors.brandPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? HexaColors.brandPrimary : const Color(0xFFE8EEEC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF475569),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 14,
              width: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 8),
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _kpiUnitsLine(HomeDashboardData data) {
  final parts = <String>[];
  if (data.totalBags > 0) parts.add('${_fmtQty(data.totalBags)} bag');
  if (data.totalBoxes > 0) parts.add('${_fmtQty(data.totalBoxes)} box');
  if (data.totalTins > 0) parts.add('${_fmtQty(data.totalTins)} tin');
  if (data.totalKg > 0) parts.add('${_fmtQty(data.totalKg)} kg');
  return parts.join(' · ');
}

class _HomeFixedHeaderBody extends ConsumerWidget {
  const _HomeFixedHeaderBody({
    required this.data,
    required this.period,
    required this.categoryColors,
    required this.listBottomPadding,
    required this.onRefresh,
  });

  final HomeDashboardData data;
  final HomePeriod period;
  final List<Color> categoryColors;
  final double listBottomPadding;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slice = data.categories.where((e) => e.totalAmount > 0).toList();
    final amts = List<double>.generate(slice.length, (i) => slice[i].totalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _HomeKpiBlock(data: data, period: period),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (context, c) {
              final side = math.min(300.0, c.maxWidth);
              if (slice.isEmpty || amts.every((a) => a <= 0)) {
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: side, maxHeight: side),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Center(
                        child: Text(
                          'No category spend in this period',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: RepaintBoundary(
                  child: SpendRingChart(
                    diameter: side,
                    strokeWidth: 17,
                    values: amts,
                    colors: categoryColors,
                    centerLine1: _inr(data.totalPurchase),
                    centerLine2: '${data.totalQtyAllLines.round()} units',
                    centerLine3: _kpiUnitsLine(data).isNotEmpty
                        ? _kpiUnitsLine(data)
                        : null,
                    onSectionTap: (i) {
                      if (i < 0 || i >= slice.length) return;
                      final cat = slice[i];
                      if (cat.categoryId == '_uncat') {
                        context.go('/catalog');
                      } else {
                        context.go('/catalog/category/${cat.categoryId}');
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: _ProfitBlock(data: data),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: HexaColors.brandPrimary,
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 0, 16, listBottomPadding),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: data.categories.isEmpty ? 1 : data.categories.length,
              itemBuilder: (context, index) {
                if (data.categories.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No purchases in this period',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }
                final stat = data.categories[index];
                return _CategoryRow(
                  stat: stat,
                  dotColor: categoryColors[index % categoryColors.length],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeKpiBlock extends StatelessWidget {
  const _HomeKpiBlock({required this.data, required this.period});
  final HomeDashboardData data;
  final HomePeriod period;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final q = data.totalQtyAllLines;
    final sub = period == HomePeriod.month
        ? 'This month'
        : _periodCenterLabel(period);
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Total spend',
              style: HexaDsType.label(12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 2),
            Text(
              _inr(data.totalPurchase),
              style: HexaDsType.purchaseLineMoney.copyWith(
                fontSize: 28,
                height: 1.12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: tt.labelSmall?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmtQty(q)} units',
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            if (_kpiUnitsLine(data).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _kpiUnitsLine(data),
                style: tt.labelSmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfitBlock extends StatelessWidget {
  const _ProfitBlock({required this.data});
  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final s = data.totalSelling;
    final l = data.totalLanding > 0 ? data.totalLanding : data.totalPurchase;
    final p = data.totalProfit;
    final pp = data.profitPercent;
    if (s < 1e-6) {
      return Text(
        'Add selling on lines to see profit',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profitRow('Landing', _inr(l)),
        const SizedBox(height: 2),
        _profitRow('Selling', _inr(s)),
        const SizedBox(height: 2),
        _profitRow(
          'Profit',
          '${p >= 0 ? '' : '−'}${_inr(p.abs())}${pp != null ? '  (${p >= 0 ? '+' : ''}${pp.toStringAsFixed(1)}%)' : ''}',
        ),
      ],
    );
  }

  Widget _profitRow(String k, String v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          k,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

String _categoryQtyLabel(CategoryStat c) {
  if (c.items.isNotEmpty) {
    final u = c.items.first.unit.trim();
    if (u.isNotEmpty && u != '—') {
      return '${_fmtQty(c.totalQty)} $u';
    }
  }
  return '${_fmtQty(c.totalQty)} units';
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.stat, required this.dotColor});
  final CategoryStat stat;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final sup = (stat.subtitleSupplier == null || stat.subtitleSupplier!.isEmpty)
        ? '—'
        : stat.subtitleSupplier!;
    final bro = (stat.subtitleBroker == null || stat.subtitleBroker!.isEmpty)
        ? '—'
        : stat.subtitleBroker!;
    final sub = '${_categoryQtyLabel(stat)} · $sup · $bro';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (stat.categoryId == '_uncat') {
            context.go('/catalog');
          } else {
            context.go('/catalog/category/${stat.categoryId}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      stat.categoryName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                      ),
                    ),
                  ),
                  Text(
                    _inr(stat.totalAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: HexaColors.brandPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

