import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../stock/reports_stock_models.dart';
import '../stock/reports_stock_status.dart';

/// Dense row for Reports → Stock (~72dp) — name, qty, status, movement on 2–3 lines.
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

    final meta = <String>[
      'Last ${item.movementLabel}',
      '7d ${_usageLine(item.used7d, item.unit)}',
      '30d ${_usageLine(item.used30d, item.unit)}',
    ].join(' · ');

    return Material(
      color: HexaColors.brandCard,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.id.isEmpty
            ? null
            : () => context.push('/stock/intelligence/${item.id}'),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(width: 4, color: status.borderAccent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusBadge(status: status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            stockLabel,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              height: 1.1,
                            ),
                          ),
                          if (item.category.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HexaDsType.bodySm(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFF94A3B8),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: status.badgeBackground,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: status.badgeForeground,
        ),
      ),
    );
  }
}
