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
import '../../../core/providers/reports_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches, invalidateTradePurchaseCachesFromContainer;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/feature_flags.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';
import '../../purchase/presentation/widgets/purchase_saved_sheet.dart';
import '../../purchase/presentation/widgets/resume_purchase_draft_banner.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/maintenance_payment_provider.dart';
import '../../../core/navigation/open_trade_item_from_report.dart';
import '../../../widgets/spend_ring_chart.dart';
import 'maintenance_home_card.dart';
import 'home_spend_ring_diameter.dart';
import '../home_pack_unit_word.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

final NumberFormat _qtyIntFmt = NumberFormat.decimalPattern('en_IN');
final NumberFormat _qtyDecFmt = NumberFormat('#,##,##0.#', 'en_IN');

String _fmtQty(double q) =>
    q == q.roundToDouble() ? _qtyIntFmt.format(q.round()) : _qtyDecFmt.format(q);

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
  DateTime? _lastFullInvalidate;
  bool _handlingPurchasePostSave = false;
  Timer? _dashRefreshGuardTimer;
  Timer? _loadCapTimer;
  bool _loadCapReached = false;
  bool _shownPersistDashboardSnack = false;

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
      if (_resumeRefreshDebounce?.isActive == true) return;
      final last = _lastFullInvalidate;
      if (last != null && DateTime.now().difference(last).inMinutes < 2) return;
      _lastFullInvalidate = DateTime.now();
      bustHomeDashboardVolatileCaches();
      invalidateTradePurchaseCaches(ref);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _resumeRefreshDebounce?.cancel();
    _dashRefreshGuardTimer?.cancel();
    _loadCapTimer?.cancel();
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
      _lastFullInvalidate = DateTime.now();
      ref.invalidate(homeDashboardDataProvider);
      ref.invalidate(homeShellReportsProvider);
      ref.invalidate(maintenancePaymentControllerProvider);
      invalidateTradePurchaseCaches(ref);
    });
  }

  Future<void> _refresh() async {
    _lastFullInvalidate = DateTime.now();
    ref.invalidate(homeDashboardDataProvider);
    ref.invalidate(homeShellReportsProvider);
    invalidateTradePurchaseCaches(ref);
    // Avoid a full aggregate stampede on pull-to-refresh; targeted invalidation
    // keeps the UI responsive and prevents request storms on weaker networks.
    ref.invalidate(reportsPurchasesPayloadProvider);
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
    ref.listen<PurchasePostSavePayload?>(purchasePostSaveProvider, (prev, next) {
      if (next == null || _handlingPurchasePostSave) return;
      _handlingPurchasePostSave = true;
      unawaited(_doHandlePurchasePostSave(next));
    });

    final period = ref.watch(homePeriodProvider);
    final custom = ref.watch(homeCustomDateRangeProvider);
    final async = ref.watch(homeDashboardDataProvider);
    final peek = ref.watch(homeDashboardSyncCacheProvider);
    final pay = async.snapshot;
    final effectiveData = pay.data.isEmpty ? (peek ?? pay.data) : pay.data;

    ref.listen<HomeDashboardDashState>(
      homeDashboardDataProvider,
      (prev, next) {
        if (next.refreshing) {
          if (prev?.refreshing != true) {
            _dashRefreshGuardTimer?.cancel();
            _dashRefreshGuardTimer = Timer(const Duration(seconds: 6), () {
              if (!mounted) {
                _dashRefreshGuardTimer = null;
                return;
              }
              _dashRefreshGuardTimer = null;
              try {
                ref.read(homeDashboardDataProvider.notifier).forceStopRefreshing();
              } catch (_) {}
            });
          }
          return;
        }
        _dashRefreshGuardTimer?.cancel();
        _dashRefreshGuardTimer = null;
        _loadCapTimer?.cancel();
        _loadCapTimer = null;
        if (mounted && _loadCapReached) {
          setState(() => _loadCapReached = false);
        }
        final p = next.snapshot;
        if (!p.persistAlert) {
          _shownPersistDashboardSnack = false;
          return;
        }
        if (_shownPersistDashboardSnack) return;
        _shownPersistDashboardSnack = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Still having trouble reaching the server. Showing saved data.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 5),
            ),
          );
        });
      },
    );

    final shellSkeleton =
        async.refreshing && peek == null && pay.data.isEmpty;

    if (shellSkeleton && !_loadCapReached) {
      _loadCapTimer ??= Timer(const Duration(seconds: 6), () {
        if (!mounted) {
          _loadCapTimer = null;
          return;
        }
        try {
          ref.read(homeDashboardDataProvider.notifier).forceStopRefreshing();
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _loadCapReached = true;
          _loadCapTimer = null;
        });
      });
    } else if (!shellSkeleton ||
        _loadCapReached ||
        peek != null ||
        !pay.data.isEmpty) {
      _loadCapTimer?.cancel();
      _loadCapTimer = null;
    }

    final topBanner = pay.banner ??
        ((_loadCapReached && shellSkeleton) ? 'Server waking up...' : null);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        bottom: true,
        child: LayoutBuilder(
          builder: (context, viewport) {
            final h = viewport.maxHeight;
            final headerCap = h.isFinite
                ? (h * 0.48).clamp(160.0, 520.0)
                : 320.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: headerCap),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ResumePurchaseDraftBanner(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _HomeTraderPriorityStrip(
                pendingDeliveryCount: effectiveData.pendingDeliveryCount,
                purchaseCount: effectiveData.purchaseCount,
                totalPurchase: effectiveData.totalPurchase,
                selectedPeriod: period,
                onJumpToday: () => _selectPeriod(HomePeriod.today),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _HomeCloudCostCard(),
            ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (async.refreshing)
                    const LinearProgressIndicator(minHeight: 3),
                  if (topBanner != null)
                    Material(
                      color: Colors.amber.shade50,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                topBanner,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => unawaited(_refresh()),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (FeatureFlags.showMaintenanceFeeCard)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: MaintenanceHomeCard(),
              ),
                      ],
                    ),
                  ),
                ),
                Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  // Web + nested Scaffold: without [Positioned.fill], [Stack] can pass
                  // loose vertical constraints; [Column] + inner [Expanded] then lays out
                  // with zero height and the home body appears blank (shell nav still shows).
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: _HomeFixedHeaderBody(
                        data: effectiveData,
                        categoryColors: _donutColors,
                        paintShellSkeleton: shellSkeleton,
                        dashboardRefreshing: async.refreshing,
                        homePeriod: period,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: FloatingActionButton.small(
                      heroTag: 'home_add_item',
                      tooltip: 'Add Item',
                      onPressed: () =>
                          context.pushNamed('catalog_quick_add'),
                      child: const Icon(Icons.inventory_2_outlined),
                    ),
                  ),
                ],
              ),
            ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _doHandlePurchasePostSave(PurchasePostSavePayload payload) async {
    try {
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(homeDashboardDataProvider);
      container.invalidate(homeShellReportsProvider);
      container.invalidate(reportsPurchasesPayloadProvider);
      invalidateTradePurchaseCachesFromContainer(container);
      container.read(purchasePostSaveProvider.notifier).state = null;
      if (!mounted) return;
      final route = await showPurchaseSavedSheet(
        context,
        ref,
        savedJson: payload.savedJson,
        wasEdit: payload.wasEdit,
      );
      if (!mounted) return;
      final sid = payload.savedJson['id']?.toString();
      if (route == 'edit_missing' && sid != null && sid.isNotEmpty) {
        context.go('/purchase/edit/$sid');
      } else if (route == 'detail' && sid != null && sid.isNotEmpty) {
        context.go('/purchase/detail/$sid');
      }
    } finally {
      _handlingPurchasePostSave = false;
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: HexaColors.brandBackground,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      title: Text(
        AppConfig.appName,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 17,
          letterSpacing: -0.2,
          color: Color(0xFF0F172A),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'New supplier',
          icon: const Icon(Icons.storefront_outlined),
          onPressed: () => context.pushNamed('supplier_quick_create'),
        ),
        IconButton(
          tooltip: 'New broker',
          icon: const Icon(Icons.handshake_outlined),
          onPressed: () => context.pushNamed('broker_quick_create'),
        ),
        IconButton(
          tooltip: 'Scan bill',
          icon: const Icon(Icons.document_scanner_outlined),
          onPressed: () => context.pushNamed('purchase_scan'),
        ),
        ShellQuickRefActions(onRefresh: _refresh, suppressToolbarSearch: true),
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

String _kpiUnitsLineUpper(HomeDashboardData data) {
  return _kpiUnitsLineUpperFromTotals(
    bags: data.totalBags,
    boxes: data.totalBoxes,
    tins: data.totalTins,
    kg: data.totalKg,
  );
}

String _kpiUnitsLineUpperFromTotals({
  required double bags,
  required double boxes,
  required double tins,
  required double kg,
}) {
  final parts = <String>[];
  if (bags > 1e-9) {
    parts.add('${_fmtQty(bags)} ${homePackUnitWord('BAG', bags)}');
  }
  if (boxes > 1e-9) {
    parts.add('${_fmtQty(boxes)} ${homePackUnitWord('BOX', boxes)}');
  }
  if (tins > 1e-9) {
    parts.add('${_fmtQty(tins)} ${homePackUnitWord('TIN', tins)}');
  }
  if (kg > 1e-9) parts.add('${_fmtQty(kg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  return '';
}

String _primaryUnitsLineUpper(HomeDashboardData data) {
  return _kpiUnitsLineUpper(data);
}

String _secondaryUnitsLineUpper(HomeDashboardData data) {
  return '';
}

({double bags, double boxes, double tins, double kg})? _unitTotalsFromHomeShell(
  HomeShellReportsBundle? shell,
) {
  if (shell == null || shell.items.isEmpty) return null;
  double bags = 0, boxes = 0, tins = 0, kg = 0;
  for (final m in shell.items) {
    bags += coerceToDouble(m['total_bags']);
    boxes += coerceToDouble(m['total_boxes']);
    tins += coerceToDouble(m['total_tins']);
    kg += coerceToDouble(m['total_kg']);
  }
  if (bags.abs() < 1e-9 &&
      boxes.abs() < 1e-9 &&
      tins.abs() < 1e-9 &&
      kg.abs() < 1e-9) {
    return null;
  }
  return (bags: bags, boxes: boxes, tins: tins, kg: kg);
}

/// Profit, percent, units, and matching breakdown (for ring + KPI).
List<String> _ringCenterLines(
  HomeDashboardData d, {
  ({double bags, double boxes, double tins, double kg})? unitsOverride,
}) {
  final p = d.totalProfit;
  final s = p >= 0 ? '' : '−';
  final l1 = 'Profit $s${_inr(p.abs())}';
  final pp = d.profitPercent;
  final l2 = pp == null
      ? '(—)'
      : '(${p >= 0 ? '+' : ''}${pp.toStringAsFixed(1)}%)';
  final l3 = unitsOverride == null
      ? _primaryUnitsLineUpper(d)
      : _kpiUnitsLineUpperFromTotals(
          bags: unitsOverride.bags,
          boxes: unitsOverride.boxes,
          tins: unitsOverride.tins,
          kg: unitsOverride.kg,
        );
  final l4 = _secondaryUnitsLineUpper(d);
  return [l1, l2, l3, l4];
}

String _itemUpperQtyLine(Map<String, dynamic> m) {
  final tb = coerceToDouble(m['total_bags']);
  final txb = coerceToDouble(m['total_boxes']);
  final ttn = coerceToDouble(m['total_tins']);
  final tkg = coerceToDouble(m['total_kg']);
  final parts = <String>[];
  // Legacy: some items were recorded in KG but named like "SUGAR 50 KG".
  // Infer bags from name when totals don't include bags.
  var bags = tb;
  if (bags <= 1e-9 && tkg > 1e-9) {
    final unit = (m['unit']?.toString() ?? '').trim().toUpperCase();
    final name = (m['item_name']?.toString() ?? '').toUpperCase();
    final isKg = unit == 'KG' || unit == 'KGS' || unit == 'KILOGRAM' || unit == 'KILOGRAMS';
    if (isKg) {
      final mm = RegExp(r'(\d{1,3}(?:\.\d{1,2})?)\s*KG\b').firstMatch(name);
      final raw = mm?.group(1);
      final v = raw == null ? null : double.tryParse(raw);
      if (v != null && v > 0 && v <= 200) {
        bags = tkg / v;
      }
    }
  }

  if (bags > 0) parts.add('${_fmtQty(bags)} ${homePackUnitWord('BAG', bags)}');
  if (txb > 0) parts.add('${_fmtQty(txb)} ${homePackUnitWord('BOX', txb)}');
  if (ttn > 0) parts.add('${_fmtQty(ttn)} ${homePackUnitWord('TIN', ttn)}');
  if (tkg > 0) parts.add('${_fmtQty(tkg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  final q = coerceToDouble(m['total_qty']);
  return homePackQtyWithDbUnit(q, m['unit']?.toString());
}

String _categoryQtyLabel(CategoryStat c) {
  final parts = <String>[];
  if (c.units.bags > 0) {
    parts.add(
        '${_fmtQty(c.units.bags)} ${homePackUnitWord('BAG', c.units.bags)}');
  }
  if (c.units.boxes > 0) {
    parts.add(
        '${_fmtQty(c.units.boxes)} ${homePackUnitWord('BOX', c.units.boxes)}');
  }
  if (c.units.tins > 0) {
    parts.add(
        '${_fmtQty(c.units.tins)} ${homePackUnitWord('TIN', c.units.tins)}');
  }
  if (parts.isNotEmpty) return parts.join(' • ');
  if (c.items.isNotEmpty) {
    final u = c.items.first.unit.trim();
    if (u.isNotEmpty && u != '—') {
      return homePackQtyWithDbUnit(c.totalQty, u);
    }
  }
  if (c.totalQty.abs() > 1e-9) return '${_fmtQty(c.totalQty)} QTY';
  return '';
}

const int _homeRingPreviewCap = 8;
const double _homeBreakdownRowExtent = 54;

const _chartEmptyCenter = Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(Icons.donut_large_rounded, size: 26, color: Color(0xFF94A3B8)),
    SizedBox(height: 6),
    Text(
      'No data',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: Color(0xFF475569),
      ),
    ),
  ],
);

const _chartSkeletonCenterInner = Column(
  mainAxisAlignment: MainAxisAlignment.center,
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox(
      height: 22,
      width: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    SizedBox(height: 8),
    Text(
      'Loading…',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: Color(0xFF64748B),
      ),
    ),
  ],
);

