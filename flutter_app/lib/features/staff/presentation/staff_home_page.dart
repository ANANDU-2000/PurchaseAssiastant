import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/providers/notifications_provider.dart';
import '../../../core/providers/search_focus_provider.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../stock/presentation/update_stock_sheet.dart';
import 'widgets/staff_home_dashboard_widgets.dart';
import 'widgets/staff_warehouse_totals_card.dart';

String _staffInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final list = parts.take(2).toList();
  if (list.isEmpty) return 'S';
  return list.map((w) => w[0].toUpperCase()).join();
}

String _pendingDeliverySubtitle(List<TradePurchase> pending) {
  if (pending.isEmpty) return 'Trucks waiting — open receive checklist';
  final first = pending.first.supplierName?.trim();
  if (first != null && first.isNotEmpty) {
    if (pending.length == 1) return 'From $first — tap to receive';
    return 'From $first + ${pending.length - 1} more';
  }
  return '${pending.length} orders waiting at warehouse';
}

Future<void> _showStaffProfileSheet(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider);
  final nameAsync = ref.read(staffDisplayNameProvider);
  final name = nameAsync.valueOrNull ?? 'Staff';
  final biz = session?.primaryBusiness.effectiveDisplayTitle ?? 'Workspace';

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.15),
                  child: Text(
                    _staffInitials(name),
                    style: HexaDsType.heading(18, color: HexaColors.brandPrimary),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: HexaDsType.heading(18)),
                      const SizedBox(height: 4),
                      Text(
                        'Role: Staff · $biz',
                        style: HexaDsType.body(13, color: HexaDsColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
                side: BorderSide(color: Theme.of(ctx).colorScheme.error),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: Text('Log out of ${HexaColors.appName}?'),
                    content: const Text('You will need to sign in again to continue.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(sessionProvider.notifier).logout();
                }
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Staff shell home — scan-first dashboard (FEAT-5).
class StaffHomePage extends ConsumerWidget {
  const StaffHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(staffDisplayNameProvider);
    final name = nameAsync.valueOrNull ?? 'Staff';
    final initials = _staffInitials(name);
    final bellCount = ref.watch(notificationsUnreadCountProvider);
    final activityAsync = ref.watch(staffTodaySummaryProvider);
    final lowAsync = ref.watch(staffLowStockAlertsProvider);
    final recentAsync = ref.watch(staffRecentScansProvider);
    final missingCount = ref.watch(staffMissingCodeCountProvider);
    final pendingDeliveries = ref.watch(staffPendingDeliveryCountProvider);
    final pendingList =
        ref.watch(staffPendingDeliveriesProvider).valueOrNull ?? const [];
    final lowCount = lowAsync.valueOrNull?.length ?? 0;
    final todayPurchases =
        ref.watch(staffTodayPurchasesProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(staffTodayActivityProvider);
            ref.invalidate(staffTodayStockWorkProvider);
            ref.invalidate(staffLowStockAlertsProvider);
            ref.invalidate(staffRecentScansProvider);
            ref.invalidate(missingCodeItemsProvider);
            ref.invalidate(tradePurchasesListProvider);
            ref.invalidate(stockOnHandTotalsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              12,
              HexaOp.pageGutter,
              100,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $name',
                          style: HexaDsType.heading(20, color: HexaDsColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: HexaColors.brandPrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'STAFF',
                                style: HexaDsType.label(11, color: HexaColors.brandPrimary)
                                    .copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('EEE, d MMM').format(DateTime.now()),
                              style: HexaDsType.body(13, color: HexaDsColors.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => context.push('/notifications'),
                    icon: Badge(
                      isLabelVisible: bellCount > 0,
                      label: Text(
                        bellCount > 99 ? '99+' : '$bellCount',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Account',
                    onPressed: () => _showStaffProfileSheet(context, ref),
                    icon: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          HexaColors.brandPrimary.withValues(alpha: 0.12),
                      child: Text(
                        initials,
                        style: HexaDsType.label(12, color: HexaColors.brandPrimary)
                            .copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              activityAsync.when(
                loading: () => const SizedBox(
                  height: 88,
                  child: ListSkeleton(rowCount: 1, rowHeight: 80),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (s) => StaffHomeTodaySummaryCard(summary: s),
              ),
              if (pendingDeliveries > 0 ||
                  missingCount > 0 ||
                  lowCount > 0) ...[
                const SizedBox(height: HexaOp.sectionGap),
                const StaffHomeSectionHeader(
                  title: 'Needs attention',
                  subtitle: 'Tap to open and complete',
                ),
                if (pendingDeliveries > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.local_shipping_rounded,
                    title: 'Pending deliveries',
                    subtitle: _pendingDeliverySubtitle(pendingList),
                    count: pendingDeliveries,
                    accent: const Color(0xFFBA7517),
                    onTap: () => context.push('/staff/receive'),
                  ),
                if (missingCount > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.qr_code_2_outlined,
                    title: 'Missing barcodes',
                    subtitle: 'Items need labels before bulk print',
                    count: missingCount,
                    accent: HexaColors.loss,
                    onTap: () => context.push('/stock/missing-barcodes'),
                  ),
                if (lowCount > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.warning_amber_rounded,
                    title: 'Low stock',
                    subtitle: 'Update counts or reorder levels',
                    count: lowCount,
                    accent: const Color(0xFFDC2626),
                    onTap: () {
                      ref.read(stockListQueryProvider.notifier).state =
                          const StockListQuery(status: 'low', page: 1);
                      context.go('/staff/stock');
                    },
                  ),
              ],
              const SizedBox(height: HexaOp.sectionGap),
              const StaffHomeSectionHeader(
                title: 'Warehouse on hand',
                subtitle: 'Totals across bags, kg, boxes, tins',
              ),
              const StaffWarehouseTotalsCard(),
              const SizedBox(height: HexaOp.sectionGap),
              const StaffHomeSectionHeader(
                title: 'Start here',
                subtitle: 'Most used actions for floor staff',
              ),
              Material(
                elevation: 2,
                shadowColor: HexaColors.brandPrimary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/barcode/scan'),
                  child: Ink(
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          HexaColors.brandPrimary,
                          HexaColors.brandPrimary.withValues(alpha: 0.82),
                        ],
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 26),
                        SizedBox(width: 10),
                        Text(
                          'Scan barcode',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/operations/checklist'),
                      icon: const Icon(Icons.checklist_rounded),
                      label: const Text('Checklist'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push('/operations/usage'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3B6D11),
                      ),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('Log usage'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HexaOp.sectionGap),
              const StaffHomeSectionHeader(
                title: 'Tools',
                subtitle: 'Search, stock, labels, and history',
              ),
              StaffHomeActionGroup(
                children: [
                  StaffHomeActionRow(
                    isFirst: true,
                    icon: Icons.search_rounded,
                    title: 'Search items',
                    subtitle: 'Name, item code, barcode, category',
                    onTap: () {
                      ref.read(searchFocusRequestedProvider.notifier).state =
                          true;
                      context.go('/staff/search');
                    },
                  ),
                  StaffHomeActionRow(
                    icon: Icons.inventory_2_outlined,
                    title: 'Update stock',
                    subtitle: 'Counts, adjustments, and audit trail',
                    onTap: () => context.go('/staff/stock'),
                  ),
                  StaffHomeActionRow(
                    icon: Icons.add_box_outlined,
                    title: 'Add new item',
                    subtitle: 'Quick catalog entry from the floor',
                    onTap: () => context.push('/catalog/quick-add'),
                  ),
                  StaffHomeActionRow(
                    icon: Icons.print_outlined,
                    title: 'Bulk print labels',
                    subtitle: 'A4 sheets or thermal roll',
                    onTap: () => context.push('/barcode/bulk-print'),
                  ),
                  StaffHomeActionRow(
                    icon: Icons.receipt_long_outlined,
                    title: 'Purchase history',
                    subtitle: 'Today, week, and all orders',
                    onTap: () => context.go('/staff/purchase-history'),
                  ),
                  StaffHomeActionRow(
                    isLast: true,
                    icon: Icons.warning_amber_rounded,
                    title: 'Low stock list',
                    subtitle: 'Items below reorder — update or notify',
                    badge: lowCount,
                    onTap: () => context.push('/staff/low-stock'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/staff/activity'),
                  child: const Text('Full activity log'),
                ),
              ),
              if (todayPurchases.isNotEmpty) ...[
                const SizedBox(height: HexaOp.sectionGap),
                const StaffHomeSectionHeader(
                  title: 'Stock received today',
                  subtitle: 'Delivered purchases on the floor',
                ),
                ...todayPurchases.take(4).map((p) {
                  final sup = p.supplierName ?? 'Supplier';
                  final summary = p.lines
                      .take(2)
                      .map((l) => '${l.itemName} · ${formatLineQtyWeightFromTradeLine(l)}')
                      .join(' · ');
                  final status = p.isDelivered ? 'Delivered' : 'Pending';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        '${p.humanId} · $sup',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        summary.isEmpty ? status : '$summary · $status',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                      ),
                      onTap: () => context.push('/staff/purchase-history/${p.id}'),
                    ),
                  );
                }),
              ],
              const SizedBox(height: HexaOp.sectionGap),
              const StaffHomeSectionHeader(title: 'Recent scans'),
              recentAsync.when(
                loading: () => const SizedBox(
                  height: 44,
                  child: ListSkeleton(rowCount: 1, rowHeight: 40),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (scans) {
                  if (scans.isEmpty) {
                    return Text(
                      'No scans yet today — tap Scan above.',
                      style: HexaDsType.body(14, color: HexaDsColors.textMuted),
                    );
                  }
                  return SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: scans.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final s = scans[i];
                        final label = s.name.length > 12
                            ? '${s.name.substring(0, 12)}…'
                            : s.name;
                        return ActionChip(
                          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onPressed: s.id.isEmpty
                              ? null
                              : () => context.push(
                                    '/catalog/item/${s.id}?source=scan',
                                  ),
                        );
                      },
                    ),
                  );
                },
              ),
              lowAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rows) {
                  if (rows.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: HexaOp.sectionGap),
                      const StaffHomeSectionHeader(
                        title: 'Low stock alerts',
                        subtitle: 'Tap a row to update count',
                      ),
                      ...rows.take(6).map((r) {
                        final id = r['id']?.toString() ?? '';
                        final nm = r['name']?.toString() ?? '';
                        final curN = coerceToDouble(r['current_stock']);
                        final unit =
                            (r['default_unit'] ?? r['unit'])?.toString() ?? 'bag';
                        final kgBag = coerceToDoubleNullable(r['default_kg_per_bag']);
                        final kgTin = coerceToDoubleNullable(r['default_weight_per_tin']);
                        final primary = stockDisplayPrimary(curN, unit);
                        final secondary =
                            stockDisplaySecondary(curN, unit, kgBag, kgTin);
                        final ro = r['reorder_level'];
                        final sub = secondary == null
                            ? 'On hand: $primary · Reorder: $ro'
                            : 'On hand: $primary · $secondary';
                        return SizedBox(
                          height: HexaOp.listRowMin,
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            color: HexaColors.loss.withValues(alpha: 0.06),
                            child: InkWell(
                              onTap: id.isEmpty
                                  ? null
                                  : () async {
                                      await showUpdateStockSheet(
                                        context: context,
                                        ref: ref,
                                        itemId: id,
                                        itemName: nm,
                                        stockRow: r,
                                      );
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nm,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            sub,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: HexaDsType.body(
                                              12,
                                              color: HexaDsColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
