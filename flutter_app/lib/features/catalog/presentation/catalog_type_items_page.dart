import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/theme/hexa_colors.dart';

/// Items (catalog SKUs) under a category **type** — variants live on each item detail.
class CatalogTypeItemsPage extends ConsumerStatefulWidget {
  const CatalogTypeItemsPage({
    super.key,
    required this.categoryId,
    required this.typeId,
  });

  final String categoryId;
  final String typeId;

  @override
  ConsumerState<CatalogTypeItemsPage> createState() =>
      _CatalogTypeItemsPageState();
}

class _CatalogTypeItemsPageState extends ConsumerState<CatalogTypeItemsPage> {
  late ({String from, String to}) _range;

  @override
  void initState() {
    super.initState();
    _range = catalogInsightsDefaultRange();
  }

  String _insightKey(String itemId) =>
      '$itemId|${_range.from}|${_range.to}';

  Widget _compactInsightRetry(VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Insights unavailable · Retry',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: HexaColors.primaryMid,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  Color? _profitColor(num? p) {
    if (p == null) return null;
    if (p > 0) return HexaColors.profit;
    if (p < 0) return HexaColors.loss;
    return null;
  }

  Future<void> _refresh() async {
    setState(() => _range = catalogInsightsDefaultRange());
    ref.invalidate(categoryTypesListProvider(widget.categoryId));
    ref.invalidate(catalogItemsListProvider);
    await ref.read(catalogItemsListProvider.future);
  }

  Future<void> _addItem(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New catalog item'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Basmati 5kg',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: widget.categoryId,
            typeId: widget.typeId,
            name: ctrl.text.trim(),
          );
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item created')),
        );
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(categoryTypesListProvider(widget.categoryId));
    final itemsAsync = ref.watch(catalogItemsListProvider);

    final typeName = typesAsync.maybeWhen(
      data: (types) {
        for (final t in types) {
          if (t['id']?.toString() == widget.typeId) {
            return t['name']?.toString() ?? 'Type';
          }
        }
        return 'Type';
      },
      orElse: () => 'Type',
    );

    final itemsInType = itemsAsync.maybeWhen(
      data: (items) => items
          .where((it) => it['type_id']?.toString() == widget.typeId)
          .toList(),
      orElse: () => <Map<String, dynamic>>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          typeName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItem(context),
        icon: const Icon(Icons.add),
        label: const Text('Item'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Category · items in “$typeName”',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last ${_range.from} → ${_range.to} (insights)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Catalog items',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (itemsInType.isEmpty)
              Text(
                'No items in this type yet.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: HexaColors.textSecondary),
              )
            else
              ...itemsInType.map((it) {
                final id = it['id']?.toString() ?? '';
                final name = it['name']?.toString() ?? '';
                final ik = _insightKey(id);
                final iAsync = ref.watch(catalogItemInsightsProvider(ik));
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => context.push('/catalog/item/$id'),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                iAsync.when(
                                  loading: () => const Text(
                                    '…',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  error: (_, __) => _compactInsightRetry(
                                    () => ref.invalidate(
                                      catalogItemInsightsProvider(ik),
                                    ),
                                  ),
                                  data: (m) {
                                    final lines = m['line_count'] ?? 0;
                                    final profit = m['total_profit'];
                                    final al = m['avg_landing'];
                                    final ase = m['avg_selling'];
                                    final pc = _profitColor(_num(profit));
                                    return Text(
                                      'Used: $lines lines · Profit ${_inr(_num(profit))} · Avg ${_inr(_num(al))} → ${_inr(_num(ase))}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: pc ??
                                                HexaColors.textSecondary,
                                          ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
