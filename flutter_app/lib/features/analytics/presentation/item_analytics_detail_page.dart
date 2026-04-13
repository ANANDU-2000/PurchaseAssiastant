import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/friendly_load_error.dart';

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

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(_pipProvider(widget.itemName)),
            color: HexaColors.primaryMid,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        HexaColors.heroGradientEnd,
                        HexaColors.primaryDeep,
                        HexaColors.primaryMid
                      ],
                    ),
                    border: Border.all(
                        color: HexaColors.primaryMid.withValues(alpha: 0.35)),
                    boxShadow: HexaColors.cardShadow(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Price intelligence',
                        style: tt.labelSmall?.copyWith(
                          color: HexaColors.textPrimary.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.itemName,
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: HexaColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (best != null)
                        Text(
                          'Best landing: ${best['name']?.toString() ?? '—'} at ${_inr((best['avg_landing'] as num?)?.toDouble())}',
                          style: tt.bodySmall?.copyWith(
                              color: HexaColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              height: 1.35),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Price position (landing)',
                    style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: onSurf)),
                const SizedBox(height: 8),
                if (low != null && high != null && last != null)
                  Text(
                    '${_inr(low)} min · ${_inr(high)} max · last ${_inr(last)}',
                    style: tt.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: pos / 100,
                    minHeight: 14,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                Text('Snapshot',
                    style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: onSurf)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatTile(
                        label: 'Avg',
                        value: _inr(avg),
                        accent: HexaColors.primaryMid),
                    _StatTile(
                        label: 'Low',
                        value: _inr(low),
                        accent: HexaColors.profit),
                    _StatTile(
                        label: 'High',
                        value: _inr(high),
                        accent: HexaColors.warning),
                    _StatTile(
                        label: 'Last',
                        value: _inr(last),
                        accent: HexaColors.chartPurple),
                    _StatTile(
                        label: 'Trend',
                        value: p['trend']?.toString() ?? '—',
                        accent: HexaColors.chartOrange),
                    _StatTile(
                        label: 'Frequency',
                        value: '${p['frequency'] ?? 0}',
                        accent: HexaColors.chartSellingCost),
                  ],
                ),
                if (hints.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Verdicts',
                      style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: onSurf)),
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
                    Text('Suppliers',
                        style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: onSurf)),
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

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 148,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.adaptiveCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: HexaColors.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                      color: accent, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900, color: cs.onSurface)),
        ],
      ),
    );
  }
}
