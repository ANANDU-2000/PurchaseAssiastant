import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../../core/utils/unit_utils.dart';

/// Pending vs delivered truck summary for item detail.
class ItemDeliveryStatusCard extends ConsumerWidget {
  const ItemDeliveryStatusCard({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockItemDetailProvider(itemId)).valueOrNull;
    if (stock == null || stock.isEmpty) return const SizedBox.shrink();

    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final unit =
        (stock['stock_unit'] ?? stock['unit'] ?? 'piece').toString().trim();
    final unitUp = unit.isEmpty ? '' : unit.toUpperCase();
    final pendingDel = coerceToDouble(stock['pending_delivery_qty']);
    final hasPending = stock['has_pending_order'] == true;
    final delivered = stock['last_purchase_delivered'] == true;
    final pendingDays = (stock['pending_order_days'] as num?)?.toInt();
    final po = stock['last_purchase_human_id']?.toString().trim() ?? '';
    final purchased = coerceToDouble(stock['period_purchased_qty']);

    if (!hasPending && !delivered && pendingDel <= 0.001 && purchased <= 0) {
      return const SizedBox.shrink();
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Delivery & trucks', style: HexaOp.cardTitle(context)),
            const SizedBox(height: 8),
            if (hasPending || pendingDel > 0.001) ...[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_shipping_rounded, color: Color(0xFFE65100)),
                title: const Text(
                  'Pending truck',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                subtitle: Text(
                  [
                    if (pendingDel > 0.001)
                      '${formatStockQtyNumber(pendingDel)}${unitUp.isNotEmpty ? ' $unitUp' : ''}',
                    if (pendingDays != null && pendingDays > 0) '$pendingDays days',
                    if (po.isNotEmpty) 'PO $po',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: () {
                    if (isStaff) {
                      if (po.isNotEmpty) {
                        context.push('/staff/receive/$po');
                      } else {
                        context.push('/staff/receive');
                      }
                    } else {
                      context.push('/purchase');
                    }
                  },
                  child: Text(isStaff ? 'Receive' : 'Purchases'),
                ),
              ),
            ],
            if (delivered && purchased > 0) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, color: Color(0xFF16A34A)),
                title: const Text(
                  'Delivered (in system stock)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                subtitle: Text(
                  '${formatStockQtyNumber(purchased)}${unitUp.isNotEmpty ? ' $unitUp' : ''} received this period'
                      '${po.isNotEmpty ? ' · PO $po' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
