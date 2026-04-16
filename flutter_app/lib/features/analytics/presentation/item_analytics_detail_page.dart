import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../entries/presentation/entry_create_sheet.dart';

final _pipProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemName) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).priceIntelligence(
        businessId: session.primaryBusiness.id,
        item: itemName,
        priceField: 'landing',
      );
});

class ItemAnalyticsDetailPage extends ConsumerStatefulWidget {
  const ItemAnalyticsDetailPage({super.key, required this.itemName});

  final String itemName;

  @override
  ConsumerState<ItemAnalyticsDetailPage> createState() =>
      _ItemAnalyticsDetailPageState();
}

class _ItemAnalyticsDetailPageState
    extends ConsumerState<ItemAnalyticsDetailPage> {
  /// 0=name, 1=avg landing, 2=deals, 3=total profit
  int _sortColumn = 1;
  bool _asc = true;

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  double _positionPct(Map<String, dynamic> p) {
    final pos = p['position_pct'];
    if (pos is num) return pos.toDouble().clamp(0, 100);
    final low = (p['low'] as num?)?.toDouble();
    final high = (p['high'] as num?)?.toDouble();
    final last = (p['last_price'] as num?)?.toDouble();
    if (low == null || high == null || last == null || high <= low) return 50;
    return ((last - low) / (high - low) * 100).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_pipProvider(widget.itemName));
    final tt = Theme.of(context).textTheme;
    final onSurf = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: onSurf),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.itemName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: onSurf,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          onRetry: () => ref.invalidate(_pipProvider(widget.itemName)),
        ),
        data: (p) {
          final hints = (p['decision_hints'] as List<dynamic>?) ?? [];
          final sup = (p['supplier_compare'] as List<dynamic>?) ?? [];
          final low = (p['low'] as num?)?.toDouble();
          final high = (p['high'] as num?)?.toDouble();
          final last = (p['last_price'] as num?)?.toDouble();
          final avg = (p['avg'] as num?)?.toDouble();
          final pos = _positionPct(p);

          final rows =
              sup.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          rows.sort((a, b) {
            int c;
            switch (_sortColumn) {
              case 0:
                c = (a['name']?.toString() ?? '')
                    .compareTo(b['name']?.toString() ?? '');
                break;
              case 1:
                c = ((a['avg_landing'] as num?) ?? 0)
                    .compareTo((b['avg_landing'] as num?) ?? 0);
                break;
              case 2:
                c = ((a['deals'] as num?) ?? 0)
                    .compareTo((b['deals'] as num?) ?? 0);
                break;
              default:
                c = ((a['total_profit'] as num?) ?? 0)
                    .compareTo((b['total_profit'] as num?) ?? 0);
            }
            return _asc ? c : -c;
          });
          final best = rows.isEmpty
              ? null
              : rows.reduce((a, b) {
                  final va = (a['avg_landing'] as num?) ?? 1e18;
                  final vb = (b['avg_landing'] as num?) ?? 1e18;
                  return va <= vb ? a : b;
                });

          final bestAvg = (best?['avg_landing'] as num?)?.toDouble();
          final savings = (avg != null && bestAvg != null)
              ? (avg - bestAvg).clamp(-1e12, 1e12)
              : null;

          Map<String, dynamic>? buyRow;
          var maxProfit = -1e18;
          for (final r in rows) {
            final tp = (r['total_profit'] as num?)?.toDouble() ?? 0;
            if (tp > maxProfit) {
              maxProfit = tp;
              buyRow = r;
            }
          }

          final historyRaw = (p['price_history'] as List<dynamic>?) ?? [];
          final historyPts = <({DateTime? d, double p})>[];
          for (final e in historyRaw) {
            if (e is! Map) continue;
            final ds = e['d']?.toString();
            final pv = (e['p'] as num?)?.toDouble();
            if (ds == null || pv == null) continue;
            DateTime? dt;
            try {
              dt = DateTime.parse(ds);
            } catch (_) {}
            historyPts.add((d: dt, p: pv));
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(_pipProvider(widget.itemName)),
            color: HexaColors.primaryMid,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                28 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _DecisionCard(
                  itemName: widget.itemName,
                  best: best,
                  bestLanding: bestAvg,
                  savingsVsAvg: savings,
                  positionPct: pos,
                  hintLine:
                      hints.isNotEmpty ? hints.first.toString() : null,
                  inr: _inr,
                  onAddPurchase: () => showEntryCreateSheet(context),
                ),
                const SizedBox(height: 16),
                if (historyPts.length >= 2)
                  _PriceHistoryLineChart(
                    points: historyPts,
                    inr: _inr,
                  ),
                if (historyPts.length >= 2) const SizedBox(height: 16),
                if (rows.isNotEmpty)
                  _SupplierDealsDonut(
                    rows: rows,
                  ),
                if (rows.isNotEmpty) const SizedBox(height: 16),
                Text(
                  'Price position (landing)',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: onSurf,
                  ),
                ),
                const SizedBox(height: 8),
                if (low != null && high != null && last != null)
                  Text(
                    '${_inr(low)} min · ${_inr(high)} max · last ${_inr(last)}',
                    style: tt.labelMedium?.copyWith(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: pos / 100,
                    minHeight: 8,
                    backgroundColor: context.adaptiveElevated,
                    color: pos > 66
                        ? HexaColors.warning
                        : (pos < 33
                            ? HexaColors.profit
                            : HexaColors.primaryMid),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${pos.toStringAsFixed(0)}% in range · Avg ${_inr(avg)}',
                  style: tt.labelSmall?.copyWith(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Key numbers',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: onSurf,
                  ),
                ),
                const SizedBox(height: 10),
                _MetricTable(
                  rows: [
                    ('Avg', _inr(avg)),
                    ('Low', _inr(low)),
                    ('High', _inr(high)),
                    ('Last', _inr(last)),
                    ('Trend', p['trend']?.toString() ?? '—'),
                    ('Frequency', '${p['frequency'] ?? 0}'),
                  ],
                ),
                if (hints.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Verdicts',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: onSurf,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...hints.map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: HexaColors.accentAmber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: HexaColors.accentAmber
                                  .withValues(alpha: 0.45)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.tips_and_updates_rounded,
                                size: 20, color: HexaColors.accentAmber),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(h.toString(),
                                    style: tt.bodySmall?.copyWith(
                                        color: onSurf,
                                        height: 1.35))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Suppliers',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: onSurf,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Name'),
                      selected: _sortColumn == 0,
                      onSelected: (_) => setState(() {
                        if (_sortColumn == 0) {
                          _asc = !_asc;
                        } else {
                          _sortColumn = 0;
                          _asc = true;
                        }
                      }),
                      selectedColor: HexaColors.primaryLight,
                      checkmarkColor: HexaColors.primaryDeep,
                    ),
                    FilterChip(
                      label: const Text('Avg ₹'),
                      selected: _sortColumn == 1,
                      onSelected: (_) => setState(() {
                        if (_sortColumn == 1) {
                          _asc = !_asc;
                        } else {
                          _sortColumn = 1;
                          _asc = true;
                        }
                      }),
                      selectedColor: HexaColors.primaryLight,
                      checkmarkColor: HexaColors.primaryDeep,
                    ),
                    FilterChip(
                      label: const Text('Deals'),
                      selected: _sortColumn == 2,
                      onSelected: (_) => setState(() {
                        if (_sortColumn == 2) {
                          _asc = !_asc;
                        } else {
                          _sortColumn = 2;
                          _asc = false;
                        }
                      }),
                      selectedColor: HexaColors.primaryLight,
                      checkmarkColor: HexaColors.primaryDeep,
                    ),
                    FilterChip(
                      label: const Text('Profit'),
                      selected: _sortColumn == 3,
                      onSelected: (_) => setState(() {
                        if (_sortColumn == 3) {
                          _asc = !_asc;
                        } else {
                          _sortColumn = 3;
                          _asc = false;
                        }
                      }),
                      selectedColor: HexaColors.primaryLight,
                      checkmarkColor: HexaColors.primaryDeep,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No supplier breakdown for this item yet.',
                        style: tt.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  )
                else
                  ...rows.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SupplierCompareTile(
                        row: m,
                        inr: _inr,
                        isTopProfit: buyRow != null &&
                            m['supplier_id']?.toString() ==
                                buyRow['supplier_id']?.toString(),
                        onSurf: onSurf,
                        onTap: () {
                          final sid = m['supplier_id']?.toString();
                          if (sid != null && sid.isNotEmpty) {
                            context.push('/supplier/$sid');
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.itemName,
    required this.best,
    required this.bestLanding,
    required this.savingsVsAvg,
    required this.positionPct,
    this.hintLine,
    required this.inr,
    required this.onAddPurchase,
  });

  final String itemName;
  final Map<String, dynamic>? best;
  final double? bestLanding;
  final double? savingsVsAvg;
  final double positionPct;
  final String? hintLine;
  final String Function(num?) inr;
  final VoidCallback onAddPurchase;

  String _narrative() {
    if (hintLine != null && hintLine!.trim().isNotEmpty) {
      return hintLine!.trim();
    }
    if (positionPct <= 33) {
      return 'You are buying at a good price vs your recent range.';
    }
    if (positionPct >= 66) {
      return 'Latest landing is high — negotiate or try another supplier.';
    }
    return 'Landing is mid-range vs your history.';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = best?['name']?.toString();
    return Card(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              itemName,
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _narrative(),
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (name != null && bestLanding != null) ...[
              Text(
                'Best supplier: $name — ${inr(bestLanding)}/unit',
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  height: 1.15,
                  color: cs.onSurface,
                ),
              ),
              if (savingsVsAvg != null && savingsVsAvg! > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'You save ${inr(savingsVsAvg)} vs others on average',
                  style: tt.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ] else
              Text(
                'Add more purchases to compare suppliers.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddPurchase,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Add purchase'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTable extends StatelessWidget {
  const _MetricTable({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: tt.labelLarge?.copyWith(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.end,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Oldest → newest daily avg landing (matches [HexaColors] chart line).
class _PriceHistoryLineChart extends StatelessWidget {
  const _PriceHistoryLineChart({
    required this.points,
    required this.inr,
  });

  final List<({DateTime? d, double p})> points;
  final String Function(num?) inr;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    var minY = points.first.p;
    var maxY = points.first.p;
    for (var i = 0; i < points.length; i++) {
      final y = points[i].p;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      spots.add(FlSpot(i.toDouble(), y));
    }
    final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
    final first = points.first.d;
    final last = points.last.d;
    final rangeLabel = first != null && last != null
        ? '${DateFormat.MMMd().format(first)} → ${DateFormat.MMMd().format(last)}'
        : 'Oldest → newest';

    return Card(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Price trend ($rangeLabel)',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Oldest → newest · ${inr(minY)} – ${inr(maxY)}',
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 132,
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth <= 0) return const SizedBox.shrink();
                    return LineChart(
                      LineChartData(
                        minY: minY - span * 0.08,
                        maxY: maxY + span * 0.08,
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: HexaColors.accentInfo,
                            barWidth: 2.5,
                            dotData: FlDotData(
                              show: points.length <= 18,
                              getDotPainter: (a, b, c, d) =>
                                  FlDotCirclePainter(
                                radius: 2.5,
                                color: HexaColors.primaryNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Donut: share of **deals** per supplier ([HexaColors.chartPalette]).
class _SupplierDealsDonut extends StatelessWidget {
  const _SupplierDealsDonut({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final withDeals = <Map<String, dynamic>>[];
    var total = 0;
    for (final r in rows) {
      final d = (r['deals'] as num?)?.toInt() ?? 0;
      if (d > 0) {
        withDeals.add(r);
        total += d;
      }
    }
    if (total <= 0) return const SizedBox.shrink();

    final palette = HexaColors.chartPalette;
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < withDeals.length; i++) {
      final r = withDeals[i];
      final deals = (r['deals'] as num?)?.toInt() ?? 0;
      final pct = (deals / total * 100).clamp(0, 100);
      sections.add(
        PieChartSectionData(
          color: palette[i % palette.length],
          value: deals.toDouble(),
          title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
          radius: 52,
          titleStyle: tt.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      );
    }
    if (sections.isEmpty) return const SizedBox.shrink();

    return Card(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Deals by supplier',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Share of purchase lines in this window',
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth <= 0) return const SizedBox.shrink();
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 1.2,
                            centerSpaceRadius: 44,
                            sections: sections,
                            pieTouchData: PieTouchData(enabled: false),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$total',
                              style: tt.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: HexaColors.primaryNavy,
                              ),
                            ),
                            Text(
                              'deals',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...withDeals.asMap().entries.map((e) {
              final i = e.key;
              final r = e.value;
              final deals = (r['deals'] as num?)?.toInt() ?? 0;
              final pct = deals / total * 100;
              final name = r['name']?.toString() ?? '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: palette[i % palette.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: tt.labelMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$deals · ${pct.toStringAsFixed(0)}%',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Full-width supplier row — no horizontal table scroll.
class _SupplierCompareTile extends StatelessWidget {
  const _SupplierCompareTile({
    required this.row,
    required this.inr,
    required this.isTopProfit,
    required this.onSurf,
    this.onTap,
  });

  final Map<String, dynamic> row;
  final String Function(num?) inr;
  final bool isTopProfit;
  final Color onSurf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = row['name']?.toString() ?? '—';
    final sh = (row['profit_share_pct'] as num?)?.toDouble();
    Color? bg;
    if (sh != null && sh >= 10) {
      bg = HexaColors.profit.withValues(alpha: 0.08);
    } else if (((row['total_profit'] as num?)?.toDouble() ?? 0) < 0) {
      bg = HexaColors.loss.withValues(alpha: 0.07);
    }

    return Material(
      color: bg ?? cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: onSurf,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isTopProfit)
                  Chip(
                    label: const Text('Top profit'),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                    backgroundColor: HexaColors.profit.withValues(alpha: 0.22),
                  ),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 2),
                    child: Icon(Icons.chevron_right_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Avg',
                    value: inr((row['avg_landing'] as num?)?.toDouble()),
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Deals',
                    value: '${row['deals'] ?? 0}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Profit',
                    value: inr((row['total_profit'] as num?)?.toDouble()),
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Share',
                    value: row['profit_share_pct'] != null
                        ? '${row['profit_share_pct']}%'
                        : '—',
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            fontSize: 10,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
