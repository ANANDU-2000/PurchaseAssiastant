import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/catalog_providers.dart';
import '../../../core/search/catalog_fuzzy.dart';
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
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _range = catalogInsightsDefaultRange();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _insightKey() => '${widget.categoryId}|${_range.from}|${_range.to}';

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  Future<void> _refresh() async {
    setState(() => _range = catalogInsightsDefaultRange());
    ref.invalidate(categoryInsightsProvider(_insightKey()));
    ref.invalidate(categoryTypesListProvider(widget.categoryId));
    ref.invalidate(itemCategoriesListProvider);
    ref.invalidate(catalogItemsListProvider);
    await ref.read(itemCategoriesListProvider.future);
  }

  Future<void> _addSubcategory(BuildContext context) async {
    final ok = await context.push<bool>(
      '/catalog/category/${widget.categoryId}/new-subcategory',
    );
    if (ok == true) {
      ref.invalidate(categoryTypesListProvider(widget.categoryId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final typesAsync = ref.watch(categoryTypesListProvider(widget.categoryId));
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSubcategory(context),
        icon: const Icon(Icons.add),
        label: const Text('Add subcategory'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search subcategories',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 12),
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
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.85),
                    ),
                  ),
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
            Text(
              'Types',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Open a type to manage catalog items and variants.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            typesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                onRetry: () => ref.invalidate(
                  categoryTypesListProvider(widget.categoryId),
                ),
              ),
              data: (types) {
                if (types.isEmpty) {
                  return Text(
                    'No subcategories yet — tap Add subcategory.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: HexaColors.textSecondary),
                  );
                }
                final filtered = _searchQuery.trim().isEmpty
                    ? types
                    : catalogFuzzyRank(
                        _searchQuery,
                        types,
                        (t) => t['name']?.toString() ?? '',
                        minScore: 38,
                        limit: 200,
                      );
                if (filtered.isEmpty) {
                  return Text(
                    'No matches — try another spelling.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: HexaColors.textSecondary,
                        ),
                  );
                }
                return Column(
                  children: [
                    for (final t in filtered)
                      _typeCard(
                        context,
                        typeId: t['id']?.toString() ?? '',
                        typeName: t['name']?.toString() ?? '',
                        itemCount: itemsInCat
                            .where(
                              (it) =>
                                  it['type_id']?.toString() == t['id']?.toString(),
                            )
                            .length,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeCard(
    BuildContext context, {
    required String typeId,
    required String typeName,
    required int itemCount,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.8),
        ),
      ),
      child: InkWell(
        onTap: () => context.push(
          '/catalog/category/${widget.categoryId}/type/$typeId',
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 44,
                decoration: BoxDecoration(
                  color: HexaColors.primaryMid.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$itemCount items',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: HexaColors.textSecondary,
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
