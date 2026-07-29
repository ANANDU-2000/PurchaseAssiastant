import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/router/post_auth_route.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../catalog/presentation/widgets/item_stock_metric_strip.dart';
import '../quick_stock_action_sheet.dart';
import '../stock_quick_purchase_sheet.dart';
import 'staff_delivered_detail_sheet.dart';
import 'stock_row_metrics.dart';
import 'stock_update_mode_toggle.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Follow-up after the actions dialog fully closes (avoids Flutter web
/// blank dialogs when chaining `showDialog` immediately after `pop`).
enum _StockRowNextAction {
  physical,
  system,
  deliveryDetails,
  purchase,
  activity,
}

Future<void> showStockRowActions({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
  bool isStaffMode = false,
  VoidCallback? onBeforeNavigate,
  VoidCallback? onAfterNavigateReturn,
}) async {
  final id = item['id']?.toString() ?? '';
  if (id.isEmpty) return;
  final name = item['name']?.toString() ?? 'Item';
  final system = StockRowMetrics.systemQty(item);
  final unit = StockRowMetrics.unit(item);
  final session = ref.read(sessionProvider);
  final staff = isStaffMode || (session != null && sessionIsStaff(session));
  final delivered =
      StockRowMetrics.deliveryIndicator(item) == StockDeliveryIndicator.delivered;

  final next = await showHexaBottomSheet<_StockRowNextAction>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    // UID-004: keep dialog over the list/master column, not the detail CTAs.
    desktopAlignment: Alignment.centerLeft,
    barrierColor: Colors.black54,
    child: Column(
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
        const SizedBox(height: 6),
        Text(
          'System stock · ${formatStockQtyForUnit(unit, system)}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: HexaDsColors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ItemStockMetricStrip(stock: item),
        const SizedBox(height: 6),
        _StockActionTile(
          icon: Icons.inventory_2_outlined,
          label: 'Update physical stock',
          onTap: () =>
              Navigator.pop(context, _StockRowNextAction.physical),
        ),
        if (!staff)
          _StockActionTile(
            icon: Icons.memory_outlined,
            label: 'Update system stock',
            onTap: () =>
                Navigator.pop(context, _StockRowNextAction.system),
          ),
        if (staff && delivered)
          _StockActionTile(
            icon: Icons.local_shipping_rounded,
            label: 'Delivery details',
            onTap: () =>
                Navigator.pop(context, _StockRowNextAction.deliveryDetails),
          ),
        _StockActionTile(
          icon: Icons.add_shopping_cart_outlined,
          label: 'Add purchase quantity',
          onTap: () =>
              Navigator.pop(context, _StockRowNextAction.purchase),
        ),
        _StockActionTile(
          icon: Icons.info_outline_rounded,
          label: 'View item activity',
          onTap: () =>
              Navigator.pop(context, _StockRowNextAction.activity),
        ),
      ],
    ),
  );

  if (!context.mounted || next == null) return;

  switch (next) {
    case _StockRowNextAction.physical:
      await showQuickStockActionSheet(
        context: context,
        ref: ref,
        item: item,
        initialMode: StockUpdateMode.physical,
        skipInitialRefresh: true,
      );
    case _StockRowNextAction.system:
      await showQuickStockActionSheet(
        context: context,
        ref: ref,
        item: item,
        initialMode: StockUpdateMode.system,
        skipInitialRefresh: true,
      );
    case _StockRowNextAction.deliveryDetails:
      await showStaffDeliveredDetailSheet(
        context: context,
        ref: ref,
        item: item,
      );
    case _StockRowNextAction.purchase:
      await showStockQuickPurchaseSheet(
        context: context,
        ref: ref,
        item: item,
      );
    case _StockRowNextAction.activity:
      onBeforeNavigate?.call();
      await context.push('/catalog/item/$id?tab=activity');
      onAfterNavigateReturn?.call();
  }
}

class _StockActionTile extends StatelessWidget {
  const _StockActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(icon, size: 20, color: HexaColors.brandTealMid),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: HexaColors.cost, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
