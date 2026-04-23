import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/search/search_highlight.dart';
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
  final _searchCtrl = TextEditingController();
  String _debouncedSearch = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchTick);
  }

  void _onSearchTick() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _debouncedSearch = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchTick);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
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
    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev != null && next > prev) {
        ref.invalidate(categoryTypesListProvider(widget.categoryId));
        ref.invalidate(catalogItemsListProvider);
      }
    });

    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final typesAsync = ref.watch(categoryTypesListProvider(widget.categoryId));

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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Category: $title',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Total items: ${itemsInCat.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Filter types',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchCtrl,
                  builder: (_, val, __) {
                    if (val.text.trim().isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchCtrl.clear();
                        setState(() => _debouncedSearch = '');
                      },
                    );
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Types',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
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
                final filtered = _debouncedSearch.trim().isEmpty
                    ? types
                    : catalogFuzzyRank(
                        _debouncedSearch,
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
                        highlightQuery: _debouncedSearch.trim(),
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
    required String highlightQuery,
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
                    Text.rich(
                      TextSpan(
                        children: highlightSearchQuery(
                          typeName,
                          highlightQuery,
                          baseStyle: const TextStyle(fontWeight: FontWeight.w700),
                          highlightStyle: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      itemCount == 1 ? '1 item' : '$itemCount items',
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
}