bool _portfolioEmpty(HomeDashboardData d) => d.purchaseCount == 0;

String _homeEmptyPeriodLabel(HomePeriod period) {
  return switch (period) {
    HomePeriod.today => 'No purchases today',
    HomePeriod.week => 'No purchases this week',
    HomePeriod.month => 'No purchases this month',
    HomePeriod.year => 'No purchases this year',
    HomePeriod.custom => 'No purchases in this period',
  };
}

HomeShellReportsBundle? _breakdownShellBundle(
  HomeBreakdownTab tab,
  AsyncValue<HomeShellReportsBundle> shell,
  HomeShellReportsBundle? peekShell,
) {
  if (tab == HomeBreakdownTab.category) return null;
  return shell.valueOrNull ?? peekShell;
}

/// Overdue / operational context before period chips and KPI (trader-first scan).
class _HomeTraderPriorityStrip extends StatelessWidget {
  const _HomeTraderPriorityStrip({
    required this.pendingDeliveryCount,
    required this.purchaseCount,
    required this.totalPurchase,
    required this.selectedPeriod,
    required this.onJumpToday,
  });

  final int pendingDeliveryCount;
  final int purchaseCount;
  final double totalPurchase;
  final HomePeriod selectedPeriod;
  final VoidCallback onJumpToday;

