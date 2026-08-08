import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/desktop_detail_chrome.dart';
import '../../../../core/design_system/hexa_desktop_layout.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/unit_utils.dart';
import '../quick_stock_action_sheet.dart';
import '../stock_quick_purchase_sheet.dart';
import 'staff_delivered_detail_sheet.dart';
import 'stock_row_metrics.dart';
import 'stock_update_mode_toggle.dart';

/// Desktop right pane: selected item metrics + recent activity.
class StockDesktopDetailPane extends ConsumerWidget {
  const StockDesktopDetailPane({super.key, required this.item});

  final Map<String, dynamic>? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: HexaColors.brandPrimary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select an item',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: HexaColors.slate700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose a row on the left to see stock metrics and recent activity.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HexaColors.neutral, fontSize: 13),
            ),
          ],
        ),
      );
    }
    final id = item!['id']?.toString() ?? '';
    final name = item!['name']?.toString() ?? 'Item';
    final unit = StockRowMetrics.unit(item!);
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final opening = StockRowMetrics.openingQty(item!);
    final purchased = StockRowMetrics.purchasedQty(item!);
    final pending = StockRowMetrics.pendingDeliveryQty(item!);
    final stock = StockRowMetrics.systemQty(item!);
    final physical = StockRowMetrics.physicalQty(item!);
    final diff = StockRowMetrics.diffQty(item!);
    final delivered = StockRowMetrics.deliveryIndicator(item!) ==
        StockDeliveryIndicator.delivered;
    final activityAsync = id.isEmpty
        ? const AsyncValue<Map<String, dynamic>>.data({})
        : ref.watch(stockItemActivityProvider(id));

    Future<void> updatePhysical() => showQuickStockActionSheet(
          context: context,
          ref: ref,
          item: item!,
          initialMode: StockUpdateMode.physical,
        );

    Future<void> updateSystem() => showQuickStockActionSheet(
          context: context,
          ref: ref,
          item: item!,
          initialMode: StockUpdateMode.system,
        );

    Future<void> addPurchase() => showStockQuickPurchaseSheet(
          context: context,
          ref: ref,
          item: item!,
        );

    void viewActivity() {
      if (id.isEmpty) return;
      context.push('/catalog/item/$id?tab=activity');
    }

    final more = <DesktopMoreAction>[
      if (!isStaff)
        DesktopMoreAction(
          icon: Icons.memory_outlined,
          label: 'Update system stock',
          onSelected: () => updateSystem(),
        ),
      if (isStaff && delivered)
        DesktopMoreAction(
          icon: Icons.local_shipping_rounded,
          label: 'Delivery details',
          onSelected: () {
            showStaffDeliveredDetailSheet(
              context: context,
              ref: ref,
              item: item!,
            );
          },
        ),
      DesktopMoreAction(
        icon: Icons.info_outline_rounded,
        label: 'View item activity',
        onSelected: viewActivity,
      ),
      if (!isStaff)
        DesktopMoreAction(
          icon: Icons.tune_outlined,
          label: 'Set reorder',
          onSelected: () {
            if (id.isEmpty) return;
            context.push('/catalog/item/$id/edit');
          },
        ),
      DesktopMoreAction(
        icon: Icons.open_in_new_rounded,
        label: 'Full detail',
        onSelected: () {
          if (id.isEmpty) return;
          context.push('/catalog/item/$id');
        },
      ),
    ];

    return DesktopDetailPaneScaffold(
      header: Text(
        name,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      stats: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _metricRow(
            'Opening',
            opening == null
                ? '—'
                : '${formatStockQtyForUnit(unit, opening)} $unit',
          ),
          if (!isStaff)
            _metricRow(
              'Purchased',
              purchased == null
                  ? '—'
                  : '${formatStockQtyForUnit(unit, purchased)} $unit',
            ),
          const SizedBox(height: 8),
          HexaDenseKpiGrid(
            phoneColumns: 2,
            desktopColumns: 2,
            mainAxisExtent: 72,
            spacing: 8,
            children: [
              _statTile(
                label: 'System',
                value: '${formatStockQtyForUnit(unit, stock)} $unit',
                accent: HexaDsColors.blue,
              ),
              _statTile(
                label: 'Physical',
                value: physical == null
                    ? '—'
                    : '${formatStockQtyForUnit(unit, physical)} $unit',
                accent: HexaColors.brandTealMid,
              ),
              _statTile(
                label: 'Pending',
                value: pending == null || pending < 0.001
                    ? '—'
                    : '${formatStockQtyForUnit(unit, pending)} $unit',
                accent: HexaColors.warning,
              ),
              _statTile(
                label: 'Diff',
                value: StockRowMetrics.signedDiffLine(diff, unit)
                    .replaceAll('\n', ' '),
                accent: StockRowMetrics.diffColor(diff),
              ),
            ],
          ),
        ],
      ),
      actions: DesktopActionBar(
        primaryActions: [
          FilledButton.tonalIcon(
            onPressed: () => updatePhysical(),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Verify physical'),
          ),
          if (!isStaff)
            FilledButton.tonalIcon(
              onPressed: () => addPurchase(),
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: const Text('New purchase'),
            ),
        ],
        moreActions: more,
      ),
      bodyTitle: 'Recent activity',
      body: activityAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: LinearProgressIndicator(minHeight: 2),
        ),
        error: (_, __) => const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Could not load activity',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        data: (data) {
          final events = (data['activity'] as List?) ?? [];
          if (events.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No recent activity',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: events.length.clamp(0, 8),
            itemBuilder: (context, i) {
              final e = events[i];
              if (e is! Map) return const SizedBox.shrink();
              return ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                title: Text(
                  e['title']?.toString() ?? e['kind']?.toString() ?? '—',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  e['actor_name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 11),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _metricRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: HexaDsType.label(12).copyWith(color: HexaColors.neutral),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: valueColor ?? HexaColors.textOnLightSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required String value,
    required Color accent,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: HexaDsType.label(11).copyWith(color: accent),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: HexaColors.textOnLightSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
