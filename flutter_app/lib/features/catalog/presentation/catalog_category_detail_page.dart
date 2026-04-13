import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/catalog_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

class CatalogCategoryDetailPage extends ConsumerStatefulWidget {
  const CatalogCategoryDetailPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<CatalogCategoryDetailPage> createState() =>
      _CatalogCategoryDetailPageState();
}

class _CatalogCategoryDetailPageState
    extends ConsumerState<CatalogCategoryDetailPage> {
  late ({String from, String to}) _range;

  @override
  void initState() {
    super.initState();
    _range = catalogInsightsDefaultRange();
  }

  String _insightKey() => '${widget.categoryId}|${_range.from}|${_range.to}';

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

  Future<void> _refresh() async {
    setState(() => _range = catalogInsightsDefaultRange());
    ref.invalidate(categoryInsightsProvider(_insightKey()));
    ref.invalidate(itemCategoriesListProvider);
    ref.invalidate(catalogItemsListProvider);
    await ref.read(itemCategoriesListProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final insAsync = ref.watch(categoryInsightsProvider(_insightKey()));

    final title = catsAsync.maybeWhen(
      data: (cats) {
        for (final c in cats) {
          if (c['id']?.toString() == widget.categoryId) {
            return c['name']?.toString() ?? 'Category';
          }
        }
        return 'Category';
      },
      orElse: () => 'Category',
    );

    final itemsInCat = itemsAsync.maybeWhen(
      data: (items) => items
          .where((it) => it['category_id']?.toString() == widget.categoryId)
          .toList(),
      orElse: () => <Map<String, dynamic>>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Last ${_range.from} → ${_range.to}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            insAsync.when(
              loading: () => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator())),
              error: (_, __) => FriendlyLoadError(
                onRetry: () =>
                    ref.invalidate(categoryInsightsProvider(_insightKey())),
              ),
              data: (ins) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Category performance',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        _row(context, 'Catalog items', '${ins['item_count']}'),
                        _row(context, 'Purchase lines',
                            '${ins['linked_line_count']}'),
                        _row(context, 'Total profit',
                            _inr(_num(ins['total_profit']))),
                        if (ins['top_item_name'] != null)
                          _row(context, 'Top item',
                              '${ins['top_item_name']} (${_inr(_num(ins['top_item_profit']))})'),
                        if (ins['worst_item_name'] != null)
                          _row(context, 'Weakest item',
                              '${ins['worst_item_name']} (${_inr(_num(ins['worst_item_profit']))})'),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text('Items in category',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (itemsInCat.isEmpty)
              Text(
                'No catalog items in this category yet.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: HexaColors.textSecondary),
              )
            else
              ...itemsInCat.map((it) {
                final id = it['id']?.toString() ?? '';
                final name = it['name']?.toString() ?? '';
                final ik = '$id|${_range.from}|${_range.to}';
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
                                Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                iAsync.when(
                                  loading: () => const Text('…',
                                      style: TextStyle(fontSize: 12)),
                                  error: (_, __) => _compactInsightRetry(() =>
                                      ref.invalidate(
                                          catalogItemInsightsProvider(ik))),
                                  data: (m) {
                                    final lines = m['line_count'] ?? 0;
                                    final profit = m['total_profit'];
                                    final al = m['avg_landing'];
                                    final ase = m['avg_selling'];
                                    return Text(
                                      'Used: $lines lines · Profit ${_inr(_num(profit))} · Avg ${_inr(_num(al))} → ${_inr(_num(ase))}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: HexaColors.textSecondary),
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

  num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  Widget _row(BuildContext context, String a, String b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text(a, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
              child: Text(b,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
