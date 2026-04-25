import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/purchase_post_save_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';
import '../../purchase/presentation/widgets/purchase_saved_sheet.dart';
import '../../../core/providers/home_dashboard_provider.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);

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

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: HexaColors.brandPrimary,
          edgeOffset: 72,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _PeriodStrip(
                    selected: period,
                    custom: custom,
                    onSelect: _selectPeriod,
                    onPickCustom: _pickCustomRange,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: async.when(
                    skipLoadingOnReload: true,
                    loading: () => const LinearProgressIndicator(minHeight: 3),
                    error: (_, __) => FriendlyLoadError(
                      message: 'Could not load dashboard',
                      onRetry: () => unawaited(_refresh()),
                    ),
                    data: (_) => const SizedBox.shrink(),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  96 + MediaQuery.of(context).padding.bottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: async.when(
                    skipLoadingOnReload: true,
                    loading: () => const _LoadingPlaceholder(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (d) => _DashboardBody(
                      data: d,
                      donutColors: _donutColors,
                    ),
                  ),
                ),
              ),
            ],
          ),
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

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody({
    required this.data,
    required this.donutColors,
  });

  final HomeDashboardData data;
  final List<Color> donutColors;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

enum _DonutView { category, subcategory, item }

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  _DonutView _view = _DonutView.category;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeKpiCard(data: widget.data),
        const SizedBox(height: 14),
        _DonutSection(
          data: widget.data,
          colors: widget.donutColors,
          view: _view,
          onViewChanged: (v) => setState(() => _view = v),
        ),
        const SizedBox(height: 14),
        _BreakdownListSection(data: widget.data, view: _view),
      ],
    );
  }
}

String _kpiUnitsLine(HomeDashboardData data) {
  final parts = <String>[];
  if (data.totalKg > 0) parts.add('${_fmtQty(data.totalKg)} kg');
  if (data.totalBags > 0) parts.add('${_fmtQty(data.totalBags)} bag');
  if (data.totalBoxes > 0) parts.add('${_fmtQty(data.totalBoxes)} box');
  if (data.totalTins > 0) parts.add('${_fmtQty(data.totalTins)} tin');
  return parts.join(' | ');
}

/// Same as [_kpiUnitsLine] but stacked to avoid a long line in the donut center.
String _kpiUnitsLineStacked(HomeDashboardData data) {
  final s = _kpiUnitsLine(data);
  if (s.isEmpty) return s;
  return s.replaceAll(' | ', '\n');
}

