import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';

final _brokerProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, brokerId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getBroker(
        businessId: session.primaryBusiness.id,
        brokerId: brokerId,
      );
});

DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class BrokerDetailPage extends ConsumerStatefulWidget {
  const BrokerDetailPage({super.key, required this.brokerId});

  final String brokerId;

  @override
  ConsumerState<BrokerDetailPage> createState() => _BrokerDetailPageState();
}

class _BrokerDetailPageState extends ConsumerState<BrokerDetailPage> {
  late DateTime _to;
  late DateTime _from;
  bool _loading = false;
  Map<String, dynamic>? _metrics;
  List<dynamic>? _entries;

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
    setState(() => _loading = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final api = ref.read(hexaApiProvider);
    final f = fmt.format(_from);
    final t = fmt.format(_to);
    try {
      final m = await api.brokerMetrics(businessId: session.primaryBusiness.id, brokerId: widget.brokerId, from: f, to: t);
      final e = await api.listEntries(businessId: session.primaryBusiness.id, from: f, to: t, brokerId: widget.brokerId);
      if (mounted) {
        setState(() {
          _metrics = m;
          _entries = e;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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

  /// Month key -> gross line profit, commission allocated by entry month.
  Map<String, ({double gross, double commission})> _monthly() {
    final out = <String, ({double gross, double commission})>{};
    final items = _entries;
    if (items == null) return out;
    for (final raw in items) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw);
      final ed = e['entry_date']?.toString().split('T').first;
      if (ed == null || ed.length < 7) continue;
      final mk = ed.substring(0, 7);
      final comm = (e['commission_amount'] as num?)?.toDouble() ?? 0;
      final lines = e['lines'];
      var g = 0.0;
      if (lines is List) {
        for (final ln in lines) {
          if (ln is! Map) continue;
          g += (Map<String, dynamic>.from(ln)['profit'] as num?)?.toDouble() ?? 0;
        }
      }
      final prev = out[mk] ?? (gross: 0.0, commission: 0.0);
      out[mk] = (gross: prev.gross + g, commission: prev.commission + comm);
    }
    return out;
  }

  List<BarChartGroupData> _barGroups() {
    final m = _monthly();
    final keys = m.keys.toList()..sort();
    if (keys.isEmpty) return [];
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final row = m[k]!;
      final net = (row.gross - row.commission).clamp(0.0, 1e15);
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 4,
          groupVertically: true,
          barRods: [
            BarChartRodData(toY: row.gross, width: 10, color: HexaColors.primaryMid, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
            BarChartRodData(toY: net, width: 10, color: HexaColors.profit, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
          ],
        ),
      );
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_brokerProvider(widget.brokerId));
    final tt = Theme.of(context).textTheme;
    final fmt = DateFormat.yMMMd();
    final groups = _barGroups();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: async.maybeWhen(
          data: (b) => Text(b['name']?.toString() ?? 'Broker'),
          orElse: () => const Text('Broker'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (b) {
          final ct = b['commission_type']?.toString() ?? '';
          final cv = b['commission_value'];
          final badgeLabel = ct == 'flat' ? '₹ Fixed' : ct == 'percent' ? '% of deal' : ct;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(label: const Text('7d'), onPressed: () => _preset(7)),
                      const SizedBox(width: 8),
                      ActionChip(label: const Text('30d'), onPressed: () => _preset(30)),
                      const SizedBox(width: 8),
                      ActionChip(label: const Text('90d'), onPressed: () => _preset(90)),
                      const SizedBox(width: 8),
                      ActionChip(label: const Text('All'), onPressed: () => _preset(0)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${fmt.format(_from)} – ${fmt.format(_to)}', style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary)),
                ),
                Text(b['name']?.toString() ?? '—', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Chip(
                  avatar: Icon(ct == 'flat' ? Icons.payments_rounded : Icons.percent_rounded, size: 18, color: HexaColors.primaryMid),
                  label: Text('$badgeLabel${cv != null ? ' · $cv' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  side: BorderSide(color: HexaColors.border),
                  backgroundColor: HexaColors.primaryLight.withValues(alpha: 0.65),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                else if (_metrics != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _miniStat(context, 'Deals', '${(_metrics!['deals'] as num?)?.toInt() ?? 0}', Icons.receipt_long_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _miniStat(
                          context,
                          'Commission',
                          '₹${((_metrics!['total_commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          Icons.payments_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _miniStat(
                          context,
                          'Linked profit',
                          '₹${((_metrics!['total_profit'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          Icons.trending_up_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _miniStat(
                          context,
                          'Net (profit − comm.)',
                          () {
                            final tp = (_metrics!['total_profit'] as num?)?.toDouble() ?? 0;
                            final tc = (_metrics!['total_commission'] as num?)?.toDouble() ?? 0;
                            return '₹${(tp - tc).toStringAsFixed(0)}';
                          }(),
                          Icons.balance_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Commission impact (monthly)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Teal = gross line profit · Green = after commission', style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    Text('No broker-linked entries in this range.', style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary))
                  else
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: groups.fold<double>(1, (m, g) {
                            final a = g.barRods.map((r) => r.toY).fold<double>(0, (a, b) => a > b ? a : b);
                            return m > a ? m : a;
                          }) * 1.15,
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                getTitlesWidget: (v, _) {
                                  final keys = _monthly().keys.toList()..sort();
                                  final i = v.toInt();
                                  if (i < 0 || i >= keys.length) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(keys[i], style: tt.labelSmall),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                getTitlesWidget: (v, _) => Text(v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0), style: tt.labelSmall),
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          barGroups: groups,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value, IconData icon) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: HexaColors.primaryMid),
            const SizedBox(height: 8),
            Text(label, style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
