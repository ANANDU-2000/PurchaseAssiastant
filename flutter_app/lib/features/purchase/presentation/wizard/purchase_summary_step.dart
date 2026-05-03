import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strict_decimal.dart';
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

String _pRateDisplay(PurchaseLineDraft l) {
  if (l.landingCostPerKg != null &&
      l.landingCostPerKg! > 0 &&
      l.kgPerUnit != null &&
      l.kgPerUnit! > 0) {
    return '₹${l.landingCostPerKg!.toStringAsFixed(2)}/kg';
  }
  return '₹${l.landingCost.toStringAsFixed(2)}';
}

String _sRateDisplay(PurchaseLineDraft l) {
  final sp = l.sellingPrice;
  if (sp == null || sp <= 0) return '—';
  return '₹${sp.toStringAsFixed(2)}';
}

/// Read-only recap + totals — use inside parent scroll views.
class PurchaseSummarySections extends ConsumerWidget {
  const PurchaseSummarySections({super.key});

  static Widget row(
    String label,
    String value, {
    bool emphasize = false,
    Color? valueColor,
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
              color: valueColor ??
                  (emphasize ? HexaColors.brandPrimary : Colors.black87),
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

    double estRetailMargin = 0;
    var hasRetailMargin = false;
    for (final l in draft.lines) {
      final sp = l.sellingPrice;
      if (sp == null || sp <= 0) continue;
      final buy = _approxBuyLine(l);
      estRetailMargin += sp * l.qty - buy;
      hasRetailMargin = true;
    }

    final billty = draft.billtyRate ?? 0;
    final delivered = draft.deliveredRate ?? 0;
    final showBillty = billty > 1e-9;
    final showDelivered = delivered > 1e-9;

    final tableChildren = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade200),
        children: const [
          _TblCell(' # ', bold: true),
          _TblCell('Item', bold: true),
          _TblCell('Qty', bold: true),
          _TblCell('Unit', bold: true),
          _TblCell('P-Rate', bold: true),
          _TblCell('S-Rate', bold: true),
          _TblCell('P-Total', bold: true),
        ],
      ),
    ];

    for (var i = 0; i < draft.lines.length; i++) {
      final ln = draft.lines[i];
      final buy = _approxBuyLine(ln);
      tableChildren.add(
        TableRow(
          children: [
            _TblCell('${i + 1}'),
            _TblCell(ln.itemName, maxLines: 2),
            _TblCell(StrictDecimal.fromObject(ln.qty).format(3, trim: true)),
            _TblCell(ln.unit),
            _TblCell(_pRateDisplay(ln)),
            _TblCell(_sRateDisplay(ln)),
            _TblCell('₹${buy.toStringAsFixed(2)}'),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Review',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (draft.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No line items.',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 40),
              child: Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                columnWidths: const {
                  0: FixedColumnWidth(28),
                  1: FlexColumnWidth(2.4),
                  2: FixedColumnWidth(52),
                  3: FixedColumnWidth(40),
                  4: FixedColumnWidth(58),
                  5: FixedColumnWidth(58),
                  6: FixedColumnWidth(68),
                },
                children: tableChildren,
              ),
            ),
          ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFEFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: HexaColors.brandPrimary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Cost breakdown',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 8),
              row('Lines (goods, approx)',
                  '₹${bd.subtotalGross.toStringAsFixed(2)}'),
              row('Freight',
                  '${bd.freight > 1e-9 ? '+' : ''} ₹${bd.freight.toStringAsFixed(2)}'),
              row(
                  'Commission',
                  bd.commission > 1e-9
                      ? '− ₹${bd.commission.toStringAsFixed(2)}'
                      : '₹0.00'),
              if (showBillty)
                row(
                  'Billty',
                  '+ ₹${billty.toStringAsFixed(2)}',
                ),
              if (showDelivered)
                row(
                  'Delivered',
                  '+ ₹${delivered.toStringAsFixed(2)}',
                ),
              row('Tax', '+ ₹${bd.taxTotal.toStringAsFixed(2)}'),
              row('Discounts', '− ₹${bd.discountTotal.toStringAsFixed(2)}'),
              if (hasRetailMargin)
                row(
                  'Est. profit (sell − buy)',
                  '₹${estRetailMargin.toStringAsFixed(2)}',
                  valueColor: const Color(0xFF059669),
                ),
              const Divider(height: 20),
              row(
                'FINAL TOTAL',
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
      ],
    );
  }
}

class _TblCell extends StatelessWidget {
  const _TblCell(this.text, {this.bold = false, this.maxLines = 1});

  final String text;
  final bool bold;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
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
