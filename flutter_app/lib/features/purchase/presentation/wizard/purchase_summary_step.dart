import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';

double _approxBuyLine(PurchaseLineDraft l) {
  final kpu = l.kgPerUnit;
  final pk = l.landingCostPerKg;
  if (kpu != null && pk != null && kpu > 0 && pk > 0) {
    return l.qty * kpu * pk;
  }
  return l.qty * l.landingCost;
}

/// Read-only recap + totals — use inside parent scroll views.
class PurchaseSummarySections extends ConsumerWidget {
  const PurchaseSummarySections({super.key});

  static Widget row(
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
                  () {
                    final buy = _approxBuyLine(ln);
                    final sp = ln.sellingPrice;
                    if (sp != null && sp > 0) {
                      return '${ln.qty} ${ln.unit} · buy ₹${buy.toStringAsFixed(2)} · sell ₹${(sp * ln.qty).toStringAsFixed(2)}';
                    }
                    return '${ln.qty} ${ln.unit} · buy ₹${buy.toStringAsFixed(2)}';
                  }(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    double estRetailMargin = 0;
    var hasRetailMargin = false;
    for (final l in draft.lines) {
      final sp = l.sellingPrice;
      if (sp == null || sp <= 0) continue;
      final buy = _approxBuyLine(l);
      estRetailMargin += sp * l.qty - buy;
      hasRetailMargin = true;
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
            row('Goods (approx)', '₹${bd.subtotalGross.toStringAsFixed(2)}'),
            row('Tax', '+ ₹${bd.taxTotal.toStringAsFixed(2)}'),
            row('Discounts', '− ₹${bd.discountTotal.toStringAsFixed(2)}'),
            if (bd.freight > 1e-9)
              row('Freight', '+ ₹${bd.freight.toStringAsFixed(2)}'),
            if (bd.commission > 1e-9)
              row(
                'Broker commission',
                '− ₹${bd.commission.toStringAsFixed(2)}',
              ),
            if (hasRetailMargin)
              row(
                'Est. retail margin (lines)',
                '₹${estRetailMargin.toStringAsFixed(2)}',
              ),
            const Divider(height: 20),
            row(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: chunks,
    );
  }
}

/// Stand-alone scrollable recap (full screen); prefer [PurchaseSummarySections] when nested.
class PurchaseSummaryStep extends StatelessWidget {
  const PurchaseSummaryStep({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 24),
      child: PurchaseSummarySections(),
    );
  }
}
