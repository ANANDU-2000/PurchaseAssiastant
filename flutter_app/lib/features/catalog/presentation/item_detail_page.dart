import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/item_detail_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/auth/session_notifier.dart' show sessionProvider;
import '../../stock/presentation/stock_quick_purchase_sheet.dart';
import '../../stock/presentation/update_stock_sheet.dart';
import 'widgets/item_detail_header.dart';
import 'widgets/item_quick_actions_bar.dart';
import 'widgets/item_analytics_section.dart';
import 'widgets/item_ledger_section.dart';
import 'widgets/item_physical_verification_card.dart';
import 'widgets/item_purchase_history_section.dart';
import 'widgets/item_supplier_intelligence_section.dart';
import 'widgets/item_stock_snapshot_card.dart';
import 'widgets/item_timeline_section.dart';

class ItemDetailPage extends ConsumerWidget {
  const ItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev != null && next > prev) {
        ref.invalidate(catalogItemDetailProvider(itemId));
        ref.invalidate(stockItemDetailProvider(itemId));
        ref.invalidate(stockItemIntelligenceProvider(itemId));
        ref.invalidate(stockItemActivityProvider(itemId));
      }
    });

    final bundleAsync = ref.watch(itemDetailBundleProvider(itemId));
    final gutter = HexaResponsive.pageGutter(context, operational: true);
    final desktop = HexaBreakpoints.isDesktop(context);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: SafeArea(
        child: bundleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => FriendlyLoadError(
            message: 'Could not load item detail',
            onRetry: () => ref.invalidate(itemDetailBundleProvider(itemId)),
          ),
          data: (bundle) {
            final item = bundle.catalogItem;
            final stock = bundle.stockDetail;
            final name = (item['name']?.toString() ?? '').trim();
            final code = (item['item_code']?.toString() ?? '').trim();
            final cat = (stock['category_name']?.toString() ??
                    item['category_name']?.toString() ??
                    '')
                .trim();
            final sub = (stock['subcategory_name']?.toString() ??
                    item['type_name']?.toString() ??
                    '')
                .trim();
            final categoryLabel = [cat, sub].where((s) => s.isNotEmpty).join(' · ');

            Future<void> doRefresh() async {
              ref.invalidate(itemDetailBundleProvider(itemId));
              ref.invalidate(catalogItemDetailProvider(itemId));
              ref.invalidate(stockItemDetailProvider(itemId));
              ref.invalidate(stockItemIntelligenceProvider(itemId));
              ref.invalidate(stockItemActivityProvider(itemId));
            }

            if (desktop) {
              return RefreshIndicator(
                onRefresh: doRefresh,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 16),
                  child: HexaResponsiveCenter(
                    maxWidth: HexaResponsive.maxContentWidth,
                    padding: EdgeInsets.zero,
                    child: _DesktopItemLayout(
                      itemId: itemId,
                      name: name.isNotEmpty ? name : (code.isNotEmpty ? code : 'Item'),
                      code: code.isNotEmpty ? code : null,
                      categoryLabel: categoryLabel,
                      onMore: () => _showMore(context, ref, item),
                    ),
                  ),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: doRefresh,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
                    sliver: SliverToBoxAdapter(
                      child: HexaResponsiveCenter(
                        maxWidth: HexaResponsive.maxContentWidth,
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ItemDetailHeader(
                              itemName: name.isNotEmpty ? name : (code.isNotEmpty ? code : 'Item'),
                              categoryLabel: categoryLabel,
                              snapshot: null,
                              onEdit: () => context.push('/catalog/item/$itemId/edit'),
                              onMore: () => _showMore(context, ref, item),
                            ),
                            const SizedBox(height: 8),
                            ItemStockSnapshotCard(itemId: itemId),
                            const SizedBox(height: 8),
                            ItemQuickActionsBar(
                              itemId: itemId,
                              itemName: name.isNotEmpty ? name : 'Item',
                              itemCode: code.isNotEmpty ? code : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 100),
                    sliver: SliverToBoxAdapter(
                      child: HexaResponsiveCenter(
                        maxWidth: HexaResponsive.maxContentWidth,
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ItemLedgerSection(itemId: itemId),
                            const SizedBox(height: 8),
                            ItemPurchaseHistorySection(
                              itemId: itemId,
                              itemName: name.isNotEmpty ? name : (code.isNotEmpty ? code : 'Item'),
                            ),
                            const SizedBox(height: 8),
                            ItemSupplierIntelligenceSection(
                              itemId: itemId,
                              itemName: name.isNotEmpty ? name : (code.isNotEmpty ? code : 'Item'),
                            ),
                            const SizedBox(height: 8),
                            ItemPhysicalVerificationCard(itemId: itemId),
                            const SizedBox(height: 8),
                            ItemTimelineSection(itemId: itemId),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: desktop
          ? null
          : _ItemStickyActions(
              itemId: itemId,
              itemName: (bundleAsync.valueOrNull?.catalogItem['name']?.toString() ?? '').trim(),
            ),
    );
  }

  Future<void> _showMore(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> item,
  ) async {
    final itemName = (item['name']?.toString() ?? 'Item').trim();
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Ledger & statement'),
              onTap: () => Navigator.pop(ctx, 'ledger'),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Purchase history'),
              onTap: () => Navigator.pop(ctx, 'history'),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Activity'),
              onTap: () => Navigator.pop(ctx, 'activity'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy item name'),
              subtitle: Text(itemName),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;
    switch (v) {
      case 'ledger':
        context.push('/catalog/item/$itemId/ledger');
      case 'history':
        context.push('/catalog/item/$itemId/purchase-history');
      case 'activity':
        context.push('/stock/intelligence/$itemId');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: itemName));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied')),
        );
    }
  }
}

class _ItemStickyActions extends ConsumerWidget {
  const _ItemStickyActions({required this.itemId, required this.itemName});

  final String itemId;
  final String itemName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final name = itemName.trim().isNotEmpty ? itemName.trim() : 'Item';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final row = await ref.read(stockItemDetailProvider(itemId).future);
                  if (!context.mounted) return;
                  await showUpdateStockSheet(
                    context: context,
                    ref: ref,
                    itemId: itemId,
                    itemName: name,
                    stockRow: row.isEmpty ? null : row,
                  );
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Update physical'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final item = await ref.read(stockItemDetailProvider(itemId).future);
                  if (!context.mounted) return;
                  if (item.isEmpty) return;
                  await showStockQuickPurchaseSheet(
                    context: context,
                    ref: ref,
                    item: item,
                  );
                },
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('Add qty'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopItemLayout extends StatelessWidget {
  const _DesktopItemLayout({
    required this.itemId,
    required this.name,
    required this.code,
    required this.categoryLabel,
    required this.onMore,
  });

  final String itemId;
  final String name;
  final String? code;
  final String categoryLabel;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 420,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ItemDetailHeader(
                    itemName: name,
                    categoryLabel: categoryLabel,
                    snapshot: null,
                    onEdit: () => context.push('/catalog/item/$itemId/edit'),
                    onMore: onMore,
                  ),
                  const SizedBox(height: 8),
                  ItemStockSnapshotCard(itemId: itemId),
                  const SizedBox(height: 8),
                  ItemQuickActionsBar(
                    itemId: itemId,
                    itemName: name,
                    itemCode: code,
                  ),
                  const SizedBox(height: 8),
                  ItemPhysicalVerificationCard(itemId: itemId),
                  const SizedBox(height: 8),
                  ItemSupplierIntelligenceSection(itemId: itemId, itemName: name),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Ledger'),
                    Tab(text: 'Purchases'),
                    Tab(text: 'Analytics'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: ItemLedgerSection(itemId: itemId),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: ItemPurchaseHistorySection(
                          itemId: itemId,
                          itemName: name,
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: ItemAnalyticsSection(itemId: itemId),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
