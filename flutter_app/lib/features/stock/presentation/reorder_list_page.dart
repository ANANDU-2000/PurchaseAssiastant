import 'package:flutter/material.dart';

import '../../../shared/widgets/desktop_page_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/reorder_list_provider.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

class ReorderListPage extends ConsumerStatefulWidget {
  const ReorderListPage({super.key});

  @override
  ConsumerState<ReorderListPage> createState() => _ReorderListPageState();
}

class _ReorderListPageState extends ConsumerState<ReorderListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _search = '';

  static const _statuses = ['pending', 'ordered', 'done'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (_search == q) return;
      setState(() => _search = q);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    await ref.read(hexaApiProvider).patchReorderEntry(
          businessId: session.primaryBusiness.id,
          entryId: id,
          status: status,
        );
    ref.invalidate(reorderListProvider);
    ref.invalidate(reorderPendingCountProvider);
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    await ref.read(hexaApiProvider).deleteReorderEntry(
          businessId: session.primaryBusiness.id,
          entryId: id,
        );
    ref.invalidate(reorderListProvider);
    ref.invalidate(reorderPendingCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final pendingN = ref.watch(reorderPendingCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reorder list'),
            Text(
              '$pendingN pending',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Ordered'),
            Tab(text: 'Done'),
          ],
        ),
      ),
      body: DesktopPageShell(
        padding: EdgeInsets.zero,
        child: TabBarView(
        controller: _tabs,
        children: [
          for (final st in _statuses)
            _ReorderTab(
              status: st,
              query: _search,
              onClearSearch: () => _searchCtrl.clear(),
              onSetStatus: _setStatus,
              onRemove: _remove,
            ),
        ],
      ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search reorder items...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _searchCtrl.clear(),
                    ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReorderTab extends ConsumerWidget {
  const _ReorderTab({
    required this.status,
    required this.query,
    required this.onClearSearch,
    required this.onSetStatus,
    required this.onRemove,
  });

  final String status;
  final String query;
  final VoidCallback onClearSearch;
  final Future<void> Function(Map<String, dynamic> row, String status) onSetStatus;
  final Future<void> Function(Map<String, dynamic> row) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reorderListProvider(status));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => ReorderListLoadError(
        onRetry: () => ref.invalidate(reorderListProvider(status)),
      ),
      data: (rows) {
        final normalizedQuery = query.toLowerCase();
        final visible = normalizedQuery.isEmpty
            ? rows
            : rows.where((r) {
                final name = (r['item_name']?.toString() ?? '').toLowerCase();
                final supplier =
                    (r['supplier_name']?.toString() ?? '').toLowerCase();
                final by = (r['added_by_name']?.toString() ?? '').toLowerCase();
                return name.contains(normalizedQuery) ||
                    supplier.contains(normalizedQuery) ||
                    by.contains(normalizedQuery);
              }).toList();

        if (visible.isEmpty) {
          final listEmpty = rows.isEmpty;
          return HexaEmptyState(
            icon: listEmpty
                ? (status == 'pending'
                    ? Icons.playlist_add_check_outlined
                    : Icons.inventory_2_outlined)
                : Icons.search_off_rounded,
            title: listEmpty
                ? (status == 'pending'
                    ? 'No pending reorders'
                    : 'No $status items')
                : 'No items match search',
            subtitle: listEmpty
                ? 'Add items from stock or item detail.'
                : 'Try a different search term, or clear search.',
            primaryActionLabel: listEmpty ? 'Open stock' : 'Clear search',
            onPrimaryAction: listEmpty
                ? () => context.push('/stock')
                : onClearSearch,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(reorderListProvider(status));
            await ref.read(reorderListProvider(status).future);
          },
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              0,
              8,
              0,
              96 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = visible[i];
              final itemId = r['item_id']?.toString() ?? '';
              final name = r['item_name']?.toString() ?? '—';
              final unit = r['unit']?.toString() ?? '';
              final curRaw = r['current_stock'];
              final roRaw = r['reorder_level'];
              final curNum = curRaw is num ? curRaw.toDouble() : double.tryParse('$curRaw');
              final roNum = roRaw is num ? roRaw.toDouble() : double.tryParse('$roRaw');
              final cur = curNum != null
                  ? formatStockQtyForUnit(unit, curNum)
                  : '—';
              final ro = roNum != null
                  ? formatStockQtyForUnit(unit, roNum)
                  : '—';
              final supplier = r['supplier_name']?.toString().trim() ?? '';
              final lastRate = r['last_purchase_rate'];
              final rateStr = lastRate is num && lastRate > 0
                  ? NumberFormat.currency(
                      locale: 'en_IN',
                      symbol: '₹',
                      decimalDigits: 0,
                    ).format(lastRate)
                  : '';
              final by = r['added_by_name']?.toString() ?? '—';
              final created = r['created_at']?.toString();
              DateTime? dt;
              if (created != null) dt = DateTime.tryParse(created);
              final ago = dt != null
                  ? DateFormat('d MMM').format(dt.toLocal())
                  : '';

              return Material(
                color: status == 'done'
                    ? Colors.grey.shade50
                    : Colors.white,
                child: InkWell(
                  onTap: itemId.isEmpty
                      ? null
                      : () => context.push('/catalog/item/$itemId'),
                  onLongPress: () async {
                    final action = await showHexaBottomSheet<String>(
                      context: context,
                      compact: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (status == 'pending')
                            ListTile(
                              leading: const Icon(Icons.local_shipping_outlined),
                              title: const Text('Mark ordered'),
                              onTap: () => Navigator.pop(context, 'ordered'),
                            ),
                          if (status == 'ordered')
                            ListTile(
                              leading: const Icon(Icons.check_rounded),
                              title: const Text('Mark done'),
                              onTap: () => Navigator.pop(context, 'done'),
                            ),
                          ListTile(
                            leading: const Icon(Icons.delete_outline),
                            title: const Text('Remove from list'),
                            onTap: () => Navigator.pop(context, 'remove'),
                          ),
                        ],
                      ),
                    );
                    if (action == 'ordered') await onSetStatus(r, 'ordered');
                    if (action == 'done') await onSetStatus(r, 'done');
                    if (action == 'remove') await onRemove(r);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (status) {
                              'pending' => HexaColors.accentOrange,
                              'ordered' => HexaColors.brandPrimary,
                              _ => Colors.grey,
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: status == 'done'
                                      ? Colors.grey.shade600
                                      : HexaColors.textOnLightSurface,
                                ),
                              ),
                              Text(
                                [
                                  'Stock $cur / reorder $ro${unit.isNotEmpty ? ' $unit' : ''}',
                                  if (supplier.isNotEmpty) supplier,
                                  if (rateStr.isNotEmpty) 'Last $rateStr',
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                'Added by $by · $ago',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (status == 'pending') ...[
                          TextButton(
                            onPressed: () {
                              final itemId = r['item_id']?.toString() ??
                                  r['catalog_item_id']?.toString() ??
                                  '';
                              if (itemId.isEmpty) return;
                              context.push(
                                '/purchase/new?catalogItemId=${Uri.encodeComponent(itemId)}',
                              );
                            },
                            child: const Text('Order'),
                          ),
                          TextButton(
                            onPressed: () => onSetStatus(r, 'ordered'),
                            child: const Text('Ordered'),
                          ),
                        ],
                        if (status == 'ordered')
                          TextButton(
                            onPressed: () => onSetStatus(r, 'done'),
                            child: const Text('Done'),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Reorder list tab load failure (UX-154).
@visibleForTesting
class ReorderListLoadError extends StatelessWidget {
  const ReorderListLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return HexaEmptyState(
      icon: Icons.playlist_add_check_outlined,
      title: 'Could not load reorder list',
      subtitle: 'Please check your connection and try again.',
      primaryActionLabel: 'Retry',
      onPrimaryAction: onRetry,
    );
  }
}
