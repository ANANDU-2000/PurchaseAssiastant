import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/utils/unit_utils.dart';
import 'stock_row_metrics.dart';
import 'stock_table_layout.dart';

/// Color rules per stock engine constants:
/// Green  = Healthy
/// Orange = Low Stock
/// Red    = Out Of Stock / Critical
/// Blue   = Pending Verification
/// Purple = Pending Delivery
const _colorHealthy = Color(0xFF22C55E);
const _colorLow = Color(0xFFF97316);
const _colorCritical = Color(0xFFEF4444);
const _colorOut = Color(0xFFEF4444);
const _colorPendingVerification = Color(0xFF3B82F6);
const _colorPendingDelivery = Color(0xFF8B5CF6);

Color _statusColor(String status) {
  switch (status) {
    case 'healthy':
      return _colorHealthy;
    case 'low':
      return _colorLow;
    case 'critical':
      return _colorCritical;
    case 'out':
      return _colorOut;
    default:
      return _colorHealthy;
  }
}

Color _rowLeftBorderColor(Map<String, dynamic> item) {
  final status = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
  final hasPending = item['has_pending_order'] == true;
  final pendingQty = StockRowMetrics.pendingDeliveryQty(item) ?? 0;
  final needsVerification = item['needs_verification'] == true;

  if (status == 'out' || status == 'critical') return _colorOut;
  if (status == 'low') return _colorLow;
  if (needsVerification) return _colorPendingVerification;
  if (hasPending || pendingQty > 0.001) return _colorPendingDelivery;
  return Colors.transparent;
}

String _statusLabel(String status) {
  switch (status) {
    case 'healthy':
      return 'OK';
    case 'low':
      return 'LOW';
    case 'critical':
      return 'CRIT';
    case 'out':
      return 'OUT';
    default:
      return 'OK';
  }
}

/// Warehouse operational row — responsive:
/// Mobile:  ITEM (inline truck + meta) | SYS | PHYS | DIFF
/// Tablet+: ITEM (inline truck + meta) | SYS | PHYS | DIFF | PENDING | STATUS
///
/// Row meta line shows: Verified By + Last Updated (always visible).
/// Color-coded left border per stock engine rules.
class StockWarehouseRow extends StatelessWidget {
  const StockWarehouseRow({
    super.key,
    required this.item,
    required this.onTap,
    required this.ref,
    this.isStaffMode = true,
    this.isFirstRow = false,
    this.isSelected = false,
    this.onSelect,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final WidgetRef ref;
  final bool isStaffMode;
  final bool isFirstRow;
  final bool isSelected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '—';
    final status = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final deliveryCue = StockRowMetrics.inlineDeliveryCue(item);
    final diff = StockRowMetrics.diffQty(item);
    final pendingQty = StockRowMetrics.pendingDeliveryQty(item) ?? 0;
    final activityMeta = StockRowMetrics.lastActivityMetaLine(item);
    final unit = StockRowMetrics.unit(item);
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    // Build meta line: "Verified By • Last Updated" or category/subcategory
    final cat = item['category_name']?.toString().trim() ?? '';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final metaLine = activityMeta ??
        (sub.isNotEmpty
            ? sub
            : cat.isNotEmpty
                ? cat
                : '');

    final leftBorder = _rowLeftBorderColor(item);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: HexaResponsive.pageGutter(context, operational: true),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: StockTableLayout.rowMinHeight,
              maxHeight: StockTableLayout.rowMinHeight,
            ),
            decoration: StockTableLayout.rowDecoration(isFirst: isFirstRow)
                .copyWith(
              color: isSelected
                  ? const Color(0xFFEFF6FF)
                  : StockTableLayout.rowFill,
              border: leftBorder != Colors.transparent
                  ? Border(
                      left: BorderSide(color: leftBorder, width: 3),
                    )
                  : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ITEM column
                  Expanded(
                    child: Container(
                      decoration: StockTableLayout.itemCellDecoration(),
                      padding: const EdgeInsets.fromLTRB(
                        StockTableLayout.cellHPadding,
                        5,
                        4,
                        5,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                              height: 1.12,
                            ),
                          ),
                          if (deliveryCue != null || metaLine.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  if (deliveryCue != null) ...[
                                    deliveryCue,
                                    if (metaLine.isNotEmpty)
                                      const SizedBox(width: 6),
                                  ],
                                  if (metaLine.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        metaLine,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: HexaDsType.label(9).copyWith(
                                          color: const Color(0xFF64748B),
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          // On mobile, show pending delivery in item meta when > 0
                          if (!isWide && pendingQty > 0.001)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                'Pending ${formatStockQtyForUnit(unit, pendingQty)} $unit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HexaDsType.label(9).copyWith(
                                  color: _colorPendingDelivery,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // SYS column (System Stock)
                  _boxedMetric(
                    StockRowMetrics.systemCellLabel(item),
                    StockRowMetrics.systemCellColor(item),
                  ),
                  // PHYS column (Physical Stock)
                  _boxedMetric(
                    StockRowMetrics.physicalCellLabel(item),
                    const Color(0xFF0F766E),
                  ),
                  // DIFF column (Difference)
                  _boxedMetric(
                    StockRowMetrics.diffCellLabel(item),
                    StockRowMetrics.diffColor(diff),
                  ),
                  // PENDING column (Tablet+ only)
                  if (isWide)
                    _boxedMetric(
                      pendingQty > 0.001
                          ? formatStockQtyForUnit(unit, pendingQty)
                          : '—',
                      pendingQty > 0.001
                          ? _colorPendingDelivery
                          : const Color(0xFF94A3B8),
                    ),
                  // STATUS column (Tablet+ only)
                  if (isWide)
                    _statusCell(status),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _boxedMetric(String primary, Color color) {
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          primary,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _statusCell(String status) {
    final color = _statusColor(status);
    final label = _statusLabel(status);
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
