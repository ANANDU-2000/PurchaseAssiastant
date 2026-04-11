import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';

final _pipProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, itemName) async {
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
  ConsumerState<ItemAnalyticsDetailPage> createState() => _ItemAnalyticsDetailPageState();
}

class _ItemAnalyticsDetailPageState extends ConsumerState<ItemAnalyticsDetailPage> {
  int _sortColumn = 1;
  bool _asc = true;

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: Text(widget.itemName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (p) {
          final hints = (p['decision_hints'] as List<dynamic>?) ?? [];
          final sup = (p['supplier_compare'] as List<dynamic>?) ?? [];
          final low = (p['low'] as num?)?.toDouble();
          final high = (p['high'] as num?)?.toDouble();
          final last = (p['last_price'] as num?)?.toDouble();
          final avg = (p['avg'] as num?)?.toDouble();
          final pos = _positionPct(p);

          final rows = sup.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          rows.sort((a, b) {
            int c;
            if (_sortColumn == 0) {
              c = (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
            } else {
              final va = a['avg_landing'] as num? ?? 0;
              final vb = b['avg_landing'] as num? ?? 0;
              c = va.compareTo(vb);
            }
            return _asc ? c : -c;
          });

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_pipProvider(widget.itemName)),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Price position (landing)', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (low != null && high != null && last != null)
                  Text(
                    '${_inr(low)} ────●──── ${_inr(high)}   Last: ${_inr(last)}',
                    style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary),
                  ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pos / 100,
                    minHeight: 12,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    color: pos > 66 ? HexaColors.warning : (pos < 33 ? HexaColors.profit : HexaColors.primaryMid),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${pos.toStringAsFixed(0)}th percentile vs your range · Avg ${_inr(avg)}',
                  style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary),
                ),
                const SizedBox(height: 20),
                Text('Stats', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _kv('Avg landing', _inr((p['avg'] as num?)?.toDouble())),
                        _kv('High', _inr((p['high'] as num?)?.toDouble())),
                        _kv('Low', _inr((p['low'] as num?)?.toDouble())),
                        _kv('Last', _inr((p['last_price'] as num?)?.toDouble())),
                        _kv('Trend', p['trend']?.toString() ?? '—'),
                        _kv('Frequency', '${p['frequency'] ?? 0}'),
                      ],
                    ),
                  ),
                ),
                if (hints.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Hints', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ...hints.map((h) => ListTile(leading: const Icon(Icons.lightbulb_outline), title: Text(h.toString()))),
                ],
                const SizedBox(height: 16),
                Text('Suppliers', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    sortColumnIndex: _sortColumn,
                    sortAscending: _asc,
                    columns: [
                      DataColumn(
                        label: const Text('Supplier'),
                        onSort: (i, asc) => setState(() {
                          _sortColumn = i;
                          _asc = asc;
                        }),
                      ),
                      DataColumn(
                        label: const Text('Avg ₹'),
                        numeric: true,
                        onSort: (i, asc) => setState(() {
                          _sortColumn = i;
                          _asc = asc;
                        }),
                      ),
                    ],
                    rows: [
                      for (final m in rows)
                        DataRow(
                          cells: [
                            DataCell(Text(m['name']?.toString() ?? '')),
                            DataCell(Text(_inr((m['avg_landing'] as num?)?.toDouble()))),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(k), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))],
      ),
    );
  }
}
