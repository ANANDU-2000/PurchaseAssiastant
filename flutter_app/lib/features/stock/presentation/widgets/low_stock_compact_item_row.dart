import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import 'low_stock_category_tree.dart';
import 'low_stock_item_detail_sheet.dart';
import 'stock_row_metrics.dart';

/// Mobile-first low-stock row: serial # · name · stock · actions in one line.
class LowStockCompactItemRow extends ConsumerWidget {
  const LowStockCompactItemRow({
    super.key,
    required this.item,
    required this.staffMode,
    this.serialNumber,
    this.hideSubcategory = false,
    this.ownerInformed = false,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onSystemStockUpdate,
    this.onReceive,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  /// 1-based index within the open category / sub-tab list.
  final int? serialNumber;
  final bool hideSubcategory;
  final bool ownerInformed;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onSystemStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  static const _critical = Color(0xFFDC2626);
  static const _warn = Color(0xFFF59E0B);
  static const _primaryBtn = Color(0xFF065F46);
  static const _border = Color(0xFFE2E8E6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = item['name']?.toString() ?? '—';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final unit = StockRowMetrics.unit(item);
    final system = StockRowMetrics.systemQty(item);
    final reorder = coerceToDouble(item['reorder_level']);
    final out = system <= 0;
    final low = !out && reorder > 0 && system <= reorder;
    final pendingDelivery = lowStockItemPendingDelivery(item);

    final statusLabel = out
        ? 'OUT'
        : pendingDelivery
            ? 'PENDING'
            : low
                ? 'LOW'
                : 'ATTN';
    final statusColor = out
        ? _critical
        : pendingDelivery
            ? _warn
            : low
                ? _warn
                : const Color(0xFF64748B);

    void openDetails() {
      showLowStockItemDetailSheet(
        context: context,
        ref: ref,
        item: item,
        staffMode: staffMode,
        ownerInformed: ownerInformed,
        onOrderNow: onOrderNow,
        onNotifyOwner: onNotifyOwner,
        onEditReorder: onEditReorder,
        onStockUpdate: onStockUpdate,
        onSystemStockUpdate: onSystemStockUpdate,
        onReceive: onReceive,
      );
    }

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: openDetails,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (serialNumber != null)
                SizedBox(
                  width: 32,
                  child: Text(
                    '$serialNumber',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              Container(
                width: 3,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          formatStockQtyDisplay(unit, system),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!hideSubcategory && sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
              ),
              if (onStockUpdate != null)
                _CompactAction(
                  label: '+ Stock',
                  filled: true,
                  onTap: () => onStockUpdate!(item),
                ),
              if (!staffMode && onOrderNow != null)
                _CompactAction(
                  label: 'Order',
                  filled: false,
                  onTap: () => onOrderNow!(item),
                )
              else if (staffMode && onNotifyOwner != null)
                _CompactAction(
                  label: ownerInformed ? 'Sent' : 'Inform',
                  filled: false,
                  enabled: !ownerInformed,
                  onTap: () => onNotifyOwner!(item),
                ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                color: const Color(0xFF64748B),
                onPressed: openDetails,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.label,
    required this.filled,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = enabled
        ? LowStockCompactItemRow._primaryBtn
        : const Color(0xFF94A3B8);
    final child = Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    );
    if (filled) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: SizedBox(
          height: 34,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: enabled ? fg : const Color(0xFFE2E8E6),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: enabled ? onTap : null,
            child: child,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: SizedBox(
        height: 34,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            side: BorderSide(color: fg.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: enabled ? onTap : null,
          child: child,
        ),
      ),
    );
  }
}
