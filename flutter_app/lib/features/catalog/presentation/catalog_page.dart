import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

/// Category list (layer 1). Subcategories and items live on deeper routes.
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
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

  Widget _insightRetry(VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onRetry,
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

  Future<void> _editCategory(BuildContext context, String id, String current) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).updateItemCategory(
            businessId: session.primaryBusiness.id,
            categoryId: id,
            name: ctrl.text.trim(),
          );
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _deleteCategory(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Delete “$name”? It must have no items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteItemCategory(
            businessId: session.primaryBusiness.id,
            categoryId: id,
          );
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final range = catalogInsightsDefaultRange();

    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev == null || next <= prev) return;
      async.whenData((list) {
        for (final c in list) {
          final id = c['id']?.toString();
          if (id == null || id.isEmpty) continue;
          ref.invalidate(categoryInsightsProvider('$id|${range.from}|${range.to}'));
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Catalog'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/catalog/new-category').then((_) {
          ref.invalidate(itemCategoriesListProvider);
          ref.invalidate(catalogItemsListProvider);
        }),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search categories (fuzzy)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (_) {},
            ),
          ),
          if (_searchQuery.trim().isNotEmpty)
            async.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                final q = _searchQuery.trim();
                final sug = catalogFuzzyRank(
                  q,
                  list,
                  (c) => c['name']?.toString() ?? '',
                  minScore: q.length <= 1 ? 10.0 : 38,
                  limit: 6,
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final c in sug)
                          ActionChip(
                            label: Text(c['name']?.toString() ?? ''),
                            onPressed: () {
                              final id = c['id']?.toString();
                              if (id != null) context.push('/catalog/category/$id');
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => FriendlyLoadError(
                onRetry: () {
                  ref.invalidate(itemCategoriesListProvider);
                  ref.invalidate(catalogItemsListProvider);
                },
              ),
              data: (list) {
                final items = itemsAsync.maybeWhen(data: (x) => x, orElse: () => <Map<String, dynamic>>[]);
                final q = _searchQuery.trim();
                final display = q.isEmpty
                    ? list
                    : catalogFuzzyRank(
                        q,
                        list,
                        (c) => c['name']?.toString() ?? '',
                        minScore: q.length <= 1 ? 10.0 : 38,
                        limit: 500,
                      );

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(itemCategoriesListProvider);
                    ref.invalidate(catalogItemsListProvider);
                    await ref.read(itemCategoriesListProvider.future);
                    await ref.read(catalogItemsListProvider.future);
                    final r = catalogInsightsDefaultRange();
                    for (final c in list) {
                      final id = c['id']?.toString();
                      if (id == null || id.isEmpty) continue;
                      ref.invalidate(categoryInsightsProvider('$id|${r.from}|${r.to}'));
                    }
                  },
                  child: display.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 48, 24, 100),
                          children: [
                            Icon(Icons.folder_outlined,
                                size: 48, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 16),
                            Text(
                              list.isEmpty ? 'No categories yet' : 'No matches',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              list.isEmpty
                                  ? 'Add a category, then subcategories and items — all from this catalog.'
                                  : 'Try a different spelling or clear search.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: display.length,
                          itemBuilder: (context, i) {
                            final c = display[i];
                            final id = c['id']?.toString() ?? '';
                            final name = c['name']?.toString() ?? '';
                            final itemCount =
                                items.where((it) => it['category_id']?.toString() == id).length;
                            final typesAsync = ref.watch(categoryTypesListProvider(id));
                            final subCount = typesAsync.maybeWhen(
                              data: (t) => t.length,
                              orElse: () => 0,
                            );
                            final insKey = '$id|${range.from}|${range.to}';
                            final ins = ref.watch(categoryInsightsProvider(insKey));
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.85),
                                ),
                              ),
                              child: InkWell(
                                onTap: () => context.push('/catalog/category/$id'),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            HexaColors.primaryMid.withValues(alpha: 0.2),
                                        foregroundColor: HexaColors.primaryMid,
                                        child: Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '$subCount subcategories · $itemCount items',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                            ),
                                            ins.when(
                                              loading: () => const Padding(
                                                padding: EdgeInsets.only(top: 8),
                                                child: LinearProgressIndicator(),
                                              ),
                                              error: (_, __) => _insightRetry(
                                                () => ref.invalidate(categoryInsightsProvider(insKey)),
                                              ),
                                              data: (m) {
                                                final tp = m['total_profit'];
                                                final lines = m['linked_line_count'] ?? 0;
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 6),
                                                  child: Text(
                                                    'Last 90d: ${_inr(_num(tp))} profit · $lines lines',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                        ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'edit') _editCategory(context, id, name);
                                          if (v == 'del') _deleteCategory(context, id, name);
                                        },
                                        itemBuilder: (ctx) => const [
                                          PopupMenuItem(value: 'edit', child: Text('Rename')),
                                          PopupMenuItem(value: 'del', child: Text('Delete')),
                                        ],
                                      ),
                                      const Icon(Icons.chevron_right_rounded),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
