import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/models/trade_purchase_models.dart';
import '../../../stock/presentation/widgets/stock_table_layout.dart';

/// Operational purchase line row (replaces large cards).
class PurchaseDetailLineRow extends StatelessWidget {
  const PurchaseDetailLineRow({
    super.key,
    required this.index,
    required this.line,
    required this.qtyLabel,
    required this.purchaseRateLabel,
    required this.sellingRateLabel,
    required this.lineTotalLabel,
    this.profitLabel,
    this.profitColor,
    this.unitHint,
    this.hideFinancials = false,
  });

  final int index;
  final TradePurchaseLine line;
  final String qtyLabel;
  final String purchaseRateLabel;
  final String sellingRateLabel;
  final String lineTotalLabel;
  final String? profitLabel;
  final Color? profitColor;
  final String? unitHint;
  final bool hideFinancials;

  Widget _itemName(TradePurchaseLine line) {
    return Text(
      line.itemName,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 14,
        height: 1.2,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: StockTableLayout.rowDecoration(isFirst: false),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$index.',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: unitHint != null && unitHint!.trim().isNotEmpty
                    ? Tooltip(
                        message: unitHint!,
                        child: _itemName(line),
                      )
                    : _itemName(line),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            qtyLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (!hideFinancials) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'P: $purchaseRateLabel',
                    style: HexaDsType.label(11).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'S: $sellingRateLabel',
                    style: HexaDsType.label(11).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Line total',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    lineTotalLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            if (profitLabel != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Profit',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      profitLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: profitColor ?? const Color(0xFF0F766E),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