  @override
  Widget build(BuildContext context) {
    final showTodayCta = selectedPeriod != HomePeriod.today;
    final showTodaySummary = selectedPeriod == HomePeriod.today &&
        purchaseCount > 0 &&
        totalPurchase > 1e-9;
    if (pendingDeliveryCount <= 0 && !showTodayCta && !showTodaySummary) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingDeliveryCount > 0)
          _HomePendingDeliveryBanner(count: pendingDeliveryCount),
        if (pendingDeliveryCount > 0 &&
            (showTodayCta || showTodaySummary))
          const SizedBox(height: 8),
        if (showTodayCta)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onJumpToday,
              icon: Icon(
                Icons.today_outlined,
                size: 20,
                color: HexaColors.brandPrimary,
              ),
              label: const Text("View today's purchases"),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          )
        else if (showTodaySummary)
          Material(
            color: const Color(0xFFE8F6F4),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: HexaColors.brandPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Today · $purchaseCount '
                      '${purchaseCount == 1 ? 'purchase' : 'purchases'} · '
                      '${_inr(totalPurchase)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: Color(0xFF0F172A),
                      ),
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

/// Cloud subscription / payment row — kept directly under trader alerts, above period chips.
class _HomeCloudCostCard extends ConsumerWidget {
  const _HomeCloudCostCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cc = ref.watch(cloudCostProvider);
    return cc.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (m) {
        if (m.isEmpty) return const SizedBox.shrink();
        final showCard = m['show_home_card'] != false;
        if (!showCard) return const SizedBox.shrink();
        final name = m['name']?.toString() ?? 'Cloud Cost';
        final amt = coerceToDouble(m['amount_inr']);
        final next = m['next_due_date']?.toString() ?? '—';
        final needPay = m['show_alert'] == true;
        final inPre = m['in_pre_due_window'] == true;
        final iconColor = needPay
            ? const Color(0xFFDC2626)
            : (inPre ? const Color(0xFFF59E0B) : const Color(0xFF16A34A));
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
              SnackBar(content: Text(friendlyApiError(e))),
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
                  'Could not open a UPI app. Try again or pay manually.',
                ),
              ),
            );
          }
        }

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                : (inPre ? 'Due soon · $next' : 'Due $next'),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: openUpi,
                        child: const Text('UPI', style: TextStyle(fontSize: 12)),
                      ),
                    if (needPay || inPre)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: markPaid,
                        child:
                            const Text('Mark paid', style: TextStyle(fontSize: 12)),
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
  }
}

