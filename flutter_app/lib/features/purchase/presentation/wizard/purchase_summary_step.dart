import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../state/purchase_draft_provider.dart';

/// Step 4 — read-only recap + totals.
class PurchaseSummaryStep extends ConsumerWidget {
  const PurchaseSummaryStep({super.key});

  static Widget _row(
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 15 : 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? HexaColors.brandPrimary : Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 16 : 13,
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
              color: emphasize ? HexaColors.brandPrimary : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);
    final bd = ref.watch(purchaseStrictBreakdownProvider);
    final qt = ref.watch(purchaseQuantityTotalsProvider);

    final chunks = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Review',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    ];
    for (final ln in draft.lines) {
      chunks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ln.itemName,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ln.qty} ${ln.unit} · landing ₹${ln.landingCost.toStringAsFixed(2)}'
                  '${ln.sellingPrice != null ? ' · sell ₹${ln.sellingPrice!.toStringAsFixed(2)}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    chunks.add(
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFEFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HexaColors.brandPrimary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('Goods (approx)', '₹${bd.subtotalGross.toStringAsFixed(2)}'),
            _row('Tax', '+ ₹${bd.taxTotal.toStringAsFixed(2)}'),
            _row('Discounts', '− ₹${bd.discountTotal.toStringAsFixed(2)}'),
            if (bd.freight > 1e-9)
              _row('Freight', '+ ₹${bd.freight.toStringAsFixed(2)}'),
            if (bd.commission > 1e-9)
              _row(
                'Broker commission',
                '− ₹${bd.commission.toStringAsFixed(2)}',
              ),
            const Divider(height: 20),
            _row(
              'Grand payable',
              '₹${bd.grand.toStringAsFixed(2)}',
              emphasize: true,
            ),
            if (qt.totalKg > 1e-6) ...[
              const SizedBox(height: 8),
              Text(
                'Total weight ≈ ${qt.totalKg.toStringAsFixed(2)} kg',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[800],
                ),
              ),
            ],
            if (qt.qtyByUnit.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final e in qt.qtyByUnit.entries)
                    Chip(
                      label: Text(
                        '${e.key}: ${e.value.toStringAsFixed(3)}'.trim(),
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: chunks,
    );
  }
}
