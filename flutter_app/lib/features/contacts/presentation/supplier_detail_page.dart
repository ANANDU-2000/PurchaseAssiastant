import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
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
                    style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface),
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
  List<dynamic>? _entries;
  List<Map<String, dynamic>>? _supplierRankRows;

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
      final e = await api.listEntries(
          businessId: session.primaryBusiness.id,
          from: f,
          to: t,
          supplierId: widget.supplierId);
      List<Map<String, dynamic>>? rank;
      try {
        rank = await api.analyticsSuppliers(
            businessId: session.primaryBusiness.id, from: f, to: t);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _metrics = m;
          _entries = e;
          _supplierRankRows = rank;
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
    final items = _entries;
    if (items == null || items.isEmpty) return [];
    final byDay = <String, List<double>>{};
    for (final raw in items) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw);
      final ed = e['entry_date'];
      if (ed == null) continue;
      final ds = ed.toString().split('T').first;
      final lines = e['lines'];
      if (lines is! List) continue;
      for (final ln in lines) {
        if (ln is! Map) continue;
        final lc = (ln['landing_cost'] as num?)?.toDouble();
        if (lc == null || lc <= 0) continue;
        byDay.putIfAbsent(ds, () => []).add(lc);
      }
    }
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
    final buf = StringBuffer('date,items,qty,avg_landing,profit\n');
    final rows = _entries;
    if (rows == null) return;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw);
      final d = e['entry_date']?.toString().split('T').first ?? '';
      final lines = e['lines'];
      if (lines is! List) continue;
      double q = 0, p = 0;
      final names = <String>[];
      for (final ln in lines) {
        if (ln is! Map) continue;
        final m = Map<String, dynamic>.from(ln);
        q += (m['qty'] as num?)?.toDouble() ?? 0;
        p += (m['profit'] as num?)?.toDouble() ?? 0;
        names.add(m['item_name']?.toString() ?? '');
      }
      var avgL = 0.0;
      if (lines.isNotEmpty) {
        var s = 0.0;
        for (final ln in lines) {
          if (ln is! Map) continue;
          s += (Map<String, dynamic>.from(ln)['landing_cost'] as num?)
                  ?.toDouble() ??
              0;
        }
        avgL = s / lines.length;
      }
      buf.writeln('$d,"${names.join(';')}",$q,$avgL,$p');
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
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop()),
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
            onPressed:
                _entries == null || _entries!.isEmpty ? null : _exportCsv,
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ChipPill(
                                label: '7d',
                                onTap: () => _preset(7),
                                onGradient: false),
                            _ChipPill(
                                label: '30d',
                                onTap: () => _preset(30),
                                onGradient: false),
                            _ChipPill(
                                label: '90d',
                                onTap: () => _preset(90),
                                onGradient: false),
                            _ChipPill(
                              label: 'YTD',
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
                                onTap: () => _preset(0),
                                onGradient: false),
                          ],
                        ),
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
                      Text('Purchase history',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text('${_entries?.length ?? 0} entries',
                          style: tt.labelSmall
                              ?.copyWith(color: HexaColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((_entries ?? []).isEmpty)
                    HexaEmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No purchases from this supplier yet',
                      subtitle:
                          'Add a purchase and link it to this supplier to see metrics.',
                      primaryActionLabel: 'Add purchase',
                      onPrimaryAction: () => context.push('/purchase/new'),
                    )
                  else
                    _EntryTable(entries: _entries ?? []),
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
    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          SizedBox(
              width: w,
              child: _SupplierStatCard(
                  icon: Icons.receipt_long_rounded,
                  label: 'Deals',
                  value: '$deals',
                  accent: const Color(0xFF1A6B8A))),
          const SizedBox(width: 12),
          SizedBox(
              width: w,
              child: _SupplierStatCard(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Purchase',
                  value: '₹${pam.toStringAsFixed(0)}',
                  accent: const Color(0xFF3949AB))),
          const SizedBox(width: 12),
          SizedBox(
              width: w,
              child: _SupplierStatCard(
                  icon: Icons.scale_rounded,
                  label: 'Total qty',
                  value: tq.toStringAsFixed(1),
                  accent: const Color(0xFF6A1B9A))),
          const SizedBox(width: 12),
          SizedBox(
              width: w,
              child: _SupplierStatCard(
                  icon: Icons.price_change_outlined,
                  label: 'Avg landing',
                  value: '₹${al.toStringAsFixed(2)}',
                  accent: const Color(0xFFFF9800))),
          const SizedBox(width: 12),
          SizedBox(
              width: w,
              child: _SupplierStatCard(
                  icon: Icons.trending_up_rounded,
                  label: 'Total profit',
                  value: '₹${tp.toStringAsFixed(0)}',
                  accent: HexaColors.profit)),
          const SizedBox(width: 12),
          SizedBox(
              width: w,
              child: _SupplierStatCard(
                  icon: Icons.percent_rounded,
                  label: 'Avg margin',
                  value: '${margin.toStringAsFixed(1)}%',
                  accent: HexaColors.accentAmber)),
        ],
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  const _ChipPill(
      {required this.label, required this.onTap, this.onGradient = false});

  final String label;
  final VoidCallback onTap;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final child = onGradient
        ? ActionChip(
            label: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
            onPressed: onTap,
          )
        : ActionChip(label: Text(label), onPressed: onTap);
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

class _EntryTable extends StatelessWidget {
  const _EntryTable({required this.entries});

  final List<dynamic> entries;

  String _inr(num v) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Items')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Avg ₹')),
            DataColumn(label: Text('Profit')),
            DataColumn(label: Text('Margin %')),
          ],
          rows: [
            for (final raw in entries)
              if (raw is Map)
                _buildRow(context, Map<String, dynamic>.from(raw), tt),
          ],
        ),
      ),
    );
  }

  DataRow _buildRow(
      BuildContext context, Map<String, dynamic> e, TextTheme tt) {
    final d = e['entry_date']?.toString().split('T').first ?? '';
    final lines = e['lines'];
    double q = 0, profit = 0;
    double sales = 0;
    final names = <String>[];
    if (lines is List) {
      for (final ln in lines) {
        if (ln is! Map) continue;
        final m = Map<String, dynamic>.from(ln);
        q += (m['qty'] as num?)?.toDouble() ?? 0;
        profit += (m['profit'] as num?)?.toDouble() ?? 0;
        final sp = (m['selling_price'] as num?)?.toDouble();
        if (sp != null) {
          sales += ((m['qty'] as num?)?.toDouble() ?? 0) * sp;
        }
        names.add(m['item_name']?.toString() ?? '');
      }
    }
    var avgL = 0.0;
    if (lines is List && lines.isNotEmpty) {
      var s = 0.0;
      for (final ln in lines) {
        if (ln is! Map) continue;
        s += (Map<String, dynamic>.from(ln)['landing_cost'] as num?)
                ?.toDouble() ??
            0;
      }
      avgL = s / lines.length;
    }
    final id = e['id']?.toString();
    final margin = sales > 0 ? (profit / sales) * 100 : null;
    return DataRow(
      onSelectChanged: id == null
          ? null
          : (_) {
              context.push('/entry/$id');
            },
      cells: [
        DataCell(Text(d, style: tt.labelMedium)),
        DataCell(SizedBox(
            width: 140,
            child: Text(names.take(3).join(', '),
                overflow: TextOverflow.ellipsis))),
        DataCell(Text(q.toStringAsFixed(1))),
        DataCell(Text(_inr(avgL))),
        DataCell(Text(_inr(profit),
            style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
        DataCell(Text(
          margin == null ? '—' : '${margin.toStringAsFixed(1)}%',
          style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        )),
      ],
    );
  }
}
