import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/router/navigation_ext.dart';
import '../../purchase/state/purchase_providers.dart';

class ItemHistoryPage extends ConsumerWidget {
  const ItemHistoryPage({super.key, required this.catalogItemId});

  final String catalogItemId;

  TextStyle _numStyle(BuildContext context) => Theme.of(context).textTheme.bodySmall!.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      );

  String _inr(num n) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: n % 1 == 0 ? 0 : 2,
      ).format(n);

  String _qty(num n) => n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);

  Future<void> _openRowActions(BuildContext context, WidgetRef ref, LedgerLineRow row) async {
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      context.push('/purchase/edit/${row.purchaseId}');
      return;
    }
    if (action != 'delete') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove bill ${row.humanId ?? row.purchaseId}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: row.purchaseId,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(itemHistoryLinesProvider(catalogItemId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is DioException ? friendlyApiError(e) : 'Could not delete')),
      );
    }
  }

  Widget _metrics(BuildContext context, LedgerLinesState s) {
    final rows = s.filtered();
    var q = 0.0;
    var kg = 0.0;
    var amt = 0.0;
    for (final r in rows) {
      q += r.qty;
      kg += r.kg;
      amt += r.amountInr;
    }
    final avg = q > 0.0001 ? amt / q : 0.0;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Qty Σ ${_qty(q)}',
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Kg Σ ${_qty(kg)}',
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Avg rate ${_inr(avg)}',
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(itemHistoryLinesProvider(catalogItemId));
    final itemAsync = ref.watch(catalogItemDetailProvider(catalogItemId));
    final fmt = DateFormat.yMMMd();
    final notifier = ref.read(itemHistoryLinesProvider(catalogItemId).notifier);

    final showLoadMore =
        !state.loadingInitial && (state.canRevealMoreLocally || !state.exhausted);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: const Text('Item history'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.loadingInitial ? null : () => notifier.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              itemAsync.maybeWhen(
                data: (m) {
                  final name = m['name']?.toString().trim() ?? 'Item';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Filter by supplier / text…',
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 22),
                  border: OutlineInputBorder(),
                ),
                onChanged: notifier.setSearchTyping,
              ),
              const SizedBox(height: 12),
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              _metrics(context, state),
              if (state.loadingInitial && state.rows.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else ...[
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, lc) {
                      final tableW = lc.maxWidth < 720 ? 720.0 : lc.maxWidth;
                      return Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableW,
                            height: lc.maxHeight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Divider(height: 1),
                                Table(
                                  columnWidths: const {
                                    0: FixedColumnWidth(100),
                                    1: FixedColumnWidth(160),
                                    2: FixedColumnWidth(72),
                                    3: FixedColumnWidth(76),
                                    4: FixedColumnWidth(88),
                                    5: FixedColumnWidth(88),
                                  },
                                  children: [
                                    TableRow(
                                      children: [
                                        _h(context, 'Date'),
                                        _h(context, 'Supplier'),
                                        _h(context, 'Qty'),
                                        _h(context, 'Kg'),
                                        _h(context, 'Rate'),
                                        _h(context, 'Amt'),
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: state.visibleRows().isEmpty
                                      ? const Center(child: Text('No matching lines'))
                                      : ListView.builder(
                                          itemExtent: 40,
                                          itemCount: state.visibleRows().length,
                                          itemBuilder: (ctx, i) {
                                            final row = state.visibleRows()[i];
                                            final num = _numStyle(context);
                                            return InkWell(
                                              onTap: () => context
                                                  .push('/purchase/detail/${row.purchaseId}'),
                                              onLongPress: () =>
                                                  _openRowActions(context, ref, row),
                                              child: Table(
                                                columnWidths: const {
                                                  0: FixedColumnWidth(100),
                                                  1: FixedColumnWidth(160),
                                                  2: FixedColumnWidth(72),
                                                  3: FixedColumnWidth(76),
                                                  4: FixedColumnWidth(88),
                                                  5: FixedColumnWidth(88),
                                                },
                                                children: [
                                                  TableRow(
                                                    children: [
                                                      _c(context,
                                                          Text(fmt.format(row.purchaseDate), style: num)),
                                                      _c(
                                                        context,
                                                        Text(
                                                          row.supplierName.isEmpty
                                                              ? '—'
                                                              : row.supplierName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      _c(context, Text(_qty(row.qty), style: num)),
                                                      _c(context, Text(_qty(row.kg), style: num)),
                                                      _c(
                                                          context,
                                                          Text(_inr(row.rateInr), style: num)),
                                                      _c(
                                                          context,
                                                          Text(_inr(row.amountInr), style: num)),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (showLoadMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: FilledButton.tonalIcon(
                        onPressed: (state.loadingInitial || state.loadingMore)
                            ? null
                            : () => notifier.loadMore(),
                        icon: state.loadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(state.loadingMore ? 'Loading…' : 'Load more'),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _h(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          t,
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _c(BuildContext context, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
}
