import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/catalog/item_trade_history.dart';
import '../../../../core/providers/trade_purchases_provider.dart';
import '../../../../core/router/post_auth_route.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/widgets/friendly_load_error.dart';

class ItemSupplierIntelligenceSection extends ConsumerWidget {
  const ItemSupplierIntelligenceSection({
    super.key,
    required this.itemId,
    required this.itemName,
  });

  final String itemId;
  final String itemName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final hideFinancials = session != null && !sessionCanSeeFinancials(session);
    final purchasesFetch = ref.watch(tradePurchasesForItemProvider(itemId));
    final purchases = ref.watch(tradePurchasesForItemParsedProvider(itemId));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Supplier intelligence', style: HexaOp.cardTitle(context)),
            const SizedBox(height: 8),
            purchasesFetch.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load supplier intelligence',
                onRetry: () => ref.invalidate(tradePurchasesForItemProvider(itemId)),
              ),
              data: (_) {
                final rows = itemTradeHistoryRows(
                  purchases ?? const [],
                  itemId,
                  catalogItemName: itemName,
                );
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(12, 14, 12, 14),
                    child: Text(
                      'No purchases recorded yet.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  );
                }
                final bySupplier = <String, _SupplierAgg>{};
                for (final r in rows) {
                  final key = r.supplierName.trim().isEmpty ? '—' : r.supplierName.trim();
                  bySupplier.putIfAbsent(key, () => _SupplierAgg(name: key)).add(r);
                }
                final list = bySupplier.values.toList()
                  ..sort((a, b) => b.totalQty.compareTo(a.totalQty));

                _SupplierAgg? cheapest;
                if (!hideFinancials) {
                  final withRates = list.where((e) => e.avgRate != null).toList()
                    ..sort((a, b) => (a.avgRate!).compareTo(b.avgRate!));
                  cheapest = withRates.isNotEmpty ? withRates.first : null;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cheapest != null) ...[
                      _highlight(
                        'Cheapest supplier (avg rate)',
                        '${cheapest.name} • ₹${cheapest.avgRate!.toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (final s in list.take(5)) ...[
                      _SupplierRow(s: s, hideFinancials: hideFinancials),
                      if (s != list.take(5).last)
                        const Divider(height: 16),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlight(String label, String value) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF0F766E))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SupplierAgg {
  _SupplierAgg({required this.name});

  final String name;
  DateTime? lastPurchaseAt;
  int purchaseCount = 0;
  double totalQty = 0;
  double totalAmount = 0;
  double? avgRate;
  double? latestRate;

  void add(ItemTradeHistoryRow r) {
    purchaseCount += 1;
    lastPurchaseAt =
        lastPurchaseAt == null || r.purchaseDate.isAfter(lastPurchaseAt!)
            ? r.purchaseDate
            : lastPurchaseAt;
    totalQty += r.line.qty;
    totalAmount += r.lineTotal;
    final q = r.line.qty;
    if (q > 0.0001) {
      latestRate = r.lineTotal / q;
    }
    if (totalQty > 0.0001 && totalAmount > 0.01) {
      avgRate = totalAmount / totalQty;
    }
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({required this.s, required this.hideFinancials});

  final _SupplierAgg s;
  final bool hideFinancials;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final last = s.lastPurchaseAt != null ? df.format(s.lastPurchaseAt!) : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
            Text(
              last,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            _pill('${s.purchaseCount} bills'),
            _pill('Qty ${formatStockQtyNumber(s.totalQty)}'),
            if (!hideFinancials && s.avgRate != null) _pill('Avg ₹${s.avgRate!.toStringAsFixed(0)}'),
            if (!hideFinancials && s.latestRate != null) _pill('Latest ₹${s.latestRate!.toStringAsFixed(0)}'),
          ],
        ),
      ],
    );
  }

  Widget _pill(String t) => Chip(
        label: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

