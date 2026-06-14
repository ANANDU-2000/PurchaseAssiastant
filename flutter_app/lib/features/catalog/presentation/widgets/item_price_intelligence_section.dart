import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';

final itemPriceIntelligenceProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemName) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  final hq = homeDateRangeForRef(ref);
  final from = DateTime.parse(hq.from);
  final to = DateTime.parse(hq.to);
  final spanDays = to.difference(from).inDays.abs() + 1;
  final windowDays = spanDays.clamp(7, 365);
  try {
    return await ref.read(hexaApiProvider).priceIntelligence(
          businessId: session.primaryBusiness.id,
          item: itemName,
          priceField: 'landing',
          windowDays: windowDays,
        );
  } catch (_) {
    return const {};
  }
});

/// Landing price intelligence (API) for catalog item detail analytics tab.
class ItemPriceIntelligenceSection extends ConsumerWidget {
  const ItemPriceIntelligenceSection({
    super.key,
    required this.itemName,
  });

  final String itemName;

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemPriceIntelligenceProvider(itemName));
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => FriendlyLoadError(
            message: 'Could not load price intelligence',
            onRetry: () =>
                ref.invalidate(itemPriceIntelligenceProvider(itemName)),
          ),
          data: (p) {
            final hints = (p['decision_hints'] as List<dynamic>?) ?? [];
            final low = (p['low'] as num?)?.toDouble();
            final high = (p['high'] as num?)?.toDouble();
            final last = (p['last_price'] as num?)?.toDouble();
            final avg = (p['avg'] as num?)?.toDouble();
            final sup = (p['supplier_compare'] as List<dynamic>?) ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Price intelligence',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Low ${_inr(low)} · High ${_inr(high)} · Last ${_inr(last)} · Avg ${_inr(avg)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (hints.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: HexaColors.accentAmber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      hints.first.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (sup.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Suppliers (${sup.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...sup.take(5).map((e) {
                    final m = Map<String, dynamic>.from(e as Map);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              m['name']?.toString() ?? 'Supplier',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            _inr((m['avg_landing'] as num?)?.toDouble()),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
