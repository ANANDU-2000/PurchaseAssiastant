import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'purchase_delivery_badge.dart';

/// Delivery pipeline status + role-specific primary action.
class PurchaseDetailDeliveryBanner extends StatelessWidget {
  const PurchaseDetailDeliveryBanner({
    super.key,
    required this.purchase,
    this.onDispatch,
    this.onArrive,
    this.onVerify,
    this.onCommit,
    this.onRevert,
    this.isOwnerOrManager = false,
    this.isStaff = false,
    this.deliveryBusy = false,
  });

  final TradePurchase purchase;
  final VoidCallback? onDispatch;
  final VoidCallback? onArrive;
  final VoidCallback? onVerify;
  final VoidCallback? onCommit;
  final VoidCallback? onRevert;
  final bool isOwnerOrManager;
  final bool isStaff;
  final bool deliveryBusy;

  @override
  Widget build(BuildContext context) {
    final ds = purchase.deliveryStatusEnum;
    final borderColor = ds.color;
    final bg = borderColor.withValues(alpha: 0.08);

    String subtitle = switch (ds) {
      DeliveryStatus.stockCommitted =>
        purchase.stockCommittedAt != null
            ? 'Committed on ${DateFormat('d MMM yyyy').format(purchase.stockCommittedAt!)}'
            : purchase.deliveredAt != null
                ? 'Committed on ${DateFormat('d MMM yyyy').format(purchase.deliveredAt!)}'
                : 'Stock updated in warehouse',
      DeliveryStatus.staffVerified || DeliveryStatus.partial =>
        isStaff && onCommit != null
            ? 'Verified — tap Commit to add qty to system stock'
            : 'Staff verified — commit to system stock when ready',
      DeliveryStatus.arrived || DeliveryStatus.staffVerifying =>
        'Count items and submit verification',
      DeliveryStatus.dispatched || DeliveryStatus.inTransit =>
        'Shipment en route to warehouse',
      _ => 'Awaiting supplier dispatch or warehouse receipt',
    };

    final meta = <String>[];
    if ((purchase.truckNumber ?? '').trim().isNotEmpty) {
      meta.add('Truck ${purchase.truckNumber!.trim()}');
    }
    if ((purchase.driverContact ?? '').trim().isNotEmpty) {
      meta.add(purchase.driverContact!.trim());
    }
    if ((purchase.dispatchNote ?? '').trim().isNotEmpty) {
      meta.add(purchase.dispatchNote!.trim());
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(ds.icon, size: 20, color: borderColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Delivery',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        PurchaseDeliveryBadge(status: ds),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta.join(' · '),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (deliveryBusy) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
          ],
          ..._actions(ds),
        ],
      ),
    );
  }

  VoidCallback? _enabled(VoidCallback? handler) =>
      deliveryBusy ? null : handler;

  List<Widget> _actions(DeliveryStatus ds) {
    final out = <Widget>[];
    if (isOwnerOrManager &&
        ds == DeliveryStatus.pending &&
        onDispatch != null) {
      out.add(_btn('Mark dispatched', _enabled(onDispatch), outlined: false));
    }
    if (isStaff &&
        (ds == DeliveryStatus.pending ||
            ds == DeliveryStatus.dispatched ||
            ds == DeliveryStatus.inTransit) &&
        onArrive != null) {
      out.add(_btn('Mark arrived at warehouse', _enabled(onArrive), outlined: false));
    }
    if ((isStaff || isOwnerOrManager) && ds.needsStaffAction && onVerify != null) {
      out.add(_btn('Submit warehouse counts', _enabled(onVerify)));
    }
    if (isOwnerOrManager && ds.readyForOwnerCommit && onCommit != null) {
      out.add(_btn('Commit to stock', _enabled(onCommit), outlined: false));
    }
    if (isOwnerOrManager &&
        ds == DeliveryStatus.stockCommitted &&
        onRevert != null) {
      out.add(_btn('Revert delivery & stock', _enabled(onRevert), destructive: true));
    }
    if (out.isEmpty) return const [];
    return out
        .expand((w) => [w, const SizedBox(height: 8)])
        .toList()
      ..removeLast();
  }

  Widget _btn(
    String label,
    VoidCallback? onPressed, {
    bool outlined = true,
    bool destructive = false,
  }) {
    return SizedBox(
      height: 40,
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: destructive
                  ? OutlinedButton.styleFrom(foregroundColor: HexaColors.loss)
                  : null,
              child: Text(label),
            )
          : FilledButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
