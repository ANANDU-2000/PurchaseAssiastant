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

/// Follow-up after the detail sheet fully closes (chained dialog safe on web).
enum _LowStockDetailAction {
  physical,
  system,
  orderNow,
  notifyOwner,
  editReorder,
  receive,
  itemProfile,
}

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
}) async {
  final action = await showHexaBottomSheet<_LowStockDetailAction>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: _LowStockItemDetailSheet(
      item: item,
      staffMode: staffMode,
      ownerInformed: ownerInformed,
      showOrderNow: !staffMode && onOrderNow != null,
      showNotifyOwner: staffMode && onNotifyOwner != null,
      showEditReorder: onEditReorder != null,
      showStockUpdate: onStockUpdate != null,
      showSystemStockUpdate: onSystemStockUpdate != null,
      showReceive: onReceive != null,
    ),
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case _LowStockDetailAction.physical:
      onStockUpdate?.call(item);
    case _LowStockDetailAction.system:
      onSystemStockUpdate?.call(item);
    case _LowStockDetailAction.orderNow:
      onOrderNow?.call(item);
    case _LowStockDetailAction.notifyOwner:
      onNotifyOwner?.call(item);
    case _LowStockDetailAction.editReorder:
      onEditReorder?.call(item);
    case _LowStockDetailAction.receive:
      onReceive?.call(item);
    case _LowStockDetailAction.itemProfile:
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) {
        await context.push('/catalog/item/$id');
      }
  }
}

class _LowStockItemDetailSheet extends StatelessWidget {
  const _LowStockItemDetailSheet({
    required this.item,
    required this.staffMode,
    required this.ownerInformed,
    required this.showOrderNow,
    required this.showNotifyOwner,
    required this.showEditReorder,
    required this.showStockUpdate,
    required this.showSystemStockUpdate,
    required this.showReceive,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final bool ownerInformed;
  final bool showOrderNow;
  final bool showNotifyOwner;
  final bool showEditReorder;
  final bool showStockUpdate;
  final bool showSystemStockUpdate;
  final bool showReceive;

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
        if (showStockUpdate)
          AppPrimaryButton(
            label: 'Update physical stock',
            onPressed: () =>
                Navigator.pop(context, _LowStockDetailAction.physical),
          ),
        if (showSystemStockUpdate) ...[
          const SizedBox(height: 8),
          AppSecondaryButton(
            label: 'Update system stock',
            onPressed: () =>
                Navigator.pop(context, _LowStockDetailAction.system),
          ),
        ],
        if (showOrderNow) ...[
          const SizedBox(height: 8),
          AppSecondaryButton(
            label: 'Create purchase',
            onPressed: () =>
                Navigator.pop(context, _LowStockDetailAction.orderNow),
          ),
        ],
        if (showNotifyOwner) ...[
          const SizedBox(height: 8),
          AppSecondaryButton(
            label: ownerInformed ? 'Owner informed' : 'Inform owner',
            enabled: !ownerInformed,
            onPressed: () =>
                Navigator.pop(context, _LowStockDetailAction.notifyOwner),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (showEditReorder)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _LowStockDetailAction.editReorder),
                child: const Text('Set reorder level'),
              ),
            if (pendingDelivery && showReceive)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _LowStockDetailAction.receive),
                child: const Text('Receive delivery'),
              ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _LowStockDetailAction.itemProfile),
              child: const Text('Item profile'),
            ),
          ],
        ),
      ],
    );
  }
}
