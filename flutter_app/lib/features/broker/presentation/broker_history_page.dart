import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/services/broker_statement_pdf.dart';
import '../../purchase/state/purchase_providers.dart';

final _brokerHistoryHeaderProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, brokerId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getBroker(
        businessId: session.primaryBusiness.id,
        brokerId: brokerId,
      );
});

class BrokerHistoryPage extends ConsumerWidget {
  const BrokerHistoryPage({super.key, required this.brokerId});

  final String brokerId;

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

  Future<void> _openRowActions(BuildContext context, WidgetRef ref, LedgerLineRow row) async {
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => ctx.pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () => ctx.pop('delete'),
              ),
            ],
          ),
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
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Delete')),
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
      ref.invalidate(brokerHistoryLinesProvider(brokerId));
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
    final deals = rows.map((e) => e.purchaseId).toSet().length;
    final comm = rows.fold<double>(0, (a, r) => a + r.commissionInr);
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Deals (filtered) $deals', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('Commission Σ ${_inr(comm)}', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(brokerHistoryLinesProvider(brokerId));
    final headerAsync = ref.watch(_brokerHistoryHeaderProvider(brokerId));
    final purchasesAsync = ref.watch(tradePurchasesParsedProvider);
    final fmt = DateFormat.yMMMd();
    final notifier = ref.read(brokerHistoryLinesProvider(brokerId).notifier);

    final showLoadMore =
        !state.loadingInitial && (state.canRevealMoreLocally || !state.exhausted);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: const Text('Broker history'),
        actions: [
          IconButton(
            tooltip: 'Commission statement (PDF)',
            onPressed: () async {
              final biz = ref.read(invoiceBusinessProfileProvider);
              final header = headerAsync.asData?.value;
              final brokerName =
                  (header?['name'] ?? header?['display_name'])?.toString().trim();
              final brokerPhone = header?['phone']?.toString().trim();

              final merged = purchasesAsync.asData?.value;
              if (merged == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loading purchases… try again in a moment')),
                );
                return;
              }

              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final seedFrom = today.subtract(const Duration(days: 29));
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDateRange: DateTimeRange(start: seedFrom, end: today),
              );
              if (picked == null) return;
              final from = DateTime(picked.start.year, picked.start.month, picked.start.day);
              final to = DateTime(picked.end.year, picked.end.month, picked.end.day);

              final filtered = merged.where((p) {
                if (p.brokerId == null || p.brokerId!.isEmpty) return false;
                if (p.brokerId != brokerId) return false;
                final d = DateTime(p.purchaseDate.year, p.purchaseDate.month, p.purchaseDate.day);
                return !d.isBefore(from) && !d.isAfter(to);
              }).toList();

              if (filtered.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No broker purchases in this period')),
                );
                return;
              }

              await shareBrokerStatementPdfForChat(
                business: biz,
                brokerName: (brokerName != null && brokerName.isNotEmpty)
                    ? brokerName
                    : 'Broker',
                brokerPhone: brokerPhone,
                purchases: filtered,
                fromDate: from,
                toDate: to,
              );
            },
            icon: const Icon(Icons.receipt_long_outlined),
          ),
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
              headerAsync.maybeWhen(
                data: (m) {
                  final name = (m['name'] ?? m['display_name'])?.toString().trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      (name != null && name.isNotEmpty) ? name : 'Broker',
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
                  hintText: 'Search item, supplier, invoice (PUR-…), id…',
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
                                    1: FixedColumnWidth(140),
                                    2: FixedColumnWidth(160),
                                    3: FixedColumnWidth(98),
                                    4: FixedColumnWidth(98),
                                  },
                                  children: [
                                    TableRow(
                                      children: [
                                        _h(context, 'Date'),
                                        _h(context, 'Supplier'),
                                        _h(context, 'Item'),
                                        _h(context, 'Amount'),
                                        _h(context, 'Comm'),
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
                                                  1: FixedColumnWidth(140),
                                                  2: FixedColumnWidth(160),
                                                  3: FixedColumnWidth(98),
                                                  4: FixedColumnWidth(98),
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
                                                      _c(
                                                        context,
                                                        Text(
                                                          row.itemName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      _c(
                                                          context,
                                                          Text(_inr(row.amountInr), style: num)),
                                                      _c(
                                                          context,
                                                          Text(_inr(row.commissionInr), style: num)),
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
