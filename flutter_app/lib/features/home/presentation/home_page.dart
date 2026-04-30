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
import '../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/maintenance_payment_provider.dart';
import 'spend_ring_chart.dart';
import 'maintenance_home_card.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

final NumberFormat _qtyIntFmt = NumberFormat.decimalPattern('en_IN');
final NumberFormat _qtyDecFmt = NumberFormat('#,##,##0.#', 'en_IN');

String _fmtQty(double q) =>
    q == q.roundToDouble() ? _qtyIntFmt.format(q.round()) : _qtyDecFmt.format(q);

String _unitWord(String unit, double qty) {
  final upper = unit.toUpperCase();
  if ((upper == 'BAG' || upper == 'BOX' || upper == 'TIN') && qty != 1) {
    return '${upper}S';
  }
  return upper;
}

String _fmtDate(DateTime d) =>
    DateFormat.MMMd().format(d); // e.g. Apr 23

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
      ref.invalidate(homeShellReportsProvider);
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
      ref.invalidate(homeShellReportsProvider);
      ref.invalidate(maintenancePaymentControllerProvider);
      invalidateTradePurchaseCaches(ref);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(homeDashboardDataProvider);
    ref.invalidate(homeShellReportsProvider);
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: MaintenanceHomeCard(),
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
                  categoryColors: _donutColors,
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

  static const _activeBg = Color(0xFF17A8A7);
  static const _inactiveText = Color(0xFF374151);

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _activeBg : const Color(0xFFE8EEEC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _inactiveText,
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

String _kpiUnitsLineUpper(HomeDashboardData data) {
  final tb = data.totalBags;
  final txb = data.totalBoxes;
  final ttn = data.totalTins;
  final tkg = data.totalKg;
  final parts = <String>[];
  if (tb > 1e-9) parts.add('${_fmtQty(tb)} ${_unitWord('BAG', tb)}');
  if (tkg > 1e-9) parts.add('${_fmtQty(tkg)} KG');
  if (txb > 1e-9) parts.add('${_fmtQty(txb)} ${_unitWord('BOX', txb)}');
  if (ttn > 1e-9) parts.add('${_fmtQty(ttn)} ${_unitWord('TIN', ttn)}');
  if (parts.isNotEmpty) return parts.join(' • ');
  return '0 KG';
}

String _primaryUnitsLineUpper(HomeDashboardData data) {
  if (data.totalBags > 1e-9) {
    return '${_fmtQty(data.totalBags)} ${_unitWord('BAG', data.totalBags)}';
  }
  if (data.totalBoxes > 1e-9) {
    return '${_fmtQty(data.totalBoxes)} ${_unitWord('BOX', data.totalBoxes)}';
  }
  if (data.totalTins > 1e-9) {
    return '${_fmtQty(data.totalTins)} ${_unitWord('TIN', data.totalTins)}';
  }
  if (data.totalKg > 1e-9) return '${_fmtQty(data.totalKg)} KG';
  if (data.totalQtyAllLines > 1e-9) {
    return '${_fmtQty(data.totalQtyAllLines)} UNITS';
  }
  return '0 KG';
}

String _secondaryUnitsLineUpper(HomeDashboardData data) {
  final primary = _primaryUnitsLineUpper(data);
  final all = _kpiUnitsLineUpper(data);
  if (primary == all) return '';
  if (data.totalKg > 1e-9 && !primary.endsWith('KG')) {
    return '${_fmtQty(data.totalKg)} KG';
  }
  return all;
}

/// Profit, percent, units, and matching breakdown (for ring + KPI).
List<String> _ringCenterLines(HomeDashboardData d) {
  final p = d.totalProfit;
  final s = p >= 0 ? '' : '−';
  final l1 = 'Profit $s${_inr(p.abs())}';
  final pp = d.profitPercent;
  final l2 = pp == null
      ? '(—)'
      : '(${p >= 0 ? '+' : ''}${pp.toStringAsFixed(1)}%)';
  final l3 = _primaryUnitsLineUpper(d);
  final l4 = _secondaryUnitsLineUpper(d);
  return [l1, l2, l3, l4];
}

String _itemUpperQtyLine(Map<String, dynamic> m) {
  final tb = (m['total_bags'] as num?)?.toDouble() ?? 0;
  final txb = (m['total_boxes'] as num?)?.toDouble() ?? 0;
  final ttn = (m['total_tins'] as num?)?.toDouble() ?? 0;
  final tkg = (m['total_kg'] as num?)?.toDouble() ?? 0;
  final parts = <String>[];
  if (tb > 0) parts.add('${_fmtQty(tb)} BAG');
  if (txb > 0) parts.add('${_fmtQty(txb)} BOX');
  if (ttn > 0) parts.add('${_fmtQty(ttn)} TIN');
  if (tkg > 0) parts.add('${_fmtQty(tkg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  final q = (m['total_qty'] as num?)?.toDouble() ?? 0;
  final u = (m['unit']?.toString() ?? '—').toUpperCase();
  return '${_fmtQty(q)} $u';
}

String _categoryQtyLabel(CategoryStat c) {
  if (c.items.isNotEmpty) {
    final u = c.items.first.unit.trim().toUpperCase();
    if (u.isNotEmpty && u != '—') {
      return '${_fmtQty(c.totalQty)} $u';
    }
  }
  return '${_fmtQty(c.totalQty)} UNITS';
}

const int _kMaxHomeRows = 6;

class _HomeFixedHeaderBody extends ConsumerWidget {
  const _HomeFixedHeaderBody({
    required this.data,
    required this.categoryColors,
  });

  final HomeDashboardData data;
  final List<Color> categoryColors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeBreakdownTabProvider);
    final shell = ref.watch(homeShellReportsProvider);
    final rc = _ringCenterLines(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _KpiTightBlock(data: data),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _HomeBreakdownTabStrip(
            selected: tab,
            onSelect: (t) {
              ref.read(homeBreakdownTabProvider.notifier).state = t;
            },
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _buildRing(
            context,
            tab,
            shell,
            categoryColors,
            rc,
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _buildRowSection(context, tab, shell),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      context.push(
                        '/home/breakdown-more?tab=${tab.name}',
                      );
                    },
                    child: const Text('View more'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRing(
    BuildContext context,
    HomeBreakdownTab tab,
    AsyncValue<HomeShellReportsBundle> shell,
    List<Color> colors,
    List<String> rc,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(280.0, c.maxWidth);
        // Keep layout stable: load ring shell data only for non-category tabs.
        if (tab != HomeBreakdownTab.category && shell.isLoading) {
          return SizedBox(
            height: side,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (tab != HomeBreakdownTab.category && shell.hasError) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Could not load ${tab.label} data',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
        final HomeShellReportsBundle? bundle = tab == HomeBreakdownTab.category
            ? null
            : (shell is AsyncData<HomeShellReportsBundle>
                ? shell.value
                : null);
        final slice = _topSlice(
          data,
          tab,
          bundle,
          _kMaxHomeRows,
        );
        final amts = List<double>.generate(
            slice.length, (i) => slice[i].ringAmount);
        if (slice.isEmpty || amts.isEmpty) {
          return RepaintBoundary(
            child: SpendRingChart(
              diameter: side,
              strokeWidth: 17,
              values: [1],
              colors: [const Color(0xFFCBD5E1)],
              centerLine1: rc[0],
              centerLine2: rc[1],
              centerLine3: rc[2],
              centerLine4: rc[3],
            ),
          );
        }
        return Center(
          child: RepaintBoundary(
            child: SpendRingChart(
              diameter: side,
              strokeWidth: 17,
              values: amts,
              colors: colors,
              centerLine1: rc[0],
              centerLine2: rc[1],
              centerLine3: rc[2],
              centerLine4: rc[3],
              onSectionTap: (i) {
                if (i < 0 || i >= slice.length) return;
                slice[i].onTap(context);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildRowSection(
    BuildContext context,
    HomeBreakdownTab tab,
    AsyncValue<HomeShellReportsBundle> shell,
  ) {
    if (tab != HomeBreakdownTab.category) {
      if (shell.isLoading) {
        return const SizedBox(
          height: 2,
        );
      }
      if (shell.hasError) {
        return const SizedBox.shrink();
      }
    } else {
      if (data.categories.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              'No purchases in this period',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        );
      }
    }
    final HomeShellReportsBundle? bundle = tab == HomeBreakdownTab.category
        ? null
        : (shell is AsyncData<HomeShellReportsBundle> ? shell.value : null);
    final slice = _topSlice(
      data,
      tab,
      bundle,
      _kMaxHomeRows,
    );
    if (slice.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            'No purchases yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < slice.length; i++)
          _HomeBreakdownDataRow(
            title: slice[i].title,
            amount: slice[i].ringAmount,
            boldLine2: slice[i].line2,
            sup: slice[i].sup,
            bro: slice[i].bro,
            dotColor: categoryColors[i % categoryColors.length],
            onTap: () => slice[i].onTap(context),
          ),
      ],
    );
  }
}

class _KpiTightBlock extends StatelessWidget {
  const _KpiTightBlock({required this.data});
  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final primaryUnits = _primaryUnitsLineUpper(data);
    final secondaryUnits = _secondaryUnitsLineUpper(data);
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _inr(data.totalPurchase),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HexaDsType.purchaseLineMoney.copyWith(
                      fontSize: 26,
                      height: 1.08,
                    ),
                  ),
                ),
                Text(
                  primaryUnits,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            if (secondaryUnits.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                secondaryUnits,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeBreakdownTabStrip extends StatelessWidget {
  const _HomeBreakdownTabStrip({
    required this.selected,
    required this.onSelect,
  });
  final HomeBreakdownTab selected;
  final ValueChanged<HomeBreakdownTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final t in HomeBreakdownTab.values) ...[
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Center(
                    child: Text(
                      t.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected == t
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: selected == t
                            ? HexaColors.brandPrimary
                            : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeBreakdownDataRow extends StatelessWidget {
  const _HomeBreakdownDataRow({
    required this.title,
    required this.amount,
    required this.boldLine2,
    required this.sup,
    required this.bro,
    required this.dotColor,
    required this.onTap,
  });
  final String title;
  final double amount;
  final String boldLine2;
  final String sup;
  final String bro;
  final Color dotColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Text(
                    _inr(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 11, height: 1.2),
                    children: [
                      TextSpan(
                        text: boldLine2,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      TextSpan(
                        text: ' · $sup · $bro',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownRowSlice {
  const _BreakdownRowSlice({
    required this.title,
    required this.ringAmount,
    required this.line2,
    required this.sup,
    required this.bro,
    required this.onTap,
  });

  final String title;
  final double ringAmount;
  final String line2;
  final String sup;
  final String bro;
  final void Function(BuildContext context) onTap;
}

List<_BreakdownRowSlice> _topSlice(
  HomeDashboardData d,
  HomeBreakdownTab tab,
  HomeShellReportsBundle? bundle,
  int maxN,
) {
  switch (tab) {
    case HomeBreakdownTab.category:
      final cats = d.categories
          .where((e) => e.totalAmount > 0)
          .toList()
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
      return [
        for (final c in cats.take(maxN))
          _BreakdownRowSlice(
            title: c.categoryName,
            ringAmount: c.totalAmount,
            line2: _categoryQtyLabel(c),
            sup: c.subtitleSupplier?.trim().isNotEmpty == true
                ? c.subtitleSupplier!
                : '—',
            bro: c.subtitleBroker?.trim().isNotEmpty == true
                ? c.subtitleBroker!
                : '—',
            onTap: (ctx) {
              if (c.categoryId == '_uncat') {
                ctx.go('/catalog');
              } else {
                ctx.go('/catalog/category/${c.categoryId}');
              }
            },
          ),
      ];
    case HomeBreakdownTab.subcategory:
      if (bundle == null) return const [];
      final rows = List<Map<String, dynamic>>.from(bundle.subcategories)
        ..sort((a, c) {
          final pa = (a['total_purchase'] as num?)?.toDouble() ?? 0;
          final pc = (c['total_purchase'] as num?)?.toDouble() ?? 0;
          return pc.compareTo(pa);
        });
      return [
        for (final r in rows.take(maxN))
          _BreakdownRowSlice(
            title: () {
              final tn = r['type_name']?.toString().trim() ?? '';
              if (tn.isNotEmpty) return tn;
              return r['category_name']?.toString() ?? '—';
            }(),
            ringAmount: (r['total_purchase'] as num?)?.toDouble() ?? 0,
            line2:
                '${_fmtQty((r['total_qty'] as num?)?.toDouble() ?? 0)} UNITS',
            sup: '—',
            bro: '—',
            onTap: (ctx) => ctx.go('/catalog'),
          ),
      ];
    case HomeBreakdownTab.supplier:
      if (bundle == null) return const [];
      final rows = List<Map<String, dynamic>>.from(bundle.suppliers)
        ..sort((a, c) {
          final pa = (a['total_purchase'] as num?)?.toDouble() ?? 0;
          final pc = (c['total_purchase'] as num?)?.toDouble() ?? 0;
          return pc.compareTo(pa);
        });
      return [
        for (final r in rows.take(maxN))
          _BreakdownRowSlice(
            title: r['supplier_name']?.toString() ?? '—',
            ringAmount: (r['total_purchase'] as num?)?.toDouble() ?? 0,
            line2:
                '${_fmtQty((r['total_qty'] as num?)?.toDouble() ?? 0)} UNITS',
            sup: '—',
            bro: '—',
            onTap: (ctx) {
              final sid = r['supplier_id']?.toString() ?? '';
              if (sid.isNotEmpty) {
                ctx.push('/supplier/$sid');
              }
            },
          ),
      ];
    case HomeBreakdownTab.items:
      if (bundle == null) return const [];
      final rows = List<Map<String, dynamic>>.from(bundle.items)
        ..sort((a, c) {
          final pa = (a['total_purchase'] as num?)?.toDouble() ?? 0;
          final pc = (c['total_purchase'] as num?)?.toDouble() ?? 0;
          return pc.compareTo(pa);
        });
      return [
        for (final r in rows.take(maxN))
          _BreakdownRowSlice(
            title: r['item_name']?.toString() ?? '—',
            ringAmount: (r['total_purchase'] as num?)?.toDouble() ?? 0,
            line2: _itemUpperQtyLine(r),
            sup: '—',
            bro: '—',
            onTap: (ctx) {
              final name = r['item_name']?.toString() ?? '';
              if (name.isEmpty) return;
              ctx.push('/item-analytics/${Uri.encodeComponent(name)}');
            },
          ),
      ];
  }
}

