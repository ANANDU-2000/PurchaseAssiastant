import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/trade_purchase_models.dart';

/// Compact supplier / broker / date / status header for purchase detail.
class PurchaseDetailHeader extends StatelessWidget {
  const PurchaseDetailHeader({
    super.key,
    required this.purchase,
    required this.status,
    required this.paidPending,
  });

  final TradePurchase purchase;
  final PurchaseStatus status;
  final bool paidPending;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sup = (purchase.supplierName ?? '—').trim();
    final bro = (purchase.brokerName ?? '—').trim();
    final broImg = (purchase.brokerImageUrl ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                sup.isEmpty ? '—' : sup,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                paidPending ? 'Paid' : status.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: status.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _BrokerAvatar(imageUrl: broImg, name: bro.isEmpty ? '—' : bro),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Broker: ${bro.isEmpty ? '—' : bro}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('d MMM yyyy').format(purchase.purchaseDate),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        if (purchase.paymentDays != null)
          Text(
            'Payment terms: ${purchase.paymentDays} days',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        if (purchase.invoiceNumber != null &&
            purchase.invoiceNumber!.trim().isNotEmpty)
          Text(
            'Ref: ${purchase.invoiceNumber!.trim()}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _BrokerAvatar extends StatelessWidget {
  const _BrokerAvatar({required this.imageUrl, required this.name});

  final String imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '—'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();
    if (imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: const Color(0xFFE5E7EB),
        backgroundImage: NetworkImage(imageUrl),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: const Color(0xFF1B6B5A),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