class _HomePendingDeliveryBanner extends StatelessWidget {
  const _HomePendingDeliveryBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/purchase?filter=pending_delivery'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                color: Colors.orange.shade800,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '1 shipment awaiting delivery'
                          : '$count shipments awaiting delivery',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    Text(
                      'Tap to open Purchase history',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.orange.shade800,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeFixedHeaderBody extends ConsumerStatefulWidget {
  const _HomeFixedHeaderBody({
    required this.data,
    required this.categoryColors,
    this.paintShellSkeleton = false,
    this.dashboardRefreshing = false,
    required this.homePeriod,
  });

  final HomeDashboardData data;
  final List<Color> categoryColors;
  final bool paintShellSkeleton;
  final bool dashboardRefreshing;
  final HomePeriod homePeriod;

  @override
  ConsumerState<_HomeFixedHeaderBody> createState() =>
      _HomeFixedHeaderBodyState();
}

class _HomeFixedHeaderBodyState extends ConsumerState<_HomeFixedHeaderBody> {
  bool _chartExpanded = true;

  Widget _ring(
    BuildContext context,
    HomeBreakdownTab tab,
    AsyncValue<HomeShellReportsBundle> shell,
    HomeShellReportsBundle? peekShell,
    List<String> rc,
    double previewSide,
  ) {
    final data = widget.data;
    final colors = widget.categoryColors;
    if (_portfolioEmpty(data)) {
      final shellBusy = tab != HomeBreakdownTab.category &&
          shell.isLoading &&
          shell.valueOrNull == null &&
          peekShell == null;
      final Widget center = widget.paintShellSkeleton
          ? _chartSkeletonCenterInner
          : shellBusy
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Updating…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                )
              : _chartEmptyCenter;
      return RepaintBoundary(
        child: SpendRingChart(
          diameter: previewSide,
          strokeWidth: 8,
          values: const [1],
          colors: const [Color(0xFFCBD5E1)],
          centerChild: center,
        ),
      );
    }

    // Shell loading: single spinner lives in the list area below — ring stays a neutral placeholder.
    if (tab != HomeBreakdownTab.category &&
        shell.isLoading &&
        shell.valueOrNull == null &&
        peekShell == null) {
      return RepaintBoundary(
        child: SpendRingChart(
          diameter: previewSide,
          strokeWidth: 8,
          values: const [1],
          colors: const [Color(0xFFCBD5E1)],
          centerChild:
              widget.paintShellSkeleton ? _chartSkeletonCenterInner : null,
        ),
      );
    }
    if (tab != HomeBreakdownTab.category &&
        shell.hasError &&
        shell.valueOrNull == null &&
        peekShell == null) {
      return SizedBox(
        height: 112,
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

    final bundle = _breakdownShellBundle(tab, shell, peekShell);
    final slice = _topSlice(data, tab, bundle, _homeRingPreviewCap, ref);
    final amts =
        List<double>.generate(slice.length, (i) => slice[i].ringAmount);
    final anySeg =
        slice.isNotEmpty && amts.isNotEmpty && amts.any((x) => x > 1e-12);

    if (!_portfolioEmpty(data) &&
        !anySeg &&
        (widget.dashboardRefreshing || data.itemSlices.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade200,
              ),
            ),
            const SizedBox(height: 16),
            const ListSkeleton(rowCount: 4),
          ],
        ),
      );
    }

