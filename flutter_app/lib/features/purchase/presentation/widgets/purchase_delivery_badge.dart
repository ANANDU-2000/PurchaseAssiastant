import 'package:flutter/material.dart';

import '../../../../core/models/trade_purchase_models.dart';

/// Compact delivery-status chip for purchase list/detail rows.
class PurchaseDeliveryBadge extends StatelessWidget {
  const PurchaseDeliveryBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final DeliveryStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: compact ? 12 : 14, color: c),
          SizedBox(width: compact ? 4 : 5),
          Text(
            status.label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              color: c,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
