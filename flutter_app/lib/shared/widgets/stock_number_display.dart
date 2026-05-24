import 'package:flutter/material.dart';

import '../../core/theme/hexa_colors.dart';
import '../../core/utils/unit_utils.dart';

/// Warehouse stock status for number coloring.
enum StockDisplayStatus { ok, low, out, normal }

StockDisplayStatus stockDisplayStatusFromApi(String? status) {
  switch (status?.toLowerCase()) {
    case 'out':
      return StockDisplayStatus.out;
    case 'low':
    case 'critical':
      return StockDisplayStatus.low;
    case 'healthy':
      return StockDisplayStatus.ok;
    default:
      return StockDisplayStatus.normal;
  }
}

Color stockNumberColor(StockDisplayStatus status) {
  return switch (status) {
    StockDisplayStatus.low => const Color(0xFFDC2626),
    StockDisplayStatus.out => const Color(0xFF6B7280),
    StockDisplayStatus.ok => const Color(0xFF16A34A),
    StockDisplayStatus.normal => HexaColors.brandPrimary,
  };
}

/// Bold qty + muted unit + optional pending-order truck icon.
class StockNumberDisplay extends StatelessWidget {
  const StockNumberDisplay({
    super.key,
    required this.qty,
    required this.unit,
    this.status = StockDisplayStatus.normal,
    this.hasPendingOrder = false,
    this.pendingDays,
    this.fontSize = 17,
    this.strikethroughOut = true,
  });

  final double qty;
  final String unit;
  final StockDisplayStatus status;
  final bool hasPendingOrder;
  final int? pendingDays;
  final double fontSize;
  final bool strikethroughOut;

  @override
  Widget build(BuildContext context) {
    if (!qty.isFinite) return const Text('—');
    final numColor = stockNumberColor(status);
    final rounded = qty.roundToDouble();
    final qtyStr = (qty - rounded).abs() < 0.001
        ? formatStockQtyNumber(rounded)
        : formatStockQtyNumber(qty);
    final unitLabel = unit.trim().isEmpty ? '' : unit.toUpperCase();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (hasPendingOrder) ...[
          Icon(
            Icons.local_shipping_rounded,
            size: fontSize * 0.82,
            color: HexaColors.brandPrimary,
          ),
          const SizedBox(width: 3),
          if (pendingDays != null)
            Text(
              '${pendingDays}d',
              style: TextStyle(
                fontSize: fontSize * 0.55,
                fontWeight: FontWeight.w700,
                color: HexaColors.brandPrimary,
              ),
            ),
          if (pendingDays != null) const SizedBox(width: 4),
        ],
        Text(
          qtyStr,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: numColor,
            decoration: status == StockDisplayStatus.out && strikethroughOut
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        if (unitLabel.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(
            unitLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ],
    );
  }
}
