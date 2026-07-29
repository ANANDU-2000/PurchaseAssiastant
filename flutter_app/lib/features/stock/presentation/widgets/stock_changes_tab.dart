import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/stock_audit_rows.dart';
import '../../../../core/widgets/hexa_error_card.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../shared/widgets/hexa_empty_state.dart';
import '../quick_stock_action_sheet.dart';

import '../../../../core/theme/hexa_colors.dart';
/// **Activity** tab: merged stock changes + movement feed for selected period.
class StockChangesTab extends ConsumerWidget {
  const StockChangesTab({
    super.key,
    this.isStaffMode = false,
  });

  final bool isStaffMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPagePeriodProvider);
    final feed = ref.watch(stockChangesFeedProvider);
    final desktop = context.isDesktopLayout;

    return feed.when(
      loading: () => const ListSkeleton(rowCount: 8, rowHeight: 72),
      error: (e, _) => HexaErrorCard.fromError(
        error: e,
        title: 'Could not load stock activity',
        onRetry: () => ref.invalidate(stockChangesFeedProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return HexaEmptyState(
            icon: Icons.history_rounded,
            title: 'No stock activity',
            subtitle:
                'Nothing logged for ${period.label.toLowerCase()}. Try a wider period.',
            primaryActionLabel: 'Refresh',
            onPrimaryAction: () => ref.invalidate(stockChangesFeedProvider),
          );
        }
        final list = RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(stockChangesFeedProvider);
            await ref.read(stockChangesFeedProvider.future);
          },
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              8,
              HexaOp.pageGutter,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = rows[i];
              final name = r['item_name']?.toString() ??
                  r['catalog_item_name']?.toString() ??
                  'Item';
              final isBill = r['adjustment_type']?.toString() == 'purchase' &&
                  stockAuditQtyDelta(r).abs() < 0.001;
              final delta = stockAuditQtyDelta(r);
              final reason = isBill
                  ? (r['reason']?.toString() ?? 'Purchase bill')
                  : (r['reason']?.toString() ??
                      r['adjustment_type']?.toString() ??
                      'Update');
              final at = parseStockAuditTimestamp(r) ?? DateTime.now();
              final by = r['updated_by_name']?.toString() ??
                  r['user_name']?.toString() ??
                  '';
              final itemId = r['item_id']?.toString() ??
                  r['catalog_item_id']?.toString();
              final sign = isBill ? '' : (delta >= 0 ? '+' : '');
              final color = isBill
                  ? HexaColors.accentOrange
                  : delta >= 0
                      ? HexaColors.materialGreen
                      : HexaColors.materialRed;

              return Material(
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(
                      delta >= 0
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    '$reason · ${DateFormat.jm().format(at)}'
                    '${by.isNotEmpty ? ' · $by' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    isBill
                        ? 'Bill'
                        : '$sign${delta == delta.roundToDouble() ? delta.round() : delta.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  onTap: itemId == null || itemId.isEmpty
                      ? null
                      : () async {
                          if (isStaffMode) {
                            final stock = await ref.read(
                              stockItemDetailProvider(itemId).future,
                            );
                            if (!context.mounted) return;
                            if (stock.isEmpty) {
                              context.push('/catalog/item/$itemId?tab=activity');
                              return;
                            }
                            await showQuickStockActionSheet(
                              context: context,
                              ref: ref,
                              item: stock,
                              skipInitialRefresh: true,
                            );
                          } else {
                            context.push('/catalog/item/$itemId?tab=activity');
                          }
                        },
                ),
              );
            },
          ),
        );
        if (!desktop) return list;
        // Desktop: left-align with content max + height-bound (never blank).
        final windowW = MediaQuery.sizeOf(context).width;
        final maxW = HexaResponsive.desktopContentMax(windowW);
        return LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height * 0.7;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: h,
                width: maxW.clamp(0, constraints.maxWidth),
                child: list,
              ),
            );
          },
        );
      },
    );
  }
}
