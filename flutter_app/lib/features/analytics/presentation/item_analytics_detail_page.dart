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
            if (_sortColumn == 0) {
              c = (a['name']?.toString() ?? '')
                  .compareTo(b['name']?.toString() ?? '');
            } else {
              final va = a['avg_landing'] as num? ?? 0;
              final vb = b['avg_landing'] as num? ?? 0;
              c = va.compareTo(vb);
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
                  inr: _inr,
                  onAddPurchase: () => showEntryCreateSheet(context),
                ),
                const SizedBox(height: 20),
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
                  'Snapshot',
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
                  children: [
                    Text(
                      'Suppliers',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: onSurf,
                      ),
                    ),
                    const Spacer(),
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
                    const SizedBox(width: 8),
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
                  ...rows.asMap().entries.map((e) {
                    final i = e.key;
                    final m = e.value;
                    final name = m['name']?.toString() ?? '—';
                    final v = (m['avg_landing'] as num?)?.toDouble();
                    final isBest =
                        best != null && name == best['name']?.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.adaptiveCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: isBest
                                  ? HexaColors.primaryMid
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                          boxShadow: HexaColors.cardShadow(context),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: HexaColors.chartPalette[
                                      i % HexaColors.chartPalette.length]
                                  .withValues(alpha: 0.25),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: onSurf),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(name,
                                            style: tt.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: onSurf)),
                                      ),
                                      if (isBest)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: HexaColors.profit
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Best',
                                            style: tt.labelSmall?.copyWith(
                                                color: HexaColors.profit,
                                                fontWeight: FontWeight.w900),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Avg landing ${_inr(v)}',
                                    style: tt.bodySmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
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
    required this.inr,
    required this.onAddPurchase,
  });

  final String itemName;
  final Map<String, dynamic>? best;
  final double? bestLanding;
  final double? savingsVsAvg;
  final String Function(num?) inr;
  final VoidCallback onAddPurchase;

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
                  'You save ${inr(savingsVsAvg)} vs average',
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
                  Text(
                    rows[i].$2,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
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
