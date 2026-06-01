import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../stock/reports_stock_models.dart';
import '../stock/reports_stock_status.dart';

/// Compact ERP business card for Reports → Stock intel list.
class ReportsStockIntelCard extends StatelessWidget {
  const ReportsStockIntelCard({super.key, required this.item});

  final ReportsStockIntelItem item;

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final unitUpper = item.unit.trim().isEmpty
        ? ''
        : item.unit.trim().toUpperCase();
    final stockLabel = unitUpper.isEmpty
        ? formatStockQtyNumber(item.currentStock)
        : '${formatStockQtyNumber(item.currentStock)} $unitUpper';

    return Material(
      color: HexaColors.brandCard,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.id.isEmpty
            ? null
            : () => context.push('/stock/intelligence/${item.id}'),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: status.borderAccent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: HexaDsType.h3(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.category.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Category: ${item.category}',
                          style: HexaDsType.bodySm(context),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        stockLabel,
                        style: HexaDsType.metricPrimary().copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Last movement:',
                        style: HexaDsType.labelCaps(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.movementLabel,
                        style: HexaDsType.bodyPrimary(context).copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Used:',
                        style: HexaDsType.labelCaps(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '7d → ${_usageLine(item.used7d, item.unit)}',
                        style: HexaDsType.bodyPrimary(context).copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '30d → ${_usageLine(item.used30d, item.unit)}',
                        style: HexaDsType.bodyPrimary(context).copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _StatusBadge(status: status),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _usageLine(double qty, String unit) {
    final u = unit.trim().toUpperCase();
    if (u.isEmpty) return formatStockQtyNumber(qty);
    return '${formatStockQtyNumber(qty)} $u';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ReportsStockMovementStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.badgeBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: HexaDsType.labelCaps(context).copyWith(
          color: status.badgeForeground,
          fontSize: 10,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
