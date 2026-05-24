import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/stock_number_display.dart';
import 'stock_status_badge.dart';
import 'stock_table_layout.dart';

/// Dense bordered warehouse stock row: ITEM | STOCK | STATUS.
class StockTableRow extends StatelessWidget {
  const StockTableRow({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.isStaffMode = true,
    this.isFirstRow = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isStaffMode;
  final bool isFirstRow;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '—';
    final codeRaw = item['item_code']?.toString().trim() ?? '';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final cur = coerceToDouble(item['current_stock']);
    final stockUnit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'piece';
    final status =
        (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final missingBarcode = item['missing_barcode'] == true;
    final updatedAt = item['last_stock_updated_at']?.toString();
    final updatedBy = item['last_stock_updated_by']?.toString();
    final relative = formatStockRelativeTime(updatedAt);
    final hasPendingOrder = item['has_pending_order'] == true;
    final pendingDays = (item['pending_order_days'] as num?)?.toInt();

    final statusKind = StockStatusBadge.resolve(
      stockStatus: status,
      missingBarcode: missingBarcode,
      updatedAtIso: updatedAt,
    );
    final displayStatus = stockDisplayStatusFromApi(status);
    final isLowOrOut = displayStatus == StockDisplayStatus.low ||
        displayStatus == StockDisplayStatus.out;

    final metaParts = <String>[
      if (codeRaw.isNotEmpty) '#$codeRaw',
      if (relative.isNotEmpty) relative,
      if (!isStaffMode && updatedBy != null && updatedBy.isNotEmpty) updatedBy,
    ];

    String? ownerFooter;
    if (!isStaffMode) {
      final purchased = coerceToDouble(item['period_purchased_qty']);
      if (purchased > 0) {
        final diff = cur - purchased;
        if (diff.abs() > 0.001) {
          final sign = diff >= 0 ? '+' : '';
          ownerFooter =
              'Diff: $sign${formatStockQtyNumber(diff)} ${stockUnit.toUpperCase()}';
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: StockTableLayout.rowMinHeight,
            ),
            decoration: StockTableLayout.rowDecoration(isFirst: isFirstRow).copyWith(
              border: isLowOrOut
                  ? const Border(
                      left: BorderSide(color: Color(0xFFDC2626), width: 3),
                    )
                  : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        StockTableLayout.cellHPadding,
                        6,
                        4,
                        6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          if (sub.isNotEmpty &&
                              sub.toLowerCase() != name.trim().toLowerCase())
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HexaDsType.label(10).copyWith(
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          if (metaParts.isNotEmpty)
                            Text(
                              metaParts.join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HexaDsType.label(9).copyWith(
                                color: statusKind == StockRowStatusKind.recent
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          if (ownerFooter != null)
                            Text(
                              ownerFooter,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HexaDsType.label(9).copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: StockTableLayout.stockColWidth,
                    decoration: StockTableLayout.cellDecoration(),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: StockNumberDisplay(
                      qty: cur,
                      unit: stockUnit,
                      status: displayStatus,
                      hasPendingOrder: hasPendingOrder,
                      pendingDays: pendingDays,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(
                    width: StockTableLayout.statusColWidth,
                    child: Center(
                      child: StockStatusBadge(kind: statusKind),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