    if (!anySeg) {
      return RepaintBoundary(
        child: SpendRingChart(
          diameter: previewSide,
          strokeWidth: 8,
          values: const [1],
          colors: const [Color(0xFFCBD5E1)],
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
          diameter: previewSide,
          strokeWidth: 8,
          values: amts,
          colors: colors,
          centerLine1: rc[0],
          centerLine2: rc[1],
          centerLine3: rc[2],
          centerLine4: rc[3],
          onSectionTap: (i) {
            if (i < 0 || i >= slice.length) return;
            slice[i].onTap(context, ref);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeBreakdownTabProvider);
    final shell = ref.watch(homeShellReportsProvider);
    final peekShell = ref.watch(homeShellReportsSyncCacheProvider);
    final unitsFromShell =
        _unitTotalsFromHomeShell(shell.valueOrNull ?? peekShell);
    final rc = _ringCenterLines(widget.data, unitsOverride: unitsFromShell);

    final data = widget.data;
    final emptyPortfolio = !widget.dashboardRefreshing &&
        data.totalPurchase == 0 &&
        data.purchaseCount == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _KpiTightBlock(
            data: widget.data,
            unitsOverride: unitsFromShell,
          ),
        ),
        if (emptyPortfolio)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 52, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  _homeEmptyPeriodLabel(widget.homePeriod),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap + to record your first purchase',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade400,
                      ),
                ),
              ],
            ),
          )
        else if (data.itemSlices.isEmpty && widget.dashboardRefreshing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: List.generate(
                4,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!emptyPortfolio) ...[
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _HomeBreakdownTabStrip(
                  selected: tab,
                  onSelect: (t) {
                    ref.read(homeBreakdownTabProvider.notifier).state = t;
                  },
                ),
              ),
            ),
            IconButton(
              tooltip: _chartExpanded ? 'Hide spend chart' : 'Show spend chart',
              onPressed: () => setState(() => _chartExpanded = !_chartExpanded),
              icon: Icon(
                _chartExpanded ? Icons.unfold_less : Icons.unfold_more,
                size: 22,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (_chartExpanded)
          LayoutBuilder(
            builder: (context, c) {
              final mw = c.maxWidth;
              if (!mw.isFinite || mw < 8) {
                return const SizedBox(height: 120);
              }
              final previewSide = computeHomeSpendRingDiameter(
                screenHeight: MediaQuery.sizeOf(context).height,
                layoutMaxWidth: mw,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _ring(context, tab, shell, peekShell, rc, previewSide),
              );
            },
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: HexaColors.brandBorder),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _chartExpanded = true),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.donut_large_outlined,
                        color: Colors.blueGrey.shade600,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Spend chart hidden',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              rc.take(2).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Show',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 2),
        Expanded(
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: IndexedStack(
                index: tab.index,
                sizing: StackFit.expand,
                children: [
                  for (final t in HomeBreakdownTab.values)
                    _HomeBreakdownListKeepAlive(
                      key: ValueKey<String>('home_bd_${t.name}'),
                      panelTab: t,
                      data: widget.data,
                      categoryColors: widget.categoryColors,
                    ),
                ],
              ),
            ),
          ),
        ),
        ],
      ],
    );
  }
}

