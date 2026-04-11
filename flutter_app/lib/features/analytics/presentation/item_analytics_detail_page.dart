import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';

final _pipProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, itemName) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).priceIntelligence(
        businessId: session.primaryBusiness.id,
        item: itemName,
      );
});

class ItemAnalyticsDetailPage extends ConsumerWidget {
  const ItemAnalyticsDetailPage({super.key, required this.itemName});

  final String itemName;

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_pipProvider(itemName));
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: Text(itemName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (p) {
          final hints = (p['decision_hints'] as List<dynamic>?) ?? [];
          final sup = (p['supplier_compare'] as List<dynamic>?) ?? [];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Price intelligence', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv('Avg landing', _inr((p['avg'] as num?)?.toDouble())),
                      _kv('High', _inr((p['high'] as num?)?.toDouble())),
                      _kv('Low', _inr((p['low'] as num?)?.toDouble())),
                      _kv('Last', _inr((p['last_price'] as num?)?.toDouble())),
                      _kv('Trend', p['trend']?.toString() ?? '—'),
                      _kv('Frequency', '${p['frequency'] ?? 0}'),
                      _kv('Confidence', '${((p['confidence'] as num?)?.toDouble() ?? 0) * 100}%'),
                    ],
                  ),
                ),
              ),
              if (hints.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Hints', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ...hints.map((h) => ListTile(leading: const Icon(Icons.lightbulb_outline), title: Text(h.toString()))),
              ],
              if (sup.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Suppliers (avg landing)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ...sup.map(
                  (s) {
                    final m = Map<String, dynamic>.from(s as Map);
                    return ListTile(
                      title: Text(m['name']?.toString() ?? ''),
                      trailing: Text(_inr((m['avg_landing'] as num?)?.toDouble())),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(k), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))],
      ),
    );
  }
}
