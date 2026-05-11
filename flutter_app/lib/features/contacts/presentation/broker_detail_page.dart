import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/services/broker_statement_pdf.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/trade/trade_line_profit.dart';
import '../../../core/utils/trade_purchase_commission.dart';
import '../../../core/providers/purchase_prefill_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/trade_purchase_ledger_cards.dart';
import '../../../shared/widgets/search_picker_sheet.dart';

final _brokerProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, brokerId) async {
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
  /// '7' | '30' | '90' | '0' (all time) — matches [DropdownButton] value.
  late   String _rangePreset;
  bool _loading = false;
  Map<String, dynamic>? _metrics;
  /// Trades for [_from, _to] (broker-filtered) — used for chart; single source: trade purchase lines.
  List<TradePurchase> _rangeTrades = const [];

  @override
  void initState() {
    super.initState();
    _to = _dOnly(DateTime.now());
    _from = _to.subtract(const Duration(days: 89));
    _rangePreset = '90';
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    // Bust the Riverpod detail provider so the header (name, commission, etc.)
    // always reflects the latest server state, not just metrics/entries.
    ref.invalidate(_brokerProvider(widget.brokerId));
    setState(() => _loading = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final api = ref.read(hexaApiProvider);
    final f = fmt.format(_from);
    final t = fmt.format(_to);
    try {
      final m = await api.brokerMetrics(
          businessId: session.primaryBusiness.id,
          brokerId: widget.brokerId,
          from: f,
          to: t);
      var rangeTrades = <TradePurchase>[];
      try {
        const page = 200;
        for (var off = 0; off < 20000; off += page) {
          final traw = await api.listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: page,
            offset: off,
            status: 'all',
            brokerId: widget.brokerId,
          );
          if (traw.isEmpty) break;
          for (final row in traw) {
            try {
              rangeTrades.add(
                TradePurchase.fromJson(
                    Map<String, dynamic>.from(row as Map)),
              );
            } catch (_) {}
          }
          if (traw.length < page) break;
        }
        rangeTrades = rangeTrades.where(_inSelectedRange).toList();
        rangeTrades.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      } catch (_) {}
      if (mounted) {
        setState(() {
          _metrics = m;
          _rangeTrades = rangeTrades;
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

  Future<void> _shareBrokerStatementPdf() async {
    final session = ref.read(sessionProvider);
    if (session == null || _rangeTrades.isEmpty) return;
    final biz = ref.read(invoiceBusinessProfileProvider);
    final bro = ref.read(_brokerProvider(widget.brokerId)).valueOrNull;
    final name = bro?['name']?.toString() ?? 'Broker';
    final phone = bro?['phone']?.toString();
    try {
      await shareBrokerStatementPdf(
        business: biz,
        brokerName: name,
        brokerPhone: phone,
        purchases: _rangeTrades,
        fromDate: _from,
        toDate: _to,
      );
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create PDF. ${userFacingError(e)}')),
        );
      }
    }
  }

  void _preset(int days) {
    final n = _dOnly(DateTime.now());
    setState(() {
      _to = n;
      _from = days <= 0 ? DateTime(2020) : n.subtract(Duration(days: days - 1));
      _rangePreset = days <= 0 ? '0' : '$days';
    });
    _reload();
  }

  bool _inSelectedRange(TradePurchase p) {
    final d = _dOnly(p.purchaseDate);
    return !d.isBefore(_from) && !d.isAfter(_to);
  }

  /// Month key -> gross line profit, commission (same as PDF/wizard) by purchase month.
  Map<String, ({double gross, double commission})> _monthly() {
    final out = <String, ({double gross, double commission})>{};
    for (final p in _rangeTrades) {
      final ed = p.purchaseDate.toIso8601String().split('T').first;
      if (ed.length < 7) continue;
      final mk = ed.substring(0, 7);
      var g = 0.0;
      for (final ln in p.lines) {
        g += estimatedTradeLineProfit(ln);
      }
      final comm = tradePurchaseCommissionInr(p);
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
            BarChartRodData(
                toY: row.gross,
                width: 10,
                color: HexaColors.primaryMid,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3))),
            BarChartRodData(
                toY: net,
                width: 10,
                color: HexaColors.profit,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3))),
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
      floatingActionButton: async.maybeWhen(
        data: (_) => FloatingActionButton.extended(
          onPressed: () {
            ref.read(pendingPurchaseBrokerIdProvider.notifier).state =
                widget.brokerId;
            context.pushNamed('purchase_new');
          },
          backgroundColor: const Color(0xFF17A8A7),
          foregroundColor: Colors.white,
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
          data: (b) => Text(
            b['name']?.toString() ?? 'Broker',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          orElse: () => const Text('Broker'),
        ),
        actions: [
          IconButton(
            tooltip: 'Broker statement PDF',
            onPressed: _loading || _rangeTrades.isEmpty
                ? null
                : _shareBrokerStatementPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Trade purchase ledger',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/broker/${widget.brokerId}/ledger'),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load broker',
          onRetry: () => ref.invalidate(_brokerProvider(widget.brokerId)),
        ),
        data: (b) {
          final cs = Theme.of(context).colorScheme;
          final viewW = MediaQuery.sizeOf(context).width;
          final compactLedger = viewW < 560;
          final ledgerT = ledgerMoneyKgTotals(_rangeTrades,
              include: defaultActiveBill);
          final ledgerC = ledgerContainerHints(_rangeTrades,
              include: defaultActiveBill);
          final inrLedger = NumberFormat.currency(
            locale: 'en_IN',
            symbol: '₹',
            decimalDigits: 0,
          );
          final ct = b['commission_type']?.toString() ?? '';
          final cv = b['commission_value'];
          final badgeLabel = ct == 'flat'
              ? '₹ Fixed'
              : ct == 'percent'
                  ? '% of deal'
                  : ct;
          return RefreshIndicator(
            onRefresh: _reload,
            child: SafeArea(
              bottom: false,
              child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              children: [
                Text('Date range',
                    style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () async {
                    const rows = [
                      SearchPickerRow<String>(value: '7', title: 'Last 7 days'),
                      SearchPickerRow<String>(value: '30', title: 'Last 30 days'),
                      SearchPickerRow<String>(value: '90', title: 'Last 90 days'),
                      SearchPickerRow<String>(value: '0', title: 'All time'),
                    ];
                    final v = await showSearchPickerSheet<String>(
                      context: context,
                      title: 'Date range',
                      rows: rows,
                      selectedValue: _rangePreset,
                      initialChildFraction: 0.42,
                    );
                    if (!context.mounted || v == null) return;
                    _preset(int.parse(v));
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      switch (_rangePreset) {
                        '7' => 'Last 7 days',
                        '30' => 'Last 30 days',
                        '90' => 'Last 90 days',
                        _ => 'All time',
                      },
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${fmt.format(_from)} – ${fmt.format(_to)}',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((b['image_url'] ?? '').toString().trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            b['image_url'].toString().trim(),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 56,
                              height: 56,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        b['name']?.toString() ?? '—',
                        style: tt.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Chip(
                  avatar: Icon(
                      ct == 'flat'
                          ? Icons.payments_rounded
                          : Icons.percent_rounded,
                      size: 18,
                      color: HexaColors.primaryMid),
                  label: Text('$badgeLabel${cv != null ? ' · $cv' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  side: const BorderSide(color: HexaColors.border),
                  backgroundColor:
                      HexaColors.primaryLight.withValues(alpha: 0.65),
                ),
                Builder(builder: (ctx) {
                  final raw = b['last_purchase_date']?.toString() ?? '';
                  if (raw.length < 10) return const SizedBox(height: 8);
                  final parsed = DateTime.tryParse(raw.substring(0, 10));
                  if (parsed == null) return const SizedBox(height: 8);
                  final days = DateTime.now().difference(parsed).inDays;
                  final ago = days == 0
                      ? 'today'
                      : days == 1
                          ? 'yesterday'
                          : '$days days ago';
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Chip(
                      avatar: Icon(Icons.history, size: 16, color: cs.primary),
                      label: Text(
                        'Last buy ${DateFormat('MMM d').format(parsed)} · $ago',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator()))
                else if (_metrics != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        children: [
                          _metricRow(
                            context,
                            'Deals',
                            '${(_metrics!['deals'] as num?)?.toInt() ?? 0}',
                          ),
                          const Divider(height: 20),
                          _metricRow(
                            context,
                            'Commission',
                            '₹${((_metrics!['total_commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          ),
                          const Divider(height: 20),
                          _metricRow(
                            context,
                            'Linked profit',
                            '₹${((_metrics!['total_profit'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          ),
                          const Divider(height: 20),
                          _metricRow(
                            context,
                            'Net (profit − comm.)',
                            () {
                              final tp = (_metrics!['total_profit'] as num?)
                                      ?.toDouble() ??
                                  0;
                              final tc = (_metrics!['total_commission']
                                          as num?)
                                      ?.toDouble() ??
                                  0;
                              return '₹${(tp - tc).toStringAsFixed(0)}';
                            }(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TradeLedgerSummaryStrip(
                    bills: ledgerT.bills,
                    inrSpend: inrLedger.format(ledgerT.spend.round()),
                    kg: ledgerT.kg,
                    bags: ledgerC.bags,
                    boxes: ledgerC.boxes,
                    tins: ledgerC.tins,
                    subtitle:
                        '${fmt.format(_from)} – ${fmt.format(_to)} · trade PUR',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Trade purchases (PUR)',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  TradeLedgerCardList(
                    trades: _rangeTrades,
                    useCompactLines: compactLedger,
                    emptyHint:
                        'No PUR bills with this broker in this date range.',
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading:
                        Icon(Icons.receipt_long_outlined, size: 20, color: cs.primary),
                    title: Text(
                      'Full PUR ledger',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () =>
                        context.push('/broker/${widget.brokerId}/ledger'),
                  ),
                  const SizedBox(height: 20),
                  Text('Commission impact (monthly)',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Teal = gross line profit · Green = after commission',
                      style: tt.labelSmall
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    Text('No broker-linked trade purchases in this range.',
                        style: tt.bodySmall
                            ?.copyWith(color: HexaColors.textSecondary))
                  else
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: groups.fold<double>(1, (m, g) {
                                final a = g.barRods
                                    .map((r) => r.toY)
                                    .fold<double>(0, (a, b) => a > b ? a : b);
                                return m > a ? m : a;
                              }) *
                              1.15,
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
                                  if (i < 0 || i >= keys.length) {
                                    return const SizedBox.shrink();
                                  }
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
                                getTitlesWidget: (v, _) => Text(
                                    v >= 1000
                                        ? '${(v / 1000).toStringAsFixed(0)}k'
                                        : v.toStringAsFixed(0),
                                    style: tt.labelSmall),
                              ),
                            ),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          barGroups: groups,
                        ),
                      ),
                    ),
                ],
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _metricRow(BuildContext context, String label, String value) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: tt.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