class _KpiTightBlock extends StatelessWidget {
  const _KpiTightBlock({required this.data, this.unitsOverride});
  final HomeDashboardData data;
  final ({double bags, double boxes, double tins, double kg})? unitsOverride;

  @override
  Widget build(BuildContext context) {
    final primaryUnits = unitsOverride == null
        ? _primaryUnitsLineUpper(data)
        : _kpiUnitsLineUpperFromTotals(
            bags: unitsOverride!.bags,
            boxes: unitsOverride!.boxes,
            tins: unitsOverride!.tins,
            kg: unitsOverride!.kg,
          );
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        primaryUnits.trim().isEmpty ? '—' : primaryUnits,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1.12,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _inr(data.totalPurchase),
                        maxLines: 1,
                        style: HexaDsType.purchaseLineMoney.copyWith(
                          fontSize: 18,
                          height: 1.1,
                          color: const Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
                    style: const TextStyle(fontSize: 11, height: 1.15),
                    children: boldLine2.trim().isEmpty
                        ? const <InlineSpan>[
                            TextSpan(
                              text: '—',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ]
                        : [
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
  final void Function(BuildContext context, WidgetRef ref) onTap;
}

List<_BreakdownRowSlice> _topSlice(
  HomeDashboardData d,
  HomeBreakdownTab tab,
  HomeShellReportsBundle? bundle,
  int maxN,
  WidgetRef ref,
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
            onTap: (ctx, _) {
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
          final pa = coerceToDouble(a['total_purchase']);
          final pc = coerceToDouble(c['total_purchase']);
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
            ringAmount: coerceToDouble(r['total_purchase']),
            line2: _itemUpperQtyLine(r),
            sup: '—',
            bro: '—',
            onTap: (ctx, _) {
              final tid =
                  (r['type_id'] ?? r['typeId'])?.toString().trim() ?? '';
              final cid =
                  (r['category_id'] ?? r['categoryId'])?.toString().trim() ??
                      '';
              if (tid.isNotEmpty && cid.isNotEmpty) {
                ctx.push('/catalog/category/$cid/type/$tid');
              } else if (cid.isNotEmpty) {
                ctx.push('/catalog/category/$cid');
              } else {
                ctx.go('/catalog');
              }
            },
          ),
      ];
    case HomeBreakdownTab.supplier:
      if (bundle == null) return const [];
      final rows = List<Map<String, dynamic>>.from(bundle.suppliers)
        ..sort((a, c) {
          final pa = coerceToDouble(a['total_purchase']);
          final pc = coerceToDouble(c['total_purchase']);
          return pc.compareTo(pa);
        });
      return [
        for (final r in rows.take(maxN))
          _BreakdownRowSlice(
            title: r['supplier_name']?.toString() ?? '—',
            ringAmount: coerceToDouble(r['total_purchase']),
            line2: _itemUpperQtyLine(r),
            sup: '—',
            bro: '—',
            onTap: (ctx, _) {
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
          final pa = coerceToDouble(a['total_purchase']);
          final pc = coerceToDouble(c['total_purchase']);
          return pc.compareTo(pa);
        });
      return [
        for (final r in rows.take(maxN))
          _BreakdownRowSlice(
            title: r['item_name']?.toString() ?? '—',
            ringAmount: coerceToDouble(r['total_purchase']),
            line2: _itemUpperQtyLine(r),
            sup: '—',
            bro: '—',
            onTap: (ctx, ref) {
              unawaited(openTradeItemFromReportRow(ctx, ref, r));
            },
          ),
      ];
  }
}

class _HomeBreakdownListKeepAlive extends ConsumerStatefulWidget {
  const _HomeBreakdownListKeepAlive({
    super.key,
    required this.panelTab,
    required this.data,
    required this.categoryColors,
  });

  final HomeBreakdownTab panelTab;
  final HomeDashboardData data;
  final List<Color> categoryColors;

  @override
  ConsumerState<_HomeBreakdownListKeepAlive> createState() =>
      _HomeBreakdownListKeepAliveState();
}

class _HomeBreakdownListKeepAliveState
    extends ConsumerState<_HomeBreakdownListKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tab = widget.panelTab;
    final shell = ref.watch(homeShellReportsProvider);
    final peekShell = ref.watch(homeShellReportsSyncCacheProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        if (!maxH.isFinite || maxH < 8) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (tab != HomeBreakdownTab.category) {
          if (shell.isLoading &&
              shell.valueOrNull == null &&
              peekShell == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LinearProgressIndicator(minHeight: 2),
                const Expanded(
                  child: ListSkeleton(rowCount: 5),
                ),
              ],
            );
          }
          if (shell.hasError &&
              shell.valueOrNull == null &&
              peekShell == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(homeShellReportsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Could not load breakdown — Retry'),
                ),
              ),
            );
          }
        } else if (widget.data.categories.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No purchases in this period',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.go('/purchase/new'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add a purchase'),
                  ),
                ],
              ),
            ),
          );
        }

        final bundle = _breakdownShellBundle(tab, shell, peekShell);
        final full = _topSlice(
          widget.data,
          tab,
          bundle,
          10000,
          ref,
        );

        if (full.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No rows for this tab',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/purchase/new'),
                  child: const Text('Add Purchase'),
                ),
              ],
            ),
          );
        }

        var maxSlots = math.max(
          1,
          (constraints.maxHeight / _homeBreakdownRowExtent).floor(),
        );
        // Leave slack for "View more", row chrome, and web safe-area so the
        // breakdown column does not overflow (~29px) on short viewports.
        const reserveFooter = 80.0;
        maxSlots = math.max(
          1,
          ((constraints.maxHeight - reserveFooter) / _homeBreakdownRowExtent)
              .floor(),
        );

        final cap = math.min(maxSlots, full.length);
        final needsMore = full.length > maxSlots;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cap,
                itemBuilder: (ctx, i) {
                  final row = full[i];
                  return SizedBox(
                    height: _homeBreakdownRowExtent,
                    child: _HomeBreakdownDataRow(
                      title: row.title,
                      amount: row.ringAmount,
                      boldLine2: row.line2,
                      sup: row.sup,
                      bro: row.bro,
                      dotColor: widget.categoryColors[
                          i % widget.categoryColors.length],
                      onTap: () => row.onTap(context, ref),
                    ),
                  );
                },
              ),
            ),
            if (needsMore)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => context.push(
                    '/home/breakdown-more?tab=${tab.name}',
                  ),
                  child: const Text('View more'),
                ),
              ),
          ],
        );
      },
    );
  }
}

