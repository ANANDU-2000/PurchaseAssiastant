import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../features/analytics/presentation/analytics_report_helpers.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';
import 'reports_full_list_page.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _qtyReadable(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);

String _kgReadable(double kg) {
  if (kg < 1e-9) return '0';
  if ((kg - kg.roundToDouble()).abs() < 1e-6) return '${kg.round()}';
  return kg.toStringAsFixed(1);
}

enum _DatePreset { today, week, month, year, custom }

String _presetLabel(_DatePreset p) => switch (p) {
      _DatePreset.today => 'Today',
      _DatePreset.week => 'Week',
      _DatePreset.month => 'Month',
      _DatePreset.year => 'Year',
      _DatePreset.custom => 'Custom',
    };

enum ReportsMainTab { items, suppliers, brokers }

typedef FullReportsPage = ReportsPage;

/// Smart report driven by `/trade-purchases` SSOT aggregate ([buildTradeReportAggregate]).
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  _DatePreset _preset = _DatePreset.month;
  ReportsMainTab _mainTab = ReportsMainTab.items;
  ReportPackKind _unit = ReportPackKind.bag;

  final TextEditingController _searchCtl = TextEditingController();
  String _debouncedQuery = '';
  Timer? _searchDebounce;
  Timer? _stallTimer;
  bool _stallBanner = false;

  int _visibleCap = 5;
  bool _exportingCsv = false;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onSearchTyping);
  }

  void _onSearchTyping() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _debouncedQuery = _searchCtl.text;
        _visibleCap = 5;
      });
    });
  }

  @override
  void dispose() {
    _searchCtl.removeListener(_onSearchTyping);
    _searchCtl.dispose();
    _searchDebounce?.cancel();
    _stallTimer?.cancel();
    super.dispose();
  }

  void _armStallBanner(bool loading, bool hasPurchases) {
    if (!loading || hasPurchases) {
      _stallTimer?.cancel();
      _stallTimer = null;
      if (_stallBanner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _stallBanner = false);
        });
      }
      return;
    }
    if (_stallBanner) return;
    if (_stallTimer != null) return;
    _stallTimer = Timer(const Duration(seconds: 2), () {
      _stallTimer = null;
      if (!mounted) return;
      setState(() => _stallBanner = true);
    });
  }

  void _bumpInvalidate() {
    invalidatePurchaseWorkspace(ref);
    ref.invalidate(reportsPurchasesPayloadProvider);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
    );
    if (picked == null || !mounted) return;
    ref.read(analyticsDateRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    setState(() {
      _preset = _DatePreset.custom;
      _visibleCap = 5;
    });
    _bumpInvalidate();
  }

  void _applyDatePreset(_DatePreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _DatePreset.today => (from: today, to: today),
      _DatePreset.week =>
        (from: today.subtract(const Duration(days: 6)), to: today),
      _DatePreset.month => (from: DateTime(n.year, n.month, 1), to: today),
      _DatePreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _DatePreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() {
      _preset = p;
      _visibleCap = 5;
    });
    _bumpInvalidate();
  }

  ReportsFullListKind _fullListKind() => switch (_mainTab) {
        ReportsMainTab.items => switch (_unit) {
            ReportPackKind.bag => ReportsFullListKind.itemsBag,
            ReportPackKind.box => ReportsFullListKind.itemsBox,
            ReportPackKind.tin => ReportsFullListKind.itemsTin,
          },
        ReportsMainTab.suppliers => ReportsFullListKind.suppliers,
        ReportsMainTab.brokers => ReportsFullListKind.brokers,
      };

  Future<void> _exportCsv({
    required List<TradePurchase> purchases,
    required TradeReportAgg agg,
    required ({DateTime from, DateTime to}) range,
  }) async {
    if (_exportingCsv || _exportingPdf) return;
    setState(() => _exportingCsv = true);
    try {
      final df = DateFormat('yyyy-MM-dd');
      final qf = _debouncedQuery.trim().toLowerCase();
      final buf = StringBuffer();
      buf.writeln(
        '# Purchase Assistant — Reports — ${_mainTab.name} — '
        '${df.format(range.from)} to ${df.format(range.to)}',
      );

      switch (_mainTab) {
        case ReportsMainTab.items:
          final rows = switch (_unit) {
            ReportPackKind.bag => agg.itemsBag,
            ReportPackKind.box => agg.itemsBox,
            ReportPackKind.tin => agg.itemsTin,
          };
          final filtered = qf.isEmpty
              ? rows
              : rows.where((r) => r.name.toLowerCase().contains(qf)).toList();
          if (filtered.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          final unitLabel = _unit.name;
          buf.writeln('unit,name,qty_pack,kg,amount_inr,deals');
          for (final r in filtered) {
            final qty = switch (_unit) {
              ReportPackKind.bag => r.bags,
              ReportPackKind.box => r.boxes,
              ReportPackKind.tin => r.tins,
            };
            buf.writeln([
              analyticsCsvCell(unitLabel),
              analyticsCsvCell(r.name),
              analyticsCsvCell(_qtyReadable(qty)),
              analyticsCsvCell(_kgReadable(r.kg)),
              analyticsCsvCell(r.amountInr.toStringAsFixed(0)),
              analyticsCsvCell('${r.dealIds.length}'),
            ].join(','));
          }
        case ReportsMainTab.suppliers:
          final raw = agg.suppliers;
          final filtered = qf.isEmpty
              ? raw
              : raw.where((s) => s.name.toLowerCase().contains(qf)).toList();
          if (filtered.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          buf.writeln('supplier,deals,bag_qty,bag_kg');
          for (final s in filtered) {
            buf.writeln([
              analyticsCsvCell(s.name),
              analyticsCsvCell('${s.dealIds.length}'),
              analyticsCsvCell(_qtyReadable(s.bagQty)),
              analyticsCsvCell(_kgReadable(s.bagKg)),
            ].join(','));
          }
        case ReportsMainTab.brokers:
          final raw = agg.brokers;
          final filtered = qf.isEmpty
              ? raw
              : raw.where((b) => b.name.toLowerCase().contains(qf)).toList();
          if (filtered.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          buf.writeln('broker,commission_inr,deals');
          for (final b in filtered) {
            buf.writeln([
              analyticsCsvCell(b.name),
              analyticsCsvCell(b.commission.toStringAsFixed(0)),
              analyticsCsvCell('${b.purchaseIds.length}'),
            ].join(','));
          }
      }

      await Share.share(
        buf.toString(),
        subject: 'Reports ${df.format(range.from)}–${df.format(range.to)}',
      );
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Widget _totalsTop(TradeReportTotals t) {
    final packBits = <Widget>[
      if (t.bags > 1e-9)
        Text('Bags ${_qtyReadable(t.bags)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      if (t.kg > 1e-9)
        Text('Kg ${_kgReadable(t.kg)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      if (t.boxes > 1e-9)
        Text('Box ${_qtyReadable(t.boxes)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      if (t.tins > 1e-9)
        Text('Tin ${_qtyReadable(t.tins)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HexaColors.brandCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total purchase',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: HexaColors.textBody,
                      ),
                ),
                SelectableText(
                  _inr0(t.inr),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 4,
              children: [
                ...packBits,
                if (packBits.isEmpty)
                  Text(
                    '—',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: HexaColors.textBody,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactRow(
    BuildContext ctx,
    String title,
    List<({String label, String value})> metrics,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            title,
            style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: metrics.map((m) {
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${m.label}: ',
                      style: TextStyle(
                        color: HexaColors.textBody,
                        fontSize: 13,
                      ),
                    ),
                    TextSpan(
                      text: m.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _listBody(TradeReportAgg agg) {
    final q = _debouncedQuery.trim().toLowerCase();

    switch (_mainTab) {
      case ReportsMainTab.items:
        final rows = switch (_unit) {
          ReportPackKind.bag => agg.itemsBag,
          ReportPackKind.box => agg.itemsBox,
          ReportPackKind.tin => agg.itemsTin,
        };
        final all = q.isEmpty
            ? rows
            : rows.where((r) => r.name.toLowerCase().contains(q)).toList();
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No lines for ${_unit.name} in this period.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final rowWidgets = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final r = all[i];
          final metrics = switch (_unit) {
            ReportPackKind.bag => <({String label, String value})>[
                (label: 'Bags', value: _qtyReadable(r.bags)),
                (label: 'Kg', value: _kgReadable(r.kg)),
                (label: 'Amount', value: _inr0(r.amountInr)),
                (label: 'Deals', value: '${r.dealIds.length}'),
              ],
            ReportPackKind.box => <({String label, String value})>[
                (label: 'Box', value: _qtyReadable(r.boxes)),
                (label: 'Kg', value: _kgReadable(r.kg)),
                (label: 'Amount', value: _inr0(r.amountInr)),
                (label: 'Deals', value: '${r.dealIds.length}'),
              ],
            ReportPackKind.tin => <({String label, String value})>[
                (label: 'Tin', value: _qtyReadable(r.tins)),
                (label: 'Kg', value: _kgReadable(r.kg)),
                (label: 'Amount', value: _inr0(r.amountInr)),
                (label: 'Deals', value: '${r.dealIds.length}'),
              ],
          };
          rowWidgets.add(_compactRow(context, r.name, metrics));
          if (i < cap - 1) {
            rowWidgets.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rowWidgets,
            if (cap < all.length)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (ctx) => ReportsFullListPage(
                      kind: _fullListKind(),
                      searchQuery: _debouncedQuery,
                      agg: agg,
                    ),
                  ),
                ),
                child: const Text('View more'),
              ),
          ],
        );

      case ReportsMainTab.suppliers:
        final all = q.isEmpty
            ? agg.suppliers
            : agg.suppliers
                .where((s) => s.name.toLowerCase().contains(q))
                .toList();
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No suppliers for this unit filter.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final rowWidgets = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final s = all[i];
          rowWidgets.add(_compactRow(context, s.name, [
            (label: 'Deals', value: '${s.dealIds.length}'),
            (label: 'Bags', value: _qtyReadable(s.bagQty)),
            (label: 'Kg', value: _kgReadable(s.bagKg)),
          ]));
          if (i < cap - 1) {
            rowWidgets.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rowWidgets,
            if (cap < all.length)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (ctx) => ReportsFullListPage(
                      kind: ReportsFullListKind.suppliers,
                      searchQuery: _debouncedQuery,
                      agg: agg,
                    ),
                  ),
                ),
                child: const Text('View more'),
              ),
          ],
        );

      case ReportsMainTab.brokers:
        final all = q.isEmpty
            ? agg.brokers
            : agg.brokers
                .where((b) => b.name.toLowerCase().contains(q))
                .toList();
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No broker-tagged purchases in this period.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final rowWidgets = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final b = all[i];
          rowWidgets.add(_compactRow(context, b.name, [
            (label: 'Commission', value: _inr0(b.commission)),
            (label: 'Deals', value: '${b.purchaseIds.length}'),
          ]));
          if (i < cap - 1) {
            rowWidgets.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rowWidgets,
            if (cap < all.length)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (ctx) => ReportsFullListPage(
                      kind: ReportsFullListKind.brokers,
                      searchQuery: _debouncedQuery,
                      agg: agg,
                    ),
                  ),
                ),
                child: const Text('View more'),
              ),
          ],
        );
    }
  }

  Future<void> _shareStatementPdf(List<TradePurchase> purchases) async {
    if (_exportingPdf || _exportingCsv) return;
    final range = ref.read(analyticsDateRangeProvider);
    final biz = ref.read(invoiceBusinessProfileProvider);
    if (purchases.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to export for this period.')),
        );
      }
      return;
    }
    setState(() => _exportingPdf = true);
    try {
      await layoutTradeStatementSsotPdf(
        business: biz,
        from: range.from,
        to: range.to,
        purchases: purchases,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(reportsPurchasesPayloadProvider);
    final hive = ref.watch(reportsPurchasesHiveCacheProvider);
    final merged = purchasesAsync.value?.items ?? hive ?? const <TradePurchase>[];
    final fromLive = purchasesAsync.value?.fromLiveFetch ?? false;
    _armStallBanner(purchasesAsync.isLoading, merged.isNotEmpty);

    final range = ref.watch(analyticsDateRangeProvider);
    final rangeFmt =
        '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}';

    final agg = buildTradeReportAgg(merged, onlyKind: _unit);

    final session = ref.watch(sessionProvider);
    final showSkeleton =
        purchasesAsync.isLoading && merged.isEmpty && !_stallBanner;
    final showEmpty = merged.isEmpty && (!purchasesAsync.isLoading || _stallBanner);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: GoRouter.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text('Reports'),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'Export statement PDF',
            onPressed:
                (_exportingCsv || _exportingPdf) ? null : () => _shareStatementPdf(merged),
            icon: _exportingPdf
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: (_exportingCsv || _exportingPdf || merged.isEmpty)
                ? null
                : () => _exportCsv(
                      purchases: merged,
                      agg: agg,
                      range: range,
                    ),
            icon: _exportingCsv
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
          ShellQuickRefActions(
            onRefresh: _bumpInvalidate,
          ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : RefreshIndicator(
              onRefresh: () async {
                _bumpInvalidate();
                await ref.read(reportsPurchasesPayloadProvider.future);
              },
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                children: [
                  if (purchasesAsync.isLoading && merged.isNotEmpty)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_stallBanner && purchasesAsync.isLoading && merged.isEmpty)
                    Material(
                      color: Colors.amber.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(Icons.sync, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Updating…',
                                style: TextStyle(color: Colors.amber.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!fromLive && merged.isNotEmpty)
                    Material(
                      color: HexaColors.brandCard,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off_rounded,
                                size: 18, color: HexaColors.textBody),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Showing last saved report data.',
                                style: TextStyle(
                                    fontSize: 12, color: HexaColors.textBody),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Card(
                    margin: EdgeInsets.zero,
                    color: HexaColors.brandCard,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: HexaColors.brandBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                      child: Row(
                        children: [
                          PopupMenuButton<_DatePreset>(
                            tooltip: 'Date range',
                            onSelected: (p) {
                              if (p == _DatePreset.custom) {
                                _pickCustomRange();
                              } else {
                                _applyDatePreset(p);
                              }
                            },
                            itemBuilder: (ctx) => _DatePreset.values
                                .map(
                                  (p) => PopupMenuItem(
                                    value: p,
                                    child: Text(_presetLabel(p)),
                                  ),
                                )
                                .toList(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _presetLabel(_preset),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const Icon(Icons.expand_more_rounded, size: 18),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              rangeFmt,
                              style: TextStyle(
                                fontSize: 12,
                                color: HexaColors.textBody,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _totalsTop(agg.totals),
                  const SizedBox(height: 8),
                  SegmentedButton<ReportsMainTab>(
                    segments: const [
                      ButtonSegment(
                          value: ReportsMainTab.items, label: Text('Items')),
                      ButtonSegment(
                          value: ReportsMainTab.suppliers,
                          label: Text('Suppliers')),
                      ButtonSegment(
                          value: ReportsMainTab.brokers,
                          label: Text('Brokers')),
                    ],
                    selected: {_mainTab},
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setState(() {
                        _mainTab = s.first;
                        _visibleCap = 5;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ReportPackKind>(
                    segments: const [
                      ButtonSegment(
                          value: ReportPackKind.bag, label: Text('Bag')),
                      ButtonSegment(
                          value: ReportPackKind.box, label: Text('Box')),
                      ButtonSegment(
                          value: ReportPackKind.tin, label: Text('Tin')),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setState(() {
                        _unit = s.first;
                        _visibleCap = 5;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      isDense: true,
                      filled: true,
                      fillColor: HexaColors.brandCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: HexaColors.brandBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: HexaColors.brandBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (showSkeleton)
                    const ListSkeleton(
                      rowCount: 5,
                      rowHeight: 72,
                      padding: EdgeInsets.fromLTRB(0, 0, 0, 24),
                    )
                  else if (showEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No purchases in selected period',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: HexaColors.textBody,
                        ),
                      ),
                    )
                  else
                    _listBody(agg),
                ],
              ),
            ),
    );
  }
}
