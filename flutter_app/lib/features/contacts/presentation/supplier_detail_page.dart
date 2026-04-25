import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/calc_engine.dart' show lineMoney;
import '../../../core/catalog/item_trade_history.dart' show tradeLineToCalc;
import '../../../core/config/app_config.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/purchase_prefill_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

final _supplierProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, supplierId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getSupplier(
        businessId: session.primaryBusiness.id,
        supplierId: supplierId,
      );
});

class _SupplierStatCard extends StatelessWidget {
  const _SupplierStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: HexaColors.cardShadow(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: value.contains('₹')
                        ? HexaDsType.purchaseLineMoney
                            .copyWith(fontSize: 17, color: cs.onSurface)
                        : HexaDsType.statChipValue
                            .copyWith(color: cs.onSurface, fontSize: 17),
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

DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

List<TradePurchase> _tradesInDateWindow(
  List<TradePurchase> all,
  DateTime from,
  DateTime to,
) {
  return [
    for (final p in all)
      if (!_dOnly(p.purchaseDate).isBefore(from) &&
          !_dOnly(p.purchaseDate).isAfter(to))
        p,
  ];
}

double _lineAmountInr(TradePurchaseLine ln) =>
    lineMoney(tradeLineToCalc(ln));

class SupplierDetailPage extends ConsumerStatefulWidget {
  const SupplierDetailPage({super.key, required this.supplierId});

  final String supplierId;

  @override
  ConsumerState<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends ConsumerState<SupplierDetailPage> {
  late DateTime _to;
  late DateTime _from;
  bool _loading = false;
  Map<String, dynamic>? _metrics;
  List<Map<String, dynamic>>? _supplierRankRows;
  /// PUR bills in the selected date range (trade flow only; legacy entries removed)
  List<TradePurchase> _trades = const [];

  @override
  void initState() {
    super.initState();
    _to = _dOnly(DateTime.now());
    _from = _to.subtract(const Duration(days: 89));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    // Bust the Riverpod detail provider so the header card (name, phone, etc.)
    // also reflects any server-side edits — not just metrics/entries.
    ref.invalidate(_supplierProvider(widget.supplierId));
    setState(() => _loading = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final api = ref.read(hexaApiProvider);
    final f = fmt.format(_from);
    final t = fmt.format(_to);
    try {
      final m = await api.supplierMetrics(
          businessId: session.primaryBusiness.id,
          supplierId: widget.supplierId,
          from: f,
          to: t);
      List<Map<String, dynamic>>? rank;
      try {
        rank = await api.analyticsSuppliers(
            businessId: session.primaryBusiness.id, from: f, to: t);
      } catch (_) {}
      var trades = <TradePurchase>[];
      try {
        final traw = await api.listTradePurchases(
          businessId: session.primaryBusiness.id,
          limit: 200,
          status: 'all',
          supplierId: widget.supplierId,
        );
        for (final row in traw) {
          try {
            trades.add(
              TradePurchase.fromJson(Map<String, dynamic>.from(row as Map)),
            );
          } catch (_) {}
        }
        trades = _tradesInDateWindow(trades, _from, _to);
        trades.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      } catch (_) {}
      if (mounted) {
        setState(() {
          _metrics = m;
          _supplierRankRows = rank;
          _trades = trades;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  void _preset(int days) {
    final n = _dOnly(DateTime.now());
    setState(() {
      _to = n;
      _from = days <= 0 ? DateTime(2020) : n.subtract(Duration(days: days - 1));
    });
    _reload();
  }

  bool _isPreset7d() {
    final n = _dOnly(DateTime.now());
    return _dOnly(_to) == n && _dOnly(_from) == n.subtract(const Duration(days: 6));
  }

  bool _isPreset30d() {
    final n = _dOnly(DateTime.now());
    return _dOnly(_to) == n && _dOnly(_from) == n.subtract(const Duration(days: 29));
  }

  bool _isPreset90d() {
    final n = _dOnly(DateTime.now());
    return _dOnly(_to) == n && _dOnly(_from) == n.subtract(const Duration(days: 89));
  }

  bool _isYtd() {
    final n = _dOnly(DateTime.now());
    return _dOnly(_to) == n && _dOnly(_from) == _dOnly(DateTime(n.year, 1, 1));
  }

  bool _isAllTime() {
    return _dOnly(_from) == _dOnly(DateTime(2020));
  }

  Future<void> _dial(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$d');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  List<FlSpot> _chartSpots() {
    if (_trades.isEmpty) return [];
    final byDay = <String, List<double>>{};
    for (final p in _trades) {
      if (p.statusEnum == PurchaseStatus.draft ||
          p.statusEnum == PurchaseStatus.cancelled) {
        continue;
      }
      final ds = p.purchaseDate.toIso8601String().split('T').first;
      for (final ln in p.lines) {
        final kpu = ln.kgPerUnit;
        final lcpk = ln.landingCostPerKg;
        final val = (kpu != null && lcpk != null && kpu > 0 && lcpk > 0)
            ? lcpk
            : (ln.landingCost > 0 ? ln.landingCost : 0.0);
        if (val <= 0) continue;
        byDay.putIfAbsent(ds, () => []).add(val);
      }
    }
    if (byDay.isEmpty) return [];
    final sorted = byDay.keys.toList()..sort();
    final spots = <FlSpot>[];
    for (var i = 0; i < sorted.length; i++) {
      final vals = byDay[sorted[i]]!;
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      spots.add(FlSpot(i.toDouble(), avg));
    }
    return spots;
  }

  double _performancePct() {
    final rows = _supplierRankRows;
    if (rows == null || rows.isEmpty) return 0;
    final avgs = <double>[];
    for (final r in rows) {
      final a = (r['avg_landing'] as num?)?.toDouble();
      if (a != null && a > 0) avgs.add(a);
    }
    if (avgs.length < 2) return 50;
    avgs.sort();
    final mine = _metrics == null
        ? null
        : (_metrics!['avg_landing'] as num?)?.toDouble();
    if (mine == null || mine <= 0) return 50;
    var better = 0;
    for (final x in avgs) {
      if (mine <= x) better++;
    }
    return (better / avgs.length * 100).clamp(0, 100);
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer(
        'date,pur_id,item,qty,unit,landing_per_unit,selling,total_line\n');
    for (final p in _trades) {
      final d = p.purchaseDate.toIso8601String().split('T').first;
      for (final ln in p.lines) {
        final lpu = (ln.kgPerUnit != null &&
                ln.landingCostPerKg != null &&
                (ln.kgPerUnit ?? 0) > 0)
            ? ln.landingCostPerKg
            : ln.landingCost;
        buf.writeln(
            '$d,${p.humanId},"${ln.itemName.replaceAll('"', "'")}",${ln.qty},${ln.unit},$lpu,${ln.sellingCost ?? ''},${_lineAmountInr(ln)}');
      }
    }
    if (buf.length < 100) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No trade lines to export in this range.')),
        );
      }
      return;
    }
    await Share.share(buf.toString(),
        subject: '${AppConfig.appName} supplier export');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_supplierProvider(widget.supplierId));
    final tt = Theme.of(context).textTheme;
    final fmt = DateFormat.yMMMd();

    return Scaffold(
      floatingActionButton: async.maybeWhen(
        data: (_) => FloatingActionButton.extended(
          onPressed: () {
            ref.read(pendingPurchaseSupplierIdProvider.notifier).state =
                widget.supplierId;
            context.pushNamed('purchase_new');
          },
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('New purchase'),
        ),
        orElse: () => null,
      ),
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.popOrGo('/contacts')),
        title: async.maybeWhen(
          data: (s) => Text(s['name']?.toString() ?? 'Supplier'),
          orElse: () => const Text('Supplier'),
        ),
        actions: [
          IconButton(
            tooltip: 'Trade purchase ledger',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () =>
                context.push('/supplier/${widget.supplierId}/ledger'),
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _trades.isEmpty ? null : _exportCsv,
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load supplier',
          onRetry: () => ref.invalidate(_supplierProvider(widget.supplierId)),
        ),
        data: (s) {
          final phone = s['phone']?.toString();
          final wa = s['whatsapp_number']?.toString();
          final bid = s['broker_id']?.toString();
          final loc = s['location']?.toString() ?? '';
          final name = s['name']?.toString() ?? 'n/a';
          final cs = Theme.of(context).colorScheme;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              children: [
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: tt.headlineSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 22),
                      ),
                      if (loc.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(loc,
                                    style: tt.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant))),
                          ],
                        ),
                      ],
                      if (phone != null && phone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(phone,
                            style: tt.bodyMedium?.copyWith(
                                color: cs.onSurface)),
                      ],
                      if (wa != null && wa.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('WhatsApp: $wa',
                            style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: phone == null || phone.isEmpty
                                ? null
                                : () => _dial(phone),
                            icon: const Icon(Icons.call_rounded, size: 20),
                            label: const Text('Call'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: wa == null || wa.isEmpty
                                ? null
                                : () => _openWhatsApp(wa),
                            icon: const Icon(Icons.chat_rounded, size: 20),
                            label: const Text('WhatsApp'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipPill(
                            label: '7d',
                            selected: _isPreset7d(),
                            onTap: () => _preset(7),
                            onGradient: false,
                          ),
                          _ChipPill(
                            label: '30d',
                            selected: _isPreset30d(),
                            onTap: () => _preset(30),
                            onGradient: false,
                          ),
                          _ChipPill(
                            label: '90d',
                            selected: _isPreset90d(),
                            onTap: () => _preset(90),
                            onGradient: false,
                          ),
                          _ChipPill(
                            label: 'YTD',
                            selected: _isYtd(),
                            onGradient: false,
                            onTap: () {
                              final n = DateTime.now();
                              setState(() {
                                _from = DateTime(n.year, 1, 1);
                                _to = _dOnly(n);
                              });
                              _reload();
                            },
                          ),
                          _ChipPill(
                            label: 'All',
                            selected: _isAllTime(),
                            onTap: () => _preset(0),
                            onGradient: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${fmt.format(_from)} – ${fmt.format(_to)}',
                        style: tt.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (bid != null) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.handshake_outlined),
                    title: const Text('Linked broker'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/broker/$bid'),
                  ),
                ],
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()))
                else if (_metrics != null) ...[
                  Text('Metrics',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _metricsGrid(_metrics!, tt),
                  const SizedBox(height: 16),
                  Text('Price vs other suppliers',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _PerfBar(
                    pct: _performancePct(),
                    hasSupplierData:
                        ((_metrics!['deals'] as num?)?.toInt() ?? 0) > 0,
                  ),
                  const SizedBox(height: 16),
                  Text('Avg landing trend',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _LandingChart(spots: _chartSpots()),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Trade purchase history',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        _trades.isEmpty
                            ? '0 bills'
                            : '${_trades.length} bill${_trades.length == 1 ? '' : 's'} · '
                                '${_trades.fold<int>(0, (a, p) => a + p.lines.length)} lines',
                        style: tt.labelSmall
                            ?.copyWith(color: HexaColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_trades.isEmpty)
                    HexaEmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No trade purchases in this date range',
                      subtitle:
                          'Record a PUR for this supplier or widen the range above.',
                      primaryActionLabel: 'Add purchase',
                      onPrimaryAction: () => context.push('/purchase/new'),
                    )
                  else
                    _SupplierTradeTable(trades: _trades),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.receipt_long_outlined,
                        size: 20, color: cs.primary),
                    title: Text(
                      'Full PUR ledger',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () =>
                        context.push('/supplier/${widget.supplierId}/ledger'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _metricsGrid(Map<String, dynamic> m, TextTheme tt) {
    final deals = (m['deals'] as num?)?.toInt() ?? 0;
    final tq = (m['total_qty'] as num?)?.toDouble() ?? 0;
    final al = (m['avg_landing'] as num?)?.toDouble() ?? 0;
    final tp = (m['total_profit'] as num?)?.toDouble() ?? 0;
    final pam = (m['purchase_amount'] as num?)?.toDouble() ?? 0;
    final margin = (m['profit_margin_pct'] as num?)?.toDouble() ?? 0;
    const w = 152.0;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
            width: w,
            height: 120,
            child: _SupplierStatCard(
                icon: Icons.receipt_long_rounded,
                label: 'Deals',
                value: '$deals',
                accent: const Color(0xFF1A6B8A))),
        SizedBox(
            width: w,
            height: 120,
            child: _SupplierStatCard(
                icon: Icons.shopping_cart_outlined,
                label: 'Purchase',
                value: '₹${pam.toStringAsFixed(0)}',
                accent: const Color(0xFF3949AB))),
        SizedBox(
            width: w,
            height: 120,
            child: _SupplierStatCard(
                icon: Icons.scale_rounded,
                label: 'Total qty',
                value: tq.toStringAsFixed(1),
                accent: const Color(0xFF6A1B9A))),
        SizedBox(
            width: w,
            height: 120,
            child: _SupplierStatCard(
                icon: Icons.price_change_outlined,
                label: 'Avg landing',
                value: '₹${al.toStringAsFixed(2)}',
                accent: const Color(0xFFFF9800))),
        SizedBox(
            width: w,
            height: 120,
            child: _SupplierStatCard(
                icon: Icons.trending_up_rounded,
                label: 'Total profit',
                value: '₹${tp.toStringAsFixed(0)}',
                accent: HexaColors.profit)),
        SizedBox(
            width: w,
            height: 120,
            child: _SupplierStatCard(
                icon: Icons.percent_rounded,
                label: 'Avg margin',
                value: '${margin.toStringAsFixed(1)}%',
                accent: HexaColors.accentAmber)),
      ],
    );
  }
}

class _ChipPill extends StatelessWidget {
  const _ChipPill({
    required this.label,
    required this.onTap,
    this.onGradient = false,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool onGradient;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = onGradient
        ? ActionChip(
            label: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
            onPressed: onTap,
          )
        : FilterChip(
            label: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            showCheckmark: false,
            selected: selected,
            onSelected: (_) => onTap(),
            selectedColor: cs.primaryContainer,
            checkmarkColor: cs.primary,
            side: BorderSide(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
            visualDensity: VisualDensity.compact,
          );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: child,
    );
  }
}

class _PerfBar extends StatelessWidget {
  const _PerfBar({required this.pct, required this.hasSupplierData});

  final double pct;
  final bool hasSupplierData;

  @override
  Widget build(BuildContext context) {
    final good = pct >= 60;
    final col = good
        ? HexaColors.profit
        : (pct >= 40 ? HexaColors.accentAmber : HexaColors.loss);
    final caption = !hasSupplierData
        ? '${pct.toStringAsFixed(0)}%: No data yet. Add purchases from this supplier'
        : '${pct.toStringAsFixed(0)}%: ${good ? 'Better than many on price' : 'Negotiate harder on landing'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: hasSupplierData ? (pct / 100).clamp(0.0, 1.0) : 0,
            minHeight: 10,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            color: col,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: HexaColors.textSecondary),
        ),
      ],
    );
  }
}

class _LandingChart extends StatelessWidget {
  const _LandingChart({required this.spots});

  final List<FlSpot> spots;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (spots.length < 2) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Not enough dated points — add more purchases.',
            style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary)),
      );
    }
    final ys = spots.map((s) => s.y).toList();
    final minY = ys.reduce(math.min) * 0.92;
    final maxY = ys.reduce(math.max) * 1.08;
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, _) =>
                    Text(v.toInt().toString(), style: tt.labelSmall),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) =>
                    Text(v.toStringAsFixed(0), style: tt.labelSmall),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: HexaColors.primaryMid,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierTradeTable extends StatelessWidget {
  const _SupplierTradeTable({required this.trades});

  final List<TradePurchase> trades;

  String _inr(num v) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      ).format(v);

  String _rateL(TradePurchaseLine ln) {
    final kpu = ln.kgPerUnit;
    final lcpk = ln.landingCostPerKg;
    if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
      return 'L ${_inr(lcpk)}/kg';
    }
    return 'L ${_inr(ln.landingCost)}/${ln.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: trades.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 12, endIndent: 12),
        itemBuilder: (context, ip) {
          final p = trades[ip];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  p.humanId,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${DateFormat.yMMMd().format(p.purchaseDate)} · ${p.derivedStatus}'
                  '${(p.brokerName ?? '').isNotEmpty ? ' · ${p.brokerName}' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: Text(
                  _inr(p.totalAmount.round()),
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                onTap: () => context.push('/purchase/detail/${p.id}'),
              ),
              if (p.lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'No line items',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Column(
                    children: [
                      for (final ln in p.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  ln.itemName,
                                  style: tt.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${ln.qty % 1 == 0 ? ln.qty.toInt() : ln.qty.toStringAsFixed(1)} ${ln.unit}',
                                  textAlign: TextAlign.right,
                                  style: tt.labelSmall,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _rateL(ln),
                                  textAlign: TextAlign.right,
                                  style: tt.labelSmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                              if (ln.sellingCost != null) ...[
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'S ${_inr(ln.sellingCost!)}',
                                    textAlign: TextAlign.right,
                                    style: tt.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _inr(_lineAmountInr(ln).round()),
                                  textAlign: TextAlign.right,
                                  style: tt.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
