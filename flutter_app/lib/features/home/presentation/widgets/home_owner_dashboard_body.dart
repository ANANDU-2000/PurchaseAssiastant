import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/navigation_ext.dart';
import '../../../../core/router/shell_navigation.dart';
import '../../../../features/shell/shell_branch_provider.dart';

import '../../../../core/design_system/hexa_desktop_layout.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/delivery_pipeline_provider.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/stock_providers.dart'
    show openingStockMissingProvider, stockStatusCountsProvider;
import 'home_analytics_helpers.dart';
import 'home_delivery_pipeline_card.dart';
import 'home_owner_quick_actions.dart';
import 'home_purchase_control_center.dart';
import 'home_warehouse_activity_feed.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;
import '../../../../shared/widgets/warehouse_units_breakdown_line.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
/// Owner dashboard: alert strip → KPI grid → purchases → activity (compact).
class HomeOwnerDashboardBody extends ConsumerWidget {
  const HomeOwnerDashboardBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gap = HexaResponsive.sectionGap(context);
    final dashState = ref.watch(homeDashboardDataProvider);
    if (dashState.refreshing &&
        dashState.snapshot.data == HomeDashboardData.empty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(HexaOp.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const HomeSectionSkeleton(rows: 4),
                  const SizedBox(height: 8),
                  Text(
                    'Loading dashboard…',
                    style: HexaOp.caption(context),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final status = homeTabHasOperationalBundle(ref)
        ? ref
            .watch(homeDashboardDataProvider)
            .snapshot
            .data
            .operational!
            .stockStatusCounts
        : ref.watch(stockStatusCountsProvider).valueOrNull ?? const {};
    final low = coerceToInt(status['low']) + coerceToInt(status['critical']);
    final out = coerceToInt(status['out']);
    final openingN =
        coerceToInt(ref.watch(openingStockMissingProvider).valueOrNull?['missing_count']);
    final pipeline = ref.watch(deliveryPipelineProvider).valueOrNull;
    var pending = deliveryPipelinePendingCount(pipeline);
    if (pending == 0) {
      pending = dashState.snapshot.data.pendingDeliveryCount;
    }
    final dash = dashState.snapshot.data;
    final sh = dash.stockInHand;
    final HomeInventorySummary? invSummary = sh != null
        ? HomeInventorySummary(
            totalValueInr: sh.totalValueInr,
            bags: sh.bags,
            boxes: sh.boxes,
            tins: sh.tins,
            kg: sh.kg,
            itemCount: sh.itemCount,
          )
        : ref.watch(homeInventorySummaryProvider).valueOrNull;
    final lowCount = low + out;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              if (low > 0) ...[
                _AlertChip(
                  // Below reorder only (excludes out) — matches KPI "Low stock" base.
                  label: 'Below reorder · $low',
                  color: HexaColors.brandPrimary,
                  onTap: () => pushLowStockDashboard(context),
                  isSelected: low > 0,
                ),
                const SizedBox(width: 12),
              ],
              if (pending > 0) ...[
                _AlertChip(
                  label: 'Pending delivery · $pending',
                  color: HexaColors.brandPrimary,
                  onTap: () => context.go('/purchase?filter=pending_delivery'),
                  isSelected: low <= 0 && pending > 0,
                ),
                const SizedBox(width: 12),
              ],
              if (openingN > 0) ...[
                _AlertChip(
                  label: 'Opening stock · $openingN',
                  color: HexaColors.brandPrimary,
                  onTap: () => pushOpeningStockSetup(context),
                  isSelected: low <= 0 && pending <= 0 && openingN > 0,
                ),
                const SizedBox(width: 12),
              ],
              if (out > 0) ...[
                _AlertChip(
                  label: 'Out of stock · $out',
                  color: HexaColors.brandPrimary,
                  onTap: () => goShellTab(
                        context,
                        ref,
                        branch: ShellBranch.stock,
                        location: '/stock?status=out',
                      ),
                  isSelected: low <= 0 && pending <= 0 && openingN <= 0 && out > 0,
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: gap),
        HexaDenseKpiGrid(
          mainAxisExtent: context.isDesktopLayout ? 100 : 96,
          children: [
            _KpiTile(
              label: 'Purchases',
              value: '${dash.purchaseCount}',
              subtitle: dash.period.label,
              onTap: () => context.go('/purchase'),
            ),
            _KpiTile(
              label: 'Pending delivery',
              value: '$pending',
              subtitle: pending > 0 ? 'Needs action' : 'Clear',
              accent: pending > 0 ? HexaDsColors.error : null,
              onTap: () => context.go('/purchase?filter=pending_delivery'),
            ),
            _KpiTile(
              // Authoritative attention figure: low + critical + out (same as chips combined).
              label: 'Need attention',
              value: '$lowCount',
              subtitle: out > 0
                  ? 'Below reorder $low · Out $out'
                  : 'Below reorder + out of stock',
              onTap: () => pushLowStockDashboard(context),
            ),
            _KpiTile(
              label: 'Warehouse',
              value: invSummary != null &&
                      inventoryUnitsLine(invSummary).isNotEmpty
                  ? inventoryUnitsLine(invSummary)
                  : '${invSummary?.itemCount ?? dash.itemSlices.length}',
              subtitle: invSummary != null &&
                      inventoryUnitsLine(invSummary).isNotEmpty
                  ? '${invSummary.itemCount} items on hand'
                  : 'Active items',
              onTap: () => goShellTab(
                    context,
                    ref,
                    branch: ShellBranch.stock,
                    location: '/stock',
                  ),
            ),
          ],
        ),
        SizedBox(height: gap),
        const DesktopTwoColumnGrid(
          children: [
            HomeDeliveryPipelineCard(),
            HomePurchaseControlCenter(),
          ],
        ),
        SizedBox(height: gap),
        HomeOwnerQuickActions(
          lowStockCount: lowCount,
          onPurchase: () => pushPurchaseNew(context),
          onStock: () => goShellTab(
                context,
                ref,
                branch: ShellBranch.stock,
                location: '/stock',
              ),
          onLowStock: () => pushLowStockDashboard(context),
          onDelivered: () => context.go('/purchase?filter=delivery_commit'),
          onReports: () => goShellTab(
                context,
                ref,
                branch: ShellBranch.reports,
                location: '/reports',
              ),
          onUsers: () => context.push('/settings/users'),
          onBarcode: () => pushBarcodeScan(context),
          onReorder: () => pushStockReorder(context),
          onDailyLog: () => goShellTab(
                context,
                ref,
                branch: ShellBranch.home,
                location: '/home/activity',
              ),
        ),
        SizedBox(height: gap),
        const HomeWarehouseActivityFeed(maxRows: 3),
      ],
    );
  }
}

class _AlertChip extends StatelessWidget {
  const _AlertChip({
    required this.label,
    required this.color,
    required this.onTap,
    this.isSelected = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: isSelected ? 2 : 0,
      shadowColor: Colors.black12,
      color: isSelected ? color : Colors.white,
      borderRadius: BorderRadius.circular(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.transparent : HexaColors.slateBorder,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : HexaColors.slate700,
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.onTap,
    this.accent,
  });

  final String label;
  final String value;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: context.isDesktopLayout ? 20 : 22,
      fontWeight: FontWeight.bold,
      color: accent ?? HexaColors.textOnLightSurface,
      height: 1.15,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: HexaColors.slateBorder,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: HexaColors.neutral,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: value.contains(' · ')
                        ? WarehouseUnitsSubtitleText(
                            subtitle: value,
                            fontSize: 14,
                            fallbackStyle: valueStyle,
                          )
                        : Text(
                            value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: valueStyle,
                          ),
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: HexaColors.cost,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
