import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart'
    show staffTradePurchasesForAlertsProvider;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

class StaffPendingDeliveriesPage extends ConsumerWidget {
  const StaffPendingDeliveriesPage({super.key});

  static String _bagsQtySummary(TradePurchase p) {
    final byUnit = <String, double>{};
    for (final l in p.lines) {
      final u = l.unit.trim().toUpperCase();
      byUnit[u] = (byUnit[u] ?? 0) + l.qty;
    }
    if (byUnit.isEmpty) return '—';
    return byUnit.entries
        .map((e) => '${formatStockQtyNumber(e.value)} ${e.key}')
        .join(' · ');
  }

  static double _totalLineQty(TradePurchase p) {
    var sum = 0.0;
    for (final l in p.lines) {
      sum += l.qty;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(staffDeliverySectionsProvider);
    final fetch = ref.watch(staffTradePurchasesForAlertsProvider);
    final total = sections?.total ?? 0;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: Text(
          total > 0 ? 'Pending deliveries ($total)' : 'Pending deliveries',
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'Scan purchase',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push('/barcode/scan'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (sections == null && fetch.isLoading) {
            return const ListSkeleton(rowCount: 6);
          }
          if (fetch.hasError && sections == null) {
            return FriendlyLoadError(
              message: 'Could not load pending deliveries',
              onRetry: () => invalidateStaffDeliverySurfaces(ref),
            );
          }
          final data = sections ?? const StaffDeliverySections();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            children: [
              _DeliverySection(
                title: 'Dispatched',
                count: data.dispatched.length,
                emptyMessage: 'No dispatches in transit.',
                purchases: data.dispatched,
              ),
              const SizedBox(height: 16),
              _DeliverySection(
                title: 'Arrived',
                count: data.arrived.length,
                emptyMessage: 'Nothing waiting at the warehouse.',
                purchases: data.arrived,
                highlight: true,
              ),
              const SizedBox(height: 16),
              _DeliverySection(
                title: 'Pending verification',
                count: data.pendingVerification.length,
                emptyMessage: 'No purchases awaiting owner commit.',
                purchases: data.pendingVerification,
              ),
              if (data.total == 0) ...[
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'No pending deliveries right now.',
                    textAlign: TextAlign.center,
                    style: HexaDsType.body(15, color: HexaDsColors.textMuted),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DeliverySection extends StatelessWidget {
  const _DeliverySection({
    required this.title,
    required this.count,
    required this.emptyMessage,
    required this.purchases,
    this.highlight = false,
  });

  final String title;
  final int count;
  final String emptyMessage;
  final List<TradePurchase> purchases;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '$title ($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HexaDsType.heading(14).copyWith(
                  color: highlight && count > 0
                      ? const Color(0xFFE65100)
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (purchases.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                emptyMessage,
                style: HexaDsType.body(13, color: HexaDsColors.textMuted),
              ),
            ),
          )
        else
          for (var i = 0; i < purchases.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PendingDeliveryTile(
              index: i + 1,
              total: purchases.length,
              purchase: purchases[i],
            ),
          ],
      ],
    );
  }
}

class _PendingDeliveryTile extends StatelessWidget {
  const _PendingDeliveryTile({
    required this.index,
    required this.total,
    required this.purchase,
  });

  final int index;
  final int total;
  final TradePurchase purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final qty = StaffPendingDeliveriesPage._totalLineQty(p);
    final bagsLine = StaffPendingDeliveriesPage._bagsQtySummary(p);
    final days = DateTime.now().difference(p.purchaseDate).inDays;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.1),
          child: Text(
            '$index',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: HexaColors.brandPrimary,
            ),
          ),
        ),
        title: Text(
          p.supplierName?.trim().isNotEmpty == true
              ? p.supplierName!
              : 'Supplier',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.humanId} · ${DateFormat('d MMM').format(p.purchaseDate)}'
              '${days > 0 ? ' · $days d pending' : ''}',
            ),
            const SizedBox(height: 2),
            Text(
              bagsLine,
              style: HexaDsType.label(11, color: HexaDsColors.textMuted),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$index/$total',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
            Text(
              '${qty == qty.roundToDouble() ? qty.round() : qty.toStringAsFixed(1)} qty',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        onTap: () => context.push('/staff/receive/${p.id}'),
      ),
    );
  }
}
