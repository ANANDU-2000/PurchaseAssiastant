import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/design_system/widgets/app_button.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../catalog/presentation/widgets/item_stock_metric_strip.dart';
import 'low_stock_category_tree.dart';
import 'stock_row_metrics.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';
/// Full item context — opened from compact low-stock row (tap or overflow).
Future<void> showLowStockItemDetailSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
  required bool staffMode,
  bool ownerInformed = false,
  void Function(Map<String, dynamic> item)? onOrderNow,
  void Function(Map<String, dynamic> item)? onNotifyOwner,
  void Function(Map<String, dynamic> item)? onEditReorder,
  void Function(Map<String, dynamic> item)? onStockUpdate,
  void Function(Map<String, dynamic> item)? onSystemStockUpdate,
  void Function(Map<String, dynamic> item)? onReceive,
}) {
  return showHexaBottomSheet<void>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: _LowStockItemDetailSheet(
      item: item,
      staffMode: staffMode,
      ownerInformed: ownerInformed,
      onOrderNow: onOrderNow,
      onNotifyOwner: onNotifyOwner,
      onEditReorder: onEditReorder,
      onStockUpdate: onStockUpdate,
      onSystemStockUpdate: onSystemStockUpdate,
      onReceive: onReceive,
    ),
  );
}

class _LowStockItemDetailSheet extends StatelessWidget {
  const _LowStockItemDetailSheet({
    required this.item,
    required this.staffMode,
    required this.ownerInformed,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onSystemStockUpdate,
    this.onReceive,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final bool ownerInformed;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onSystemStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  static const _critical = HexaDsColors.error;
  static const _warn = HexaColors.accentAmber;
  static const _ok = HexaColors.profit;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? 'Item';
    final unit = StockRowMetrics.unit(item);
    final system = StockRowMetrics.systemQty(item);
    final reorder = coerceToDouble(item['reorder_level']);
    final supplier = item['supplier_name']?.toString().trim() ?? '';
    final pendingDelivery = lowStockItemPendingDelivery(item);
    final out = system <= 0;

    final statusLabel = out
        ? 'OUT OF STOCK'
        : (reorder > 0 && system <= reorder)
            ? 'LOW STOCK'
            : 'NEEDS ATTENTION';
    final statusColor = out ? _critical : (system <= reorder ? _warn : _ok);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          statusLabel,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: statusColor,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'System stock · ${formatStockQtyDisplay(unit, system)}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: HexaDsColors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ItemStockMetricStrip(stock: item),
        if (supplier.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Supplier: $supplier',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: HexaColors.neutral,
            ),
          ),
        ],
        const SizedBox(height: 10),
          if (onStockUpdate != null)
            AppPrimaryButton(
              label: 'Update physical stock',
              onPressed: () {
                Navigator.pop(context);
                onStockUpdate!(item);
              },
            ),
          if (onSystemStockUpdate != null) ...[
            const SizedBox(height: 8),
            AppSecondaryButton(
              label: 'Update system stock',
              onPressed: () {
                Navigator.pop(context);
                onSystemStockUpdate!(item);
              },
            ),
          ],
          if (!staffMode && onOrderNow != null) ...[
            const SizedBox(height: 8),
            AppSecondaryButton(
              label: 'Create purchase',
              onPressed: () {
                Navigator.pop(context);
                onOrderNow!(item);
              },
            ),
          ],
          if (staffMode && onNotifyOwner != null) ...[
            const SizedBox(height: 8),
            AppSecondaryButton(
              label: ownerInformed ? 'Owner informed' : 'Inform owner',
              enabled: !ownerInformed,
              onPressed: () {
                Navigator.pop(context);
                onNotifyOwner!(item);
              },
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (onEditReorder != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onEditReorder!(item);
                  },
                  child: const Text('Set reorder level'),
                ),
              if (pendingDelivery && onReceive != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onReceive!(item);
                  },
                  child: const Text('Receive delivery'),
                ),
              TextButton(
                onPressed: () {
                  final id = item['id']?.toString();
                  Navigator.pop(context);
                  if (id != null && id.isNotEmpty) {
                    context.push('/catalog/item/$id');
                  }
                },
                child: const Text('Item profile'),
              ),
            ],
          ),
        ],
    );
  }
}
