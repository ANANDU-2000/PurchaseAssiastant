import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../purchase/presentation/widgets/purchase_damage_report_sheet.dart';
import '../../../purchase/providers/trade_purchase_detail_provider.dart';
/// Live delivery receipt for a stock row — always refetches purchase detail.
Future<void> showStaffDeliveredDetailSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final purchaseId = item['last_trade_purchase_id']?.toString().trim() ?? '';
  if (purchaseId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No linked purchase for this delivery')),
    );
    return;
  }
  final catalogItemId = item['id']?.toString().trim() ?? '';
  final itemName = item['name']?.toString() ?? 'Item';

  ref.invalidate(tradePurchaseDetailProvider(purchaseId));

  await showHexaBottomSheet<void>(
    context: context,
    compact: false,
    child: _StaffDeliveredDetailBody(
      purchaseId: purchaseId,
      catalogItemId: catalogItemId,
      itemName: itemName,
      fallbackQty: coerceToDoubleNullable(item['last_line_qty']),
      fallbackUnit: item['stock_unit']?.toString() ??
          item['unit']?.toString() ??
          '',
      fallbackAt: item['last_purchase_at']?.toString(),
    ),
  );
}

class _StaffDeliveredDetailBody extends ConsumerWidget {
  const _StaffDeliveredDetailBody({
    required this.purchaseId,
    required this.catalogItemId,
    required this.itemName,
    this.fallbackQty,
    this.fallbackUnit = '',
    this.fallbackAt,
  });

  final String purchaseId;
  final String catalogItemId;
  final String itemName;
  final double? fallbackQty;
  final String fallbackUnit;
  final String? fallbackAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tradePurchaseDetailProvider(purchaseId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load delivery: $e', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  ref.invalidate(tradePurchaseDetailProvider(purchaseId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (purchase) {
        final line = _lineForItem(purchase, catalogItemId);
        final deliveredQty = _deliveredQty(line, fallbackQty);
        final unit = (line?.unit ?? fallbackUnit).trim();
        final deliveredAt = purchase.staffVerifiedAt ??
            purchase.arrivedAt ??
            _parseDt(fallbackAt);
        final by = (purchase.staffVerifiedByName ?? '').trim();
        final notes = (purchase.deliveryNotes ?? '').trim();
        final refLabel =
            purchase.humanId.isNotEmpty ? purchase.humanId : purchase.id;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                itemName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Purchase #$refLabel',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _row('Delivered qty', formatStockQtyForUnit(unit, deliveredQty)),
              if (unit.isNotEmpty) _row('Unit', unit),
              if (deliveredAt != null)
                _row('Delivered', DateFormat('d MMM y, h:mm a').format(deliveredAt.toLocal())),
              if (by.isNotEmpty) _row('Marked by', by),
              if (notes.isNotEmpty) _row('Notes', notes),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await showPurchaseDamageReportSheet(
                    context: context,
                    ref: ref,
                    purchaseId: purchaseId,
                    initialItemName: itemName,
                  );
                },
                icon: const Icon(Icons.report_gmailerrorred_outlined, size: 18),
                label: const Text('Report damage'),
              ),
              TextButton(
                onPressed: () => ref.invalidate(tradePurchaseDetailProvider(purchaseId)),
                child: const Text('Refresh'),
              ),
            ],
          ),
        );
      },
    );
  }

  TradePurchaseLine? _lineForItem(TradePurchase purchase, String catalogItemId) {
    if (catalogItemId.isEmpty) return purchase.lines.isNotEmpty ? purchase.lines.first : null;
    for (final line in purchase.lines) {
      if (line.catalogItemId == catalogItemId) return line;
    }
    return purchase.lines.isNotEmpty ? purchase.lines.first : null;
  }

  double _deliveredQty(TradePurchaseLine? line, double? fallback) {
    final recv = line?.receivedQty;
    if (recv != null && recv > 0) return recv;
    if (line != null && line.qty > 0) return line.qty;
    return fallback ?? 0;
  }

  DateTime? _parseDt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
