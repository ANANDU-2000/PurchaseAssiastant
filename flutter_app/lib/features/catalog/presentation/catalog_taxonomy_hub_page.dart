import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import '../catalog_taxonomy_utils.dart';
import 'widgets/quick_catalog_taxonomy_sheet.dart';

/// Staff + owner hub: quick create and browse categories → subcategories.
class CatalogTaxonomyHubPage extends ConsumerStatefulWidget {
  const CatalogTaxonomyHubPage({super.key});

  @override
  ConsumerState<CatalogTaxonomyHubPage> createState() =>
      _CatalogTaxonomyHubPageState();
}

class _CatalogTaxonomyHubPageState extends ConsumerState<CatalogTaxonomyHubPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCategorySheet() async {
    final r = await showQuickCatalogTaxonomySheet(
      context,
      mode: QuickCatalogTaxonomyMode.categoryAndOptionalSub,
    );
    if (r != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.typeName != null
                ? 'Created ${r.categoryName} · ${r.typeName}'
                : 'Created ${r.categoryName}',
          ),
        ),
      );
    }
  }

  Future<void> _openSubcategorySheet({String? categoryId}) async {
    final r = await showQuickCatalogTaxonomySheet(
      context,
      mode: QuickCatalogTaxonomyMode.subcategoryOnly,
      preselectedCategoryId: categoryId,
    );
    if (r != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subcategory ${r.typeName ?? ''} added')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final indexAsync = ref.watch(categoryTypesIndexProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo(isStaff ? '/staff/home' : '/home'),
        ),
        title: const Text('Categories'),
        actions: [
          if (!isStaff)
            IconButton(
              tooltip: 'Full catalog',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => context.push('/catalog'),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              8,
              HexaOp.pageGutter,
              0,
            ),
            child: Text(
              'Categories group your items. Subcategories are the type under each category (e.g. Rice → Biriyani rice).',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              12,
              HexaOp.pageGutter,
              8,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Category'),
                  onPressed: _openCategorySheet,
                ),
                ActionChip(
                  avatar: const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                  label: const Text('Subcategory'),
                  onPressed: () => _openSubcategorySheet(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search categories',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: catsAsync.when(
              loading: () => const ListSkeleton(),
              error: (_, __) => FriendlyLoadError(
                onRetry: () {
                  invalidateCatalogTaxonomy(ref);
                },
              ),
              data: (cats) {
                final typeCountByCat = <String, int>{};
                final index = indexAsync.valueOrNull ?? [];
                for (final t in index) {
                  final cid = t['category_id']?.toString();
                  if (cid == null) continue;
                  typeCountByCat[cid] = (typeCountByCat[cid] ?? 0) + 1;
                }

                var list = cats;
                if (_query.isNotEmpty) {
                  list = cats
                      .where((c) =>
                          (c['name']?.toString().toLowerCase() ?? '')
                              .contains(_query))
                      .toList();
                }

                if (list.isEmpty) {
                  return HexaEmptyState(
                    icon: Icons.category_outlined,
                    title: _query.isEmpty
                        ? 'No categories yet'
                        : 'No matches',
                    subtitle: 'Tap Category to add your first one.',
                    primaryActionLabel: 'Add category',
                    onPrimaryAction: _openCategorySheet,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    invalidateCatalogTaxonomy(ref);
                    await ref.read(itemCategoriesListProvider.future);
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      HexaOp.pageGutter,
                      4,
                      HexaOp.pageGutter,
                      MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = list[i];
                      final id = c['id']?.toString() ?? '';
                      final name = c['name']?.toString() ?? '—';
                      final subN = typeCountByCat[id] ?? 0;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Icon(
                            Icons.folder_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          subN == 0
                              ? 'No subcategories · General created automatically'
                              : '$subN subcategories',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          tooltip: 'Add subcategory',
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          onPressed: id.isEmpty
                              ? null
                              : () => _openSubcategorySheet(categoryId: id),
                        ),
                        onTap: id.isEmpty
                            ? null
                            : () {
                                if (isStaff) {
                                  _openSubcategorySheet(categoryId: id);
                                } else {
                                  context.push('/catalog/category/$id');
                                }
                              },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Quick add category',
        onPressed: _openCategorySheet,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