class _HomeKpiCard extends StatelessWidget {
  const _HomeKpiCard({required this.data});
  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final units = _kpiUnitsLine(data);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Purchases (₹)',
              style: HexaDsType.label(12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 2),
            Text(
              _inr(data.totalPurchase),
              textAlign: TextAlign.left,
              style: HexaDsType.purchaseLineMoney.copyWith(
                fontSize: 24,
                height: 1.15,
              ),
            ),
            if (units.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                units,
                style: tt.titleSmall?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Deals: ${data.purchaseCount}',
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Total line qty: ${_fmtQty(data.totalQtyAllLines)}',
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutSection extends StatelessWidget {
  const _DonutSection({
    required this.data,
    required this.colors,
    required this.view,
    required this.onViewChanged,
  });

  final HomeDashboardData data;
  final List<Color> colors;
  final _DonutView view;
  final ValueChanged<_DonutView> onViewChanged;

  String get _title => switch (view) {
        _DonutView.category => 'Spend by category',
        _DonutView.subcategory => 'Spend by subcategory',
        _DonutView.item => 'Spend by item',
      };

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Distribution',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final v in _DonutView.values) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      showCheckmark: false,
                      label: Text(switch (v) {
                        _DonutView.category => 'Category',
                        _DonutView.subcategory => 'Subcategory',
                        _DonutView.item => 'Items',
                      }),
                      selected: view == v,
                      onSelected: (_) => onViewChanged(v),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              return switch (view) {
                _DonutView.category => _donutForCategories(context, c),
                _DonutView.subcategory => _donutForSubcategories(context, c),
                _DonutView.item => _donutForItems(context, c),
              };
            },
          ),
        ],
      ),
    );
  }

  Widget _donutForCategories(
      BuildContext context, BoxConstraints constraints) {
    final slice = data.categories.where((e) => e.totalAmount > 0).toList();
    final qSlice = slice.fold<double>(0, (a, s) => a + s.totalQty);
    return _buildDonut(
      context,
      constraints,
      slice.isEmpty,
      'No category spend in this period',
      slice.isEmpty
          ? 0
          : slice.fold<double>(0, (a, b) => a + b.totalAmount),
      (i) {
        if (i < 0 || i >= slice.length) return;
        final cat = slice[i];
        if (cat.categoryId == '_uncat') {
          context.go('/catalog');
        } else {
          context.go('/catalog/category/${cat.categoryId}');
        }
      },
      List.generate(
        slice.length,
        (i) => PieChartSectionData(
          value: slice[i].totalAmount,
          color: colors[i % colors.length],
          showTitle: false,
        ),
      ),
      _legendCategory(context, slice),
      sliceLineQty: qSlice,
    );
  }

  Widget _donutForSubcategories(
      BuildContext context, BoxConstraints constraints) {
    final slice = data.subcategories.where((e) => e.totalAmount > 0).toList();
    final qSlice = slice.fold<double>(0, (a, s) => a + s.totalQty);
    return _buildDonut(
      context,
      constraints,
      slice.isEmpty,
      'No subcategory spend in this period',
      slice.isEmpty
          ? 0
          : slice.fold<double>(0, (a, b) => a + b.totalAmount),
      (i) {
        if (i < 0 || i >= slice.length) return;
        final s = slice[i];
        final parts = s.id.split('|');
        if (parts.isNotEmpty && parts[0] != '_uncat' && parts[0].isNotEmpty) {
          context.go('/catalog/category/${parts[0]}');
        } else {
          context.go('/catalog');
        }
      },
      List.generate(
        slice.length,
        (i) => PieChartSectionData(
          value: slice[i].totalAmount,
          color: colors[i % colors.length],
          showTitle: false,
        ),
      ),
      _legendSubcategory(context, slice),
      sliceLineQty: qSlice,
    );
  }

  Widget _donutForItems(
      BuildContext context, BoxConstraints constraints) {
    final slice = data.itemSlices.where((e) => e.totalAmount > 0).toList();
    final qSlice = slice.fold<double>(0, (a, s) => a + s.totalQty);
    return _buildDonut(
      context,
      constraints,
      slice.isEmpty,
      'No item spend in this period',
      slice.isEmpty
          ? 0
          : slice.fold<double>(0, (a, b) => a + b.totalAmount),
      (i) {
        if (i < 0 || i >= slice.length) return;
        final it = slice[i];
        final id = it.catalogItemId;
        if (id != null && id.isNotEmpty) {
          context.push('/catalog/item/$id');
        } else {
          final enc = Uri.encodeComponent(it.name);
          context.push('/item-analytics/$enc');
        }
      },
      List.generate(
        slice.length,
        (i) => PieChartSectionData(
          value: slice[i].totalAmount,
          color: colors[i % colors.length],
          showTitle: false,
        ),
      ),
      _legendItem(context, slice),
      sliceLineQty: qSlice,
    );
  }

  Widget _buildDonut(
    BuildContext context,
    BoxConstraints constraints,
    bool isEmpty,
    String emptyText,
    double total,
    void Function(int) onSectionTap,
    List<PieChartSectionData> sections,
    Widget legend, {
    required double sliceLineQty,
  }) {
    if (isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final maxW = constraints.maxWidth;
    final side = (maxW * 0.36).clamp(120.0, 164.0);
    final ring = (side * 0.26).clamp(30.0, 48.0);
    final centerR = (ring * 0.72).clamp(28.0, 44.0);
    final units = _kpiUnitsLineStacked(data);

    final chartSections = sections
        .map(
          (s) => PieChartSectionData(
            value: s.value,
            color: s.color,
            radius: ring,
            showTitle: false,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: RepaintBoundary(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: centerR,
                      sections: chartSections,
                      pieTouchData: PieTouchData(
                        enabled: true,
                        touchCallback: (event, response) {
                          final idx =
                              response?.touchedSection?.touchedSectionIndex;
                          if (idx == null) return;
                          onSectionTap(idx);
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: side * 0.9),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'In view',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _inr(total),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: HexaColors.brandPrimary,
                                    fontSize: 15,
                                    height: 1.1,
                                  ),
                            ),
                            if (units.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                units,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: const Color(0xFF0F172A),
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                      fontSize: 9,
                                    ),
                              ),
                            ],
                            if (sliceLineQty > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Chart qty ${_fmtQty(sliceLineQty)}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: const Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 8.5,
                                    ),
                              ),
                            ],
                            Text(
                              'All lines qty ${_fmtQty(data.totalQtyAllLines)}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 8.5,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        legend,
      ],
    );
  }

  Widget _legendCategory(
      BuildContext context, List<CategoryStat> slice) {
    return _legendRows(
      List.generate(
        slice.length,
        (i) => _LegendEntry(
          color: colors[i % colors.length],
          title: slice[i].categoryName,
          sub: _inr(slice[i].totalAmount),
        ),
      ),
    );
  }

  Widget _legendSubcategory(
      BuildContext context, List<SubcategoryStat> slice) {
    return _legendRows(
      List.generate(
        slice.length,
        (i) => _LegendEntry(
          color: colors[i % colors.length],
          title: slice[i].label,
          sub: _inr(slice[i].totalAmount),
        ),
      ),
    );
  }

  Widget _legendItem(BuildContext context, List<ItemSliceStat> slice) {
    return _legendRows(
      List.generate(
        slice.length,
        (i) => _LegendEntry(
          color: colors[i % colors.length],
          title: slice[i].name,
          sub: _inr(slice[i].totalAmount),
        ),
      ),
    );
  }

  Widget _legendRows(List<_LegendEntry> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: items[i].color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  items[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                items[i].sub,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LegendEntry {
  const _LegendEntry({
    required this.color,
    required this.title,
    required this.sub,
  });
  final Color color;
  final String title;
  final String sub;
}

Widget _sectionCard(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: HexaColors.brandBorder),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _BreakdownListSection extends StatelessWidget {
  const _BreakdownListSection({
    required this.data,
    required this.view,
  });

  final HomeDashboardData data;
  final _DonutView view;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      _DonutView.category => _categoryList(context),
      _DonutView.subcategory => _subcategoryList(context),
      _DonutView.item => _itemList(context),
    };
  }

  Widget _categoryList(BuildContext context) {
    if (data.categories.isEmpty) {
      return _sectionCard(
        context,
        title: 'Details',
        child: const Text(
          'No purchases in this period',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return _sectionCard(
      context,
      title: 'By category',
      child: Column(
        children: [
          for (var i = 0; i < data.categories.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _CategoryExpansionTile(stat: data.categories[i]),
          ],
        ],
      ),
    );
  }

  Widget _subcategoryList(BuildContext context) {
    final rows = data.subcategories.where((e) => e.totalAmount > 0).toList();
    if (rows.isEmpty) {
      return _sectionCard(
        context,
        title: 'By subcategory',
        child: const Text(
          'No subcategory data in this period',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return _sectionCard(
      context,
      title: 'By subcategory',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                rows[i].label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF0F172A),
                ),
              ),
              subtitle: Text(
                '${_fmtQty(rows[i].totalQty)} qty',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Text(
                _inr(rows[i].totalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: HexaColors.brandPrimary,
                ),
              ),
              onTap: () {
                final parts = rows[i].id.split('|');
                if (parts.isNotEmpty &&
                    parts[0] != '_uncat' &&
                    parts[0].isNotEmpty) {
                  context.go('/catalog/category/${parts[0]}');
                } else {
                  context.go('/catalog');
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemList(BuildContext context) {
    final rows = data.itemSlices.where((e) => e.totalAmount > 0).toList();
    if (rows.isEmpty) {
      return _sectionCard(
        context,
        title: 'By item',
        child: const Text(
          'No item data in this period',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return _sectionCard(
      context,
      title: 'By item',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                rows[i].name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF0F172A),
                ),
              ),
              subtitle: Text(
                rows[i].unit.isEmpty
                    ? '${_fmtQty(rows[i].totalQty)} qty'
                    : '${_fmtQty(rows[i].totalQty)} ${rows[i].unit}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Text(
                _inr(rows[i].totalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: HexaColors.brandPrimary,
                ),
              ),
              onTap: () {
                final id = rows[i].catalogItemId;
                if (id != null && id.isNotEmpty) {
                  context.push('/catalog/item/$id');
                } else {
                  final enc = Uri.encodeComponent(rows[i].name);
                  context.push('/item-analytics/$enc');
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryExpansionTile extends StatelessWidget {
  const _CategoryExpansionTile({required this.stat});
  final CategoryStat stat;

  @override
  Widget build(BuildContext context) {
    final top = stat.items.isNotEmpty ? stat.items.first : null;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 8, right: 0, bottom: 8),
        title: Text(
          stat.categoryName,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Color(0xFF0F172A),
          ),
        ),
        subtitle: top != null
            ? Text(
                'Top: ${top.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _inr(stat.totalAmount),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: HexaColors.brandPrimary,
              ),
            ),
            Text(
              '${_fmtQty(stat.totalQty)} qty',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        children: [
          for (final it in stat.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      it.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Text(
                    it.unit.isEmpty
                        ? _fmtQty(it.qty)
                        : '${_fmtQty(it.qty)} ${it.unit}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _inr(it.amount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
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
