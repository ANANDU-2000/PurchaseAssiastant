import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../stock/presentation/widgets/stock_row_metrics.dart';

/// Compact SYS / PHYS / PEND / DELIV / DIFF chips for item surfaces.
class ItemStockMetricStrip extends StatelessWidget {
  const ItemStockMetricStrip({
    super.key,
    required this.stock,
  });

  final Map<String, dynamic> stock;

  @override
  Widget build(BuildContext context) {
    final unit = (stock['stock_unit'] ?? stock['unit'] ?? 'piece').toString();
    final pendingRaw =
        stock['total_pending_delivery_qty'] ?? stock['pending_delivery_qty'];
    final pending = coerceToDouble(pendingRaw);
    final diff = StockRowMetrics.diffQty(stock);

    String qtyOrDash(double v) =>
        v > 0.001 ? formatStockQtyForUnit(unit, v) : '—';

    final cells = <_MetricCell>[
      _MetricCell(
        'System',
        StockRowMetrics.systemCellLabel(stock),
        const Color(0xFF2563EB),
        tooltip: 'ERP digital on-hand',
      ),
      _MetricCell(
        'Physical',
        StockRowMetrics.physicalCellLabel(stock),
        const Color(0xFF0F766E),
        tooltip: 'Last warehouse count',
      ),
      _MetricCell(
        'Pending',
        qtyOrDash(pending),
        const Color(0xFFEA580C),
        tooltip: 'On order — not in system stock yet',
      ),
      _MetricCell(
        'Diff',
        StockRowMetrics.diffCellLabel(stock),
        StockRowMetrics.diffColor(diff),
        tooltip: 'Physical minus system',
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _MiniMetricCard(cell: cells[i])),
        ],
      ],
    );
  }
}

class _MetricCell {
  const _MetricCell(
    this.label,
    this.value,
    this.color, {
    this.tooltip,
  });
  final String label;
  final String value;
  final Color color;
  final String? tooltip;
}

class _MiniMetricCard extends StatelessWidget {
  const _MiniMetricCard({required this.cell});

  final _MetricCell cell;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: cell.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cell.color.withValues(alpha: 0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cell.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: cell.color.withValues(alpha: 0.85),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              cell.value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: cell.color,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
    final tip = cell.tooltip;
    if (tip == null || tip.isEmpty) return card;
    return Tooltip(message: tip, child: card);
  }
}
