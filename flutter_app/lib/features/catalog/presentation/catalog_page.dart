import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

/// Master categories + catalog items (per business).
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool _matches(String? name) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (name ?? '').toLowerCase().contains(q);
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

  /// Per-row insights sit in a list — use a compact retry instead of hiding failures.
  Widget _insightLoadErrorButton(VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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

  String? _existingItemIdFrom409(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final d = e.response?.data;
    if (d is Map && d['detail'] is Map) {
      return (d['detail'] as Map)['existing_item_id']?.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Item catalog'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Items'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: const Icon(Icons.search_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _categoriesBody(context),
                _itemsBody(context),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _addCategory(context),
              icon: const Icon(Icons.add),
              label: const Text('Category'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _addItem(context),
              icon: const Icon(Icons.add),
              label: const Text('Item'),
            ),
    );
  }

  Widget _categoriesBody(BuildContext context) {
    final async = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final range = catalogInsightsDefaultRange();
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(itemCategoriesListProvider);
          ref.invalidate(catalogItemsListProvider);
        },
      ),
      data: (list) {
        final items = itemsAsync.maybeWhen(
            data: (x) => x, orElse: () => <Map<String, dynamic>>[]);
        final filtered =
            list.where((c) => _matches(c['name']?.toString())).toList();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(itemCategoriesListProvider);
            ref.invalidate(catalogItemsListProvider);
            await ref.read(itemCategoriesListProvider.future);
            await ref.read(catalogItemsListProvider.future);
          },
          child: filtered.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 88),
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 48, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      list.isEmpty ? 'No categories yet' : 'No matches',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      list.isEmpty
                          ? 'Add a category to organize items, or create categories while recording a purchase.'
                          : 'Try a different search.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: HexaColors.textSecondary),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    final id = c['id']?.toString() ?? '';
                    final name = c['name']?.toString() ?? '';
                    final itemCount = items
                        .where((it) => it['category_id']?.toString() == id)
                        .length;
                    final insKey = '$id|${range.from}|${range.to}';
                    final ins = ref.watch(categoryInsightsProvider(insKey));
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => context.push('/catalog/category/$id'),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16)),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Items in catalog: $itemCount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: HexaColors.textSecondary),
                                    ),
                                    ins.when(
                                      loading: () => const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: LinearProgressIndicator(),
                                      ),
                                      error: (_, __) => _insightLoadErrorButton(
                                          () => ref.invalidate(
                                              categoryInsightsProvider(
                                                  insKey))),
                                      data: (m) {
                                        final tp = m['total_profit'];
                                        final top =
                                            m['top_item_name']?.toString();
                                        final lines =
                                            m['linked_line_count'] ?? 0;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            'Last 90d: ${_inr(_num(tp))} profit · $lines lines${top != null ? ' · top: $top' : ''}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  height: 1.35,
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
                                  if (v == 'edit') {
                                    _editCategory(context, id, name);
                                  }
                                  if (v == 'del') {
                                    _deleteCategory(context, id, name);
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('Rename')),
                                  PopupMenuItem(
                                      value: 'del', child: Text('Delete')),
                                ],
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

  Widget _itemsBody(BuildContext context) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final range = catalogInsightsDefaultRange();
    return catsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(itemCategoriesListProvider);
          ref.invalidate(catalogItemsListProvider);
        },
      ),
      data: (cats) {
        return itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => FriendlyLoadError(
            onRetry: () {
              ref.invalidate(itemCategoriesListProvider);
              ref.invalidate(catalogItemsListProvider);
            },
          ),
          data: (items) {
            final catName = <String, String>{
              for (final c in cats) c['id'].toString(): c['name'].toString(),
            };
            final filtered =
                items.where((it) => _matches(it['name']?.toString())).toList();
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(itemCategoriesListProvider);
                ref.invalidate(catalogItemsListProvider);
                await ref.read(catalogItemsListProvider.future);
              },
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 48, 24, 88),
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          items.isEmpty ? 'No catalog items yet' : 'No matches',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          items.isEmpty
                              ? 'Add items here to get profit and usage on this screen — or create them from a purchase entry.'
                              : 'Try a different search.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: HexaColors.textSecondary),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final it = filtered[i];
                        final id = it['id']?.toString() ?? '';
                        final cid = it['category_id']?.toString() ?? '';
                        final name = it['name']?.toString() ?? '';
                        final du = it['default_unit']?.toString();
                        final catLine =
                            '${catName[cid] ?? cid}${du != null && du.isNotEmpty ? ' · default $du' : ''}';
                        final insKey = '$id|${range.from}|${range.to}';
                        final ins =
                            ref.watch(catalogItemInsightsProvider(insKey));
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            onTap: () => context.push('/catalog/item/$id'),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16)),
                                        const SizedBox(height: 4),
                                        Text(
                                          catLine,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color:
                                                      HexaColors.textSecondary),
                                        ),
                                        ins.when(
                                          loading: () => const Padding(
                                            padding: EdgeInsets.only(top: 8),
                                            child: LinearProgressIndicator(),
                                          ),
                                          error: (_, __) =>
                                              _insightLoadErrorButton(() =>
                                                  ref.invalidate(
                                                      catalogItemInsightsProvider(
                                                          insKey))),
                                          data: (m) {
                                            final lines = m['line_count'] ?? 0;
                                            final profit = m['total_profit'];
                                            final al = m['avg_landing'];
                                            final ase = m['avg_selling'];
                                            final last = m['last_entry_date']
                                                ?.toString();
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 8),
                                              child: Text(
                                                'Last 90d: $lines lines · ${_inr(_num(profit))} profit · avg ${_inr(_num(al))} → ${_inr(_num(ase))}'
                                                '${last != null ? ' · last $last' : ''}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      height: 1.35,
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
                                      if (v == 'edit') {
                                        _editItem(context, cats, it);
                                      }
                                      if (v == 'del') {
                                        _deleteItem(context, id, name);
                                      }
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem(
                                          value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(
                                          value: 'del', child: Text('Delete')),
                                    ],
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
      },
    );
  }

  Future<void> _addCategory(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createItemCategory(
            businessId: session.primaryBusiness.id,
            name: ctrl.text.trim(),
          );
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Category created')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _editCategory(
      BuildContext context, String id, String current) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _deleteCategory(
      BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Delete “$name”? It must have no items.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteItemCategory(
          businessId: session.primaryBusiness.id, categoryId: id);
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Category deleted')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _addItem(BuildContext context) async {
    final cats = await ref.read(itemCategoriesListProvider.future);
    if (!context.mounted) return;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a category first.')),
      );
      return;
    }
    var selectedCat = cats.first['id']?.toString();
    final nameCtrl = TextEditingController();
    String? unit;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New catalog item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedCat),
                  initialValue: selectedCat,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: cats
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c['id']?.toString(),
                          child: Text(c['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setSt(() => selectedCat = v),
                ),
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name')),
                DropdownButtonFormField<String?>(
                  key: ValueKey(unit),
                  initialValue: unit,
                  decoration: const InputDecoration(
                      labelText: 'Default unit (optional)'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('—')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'box', child: Text('box')),
                    DropdownMenuItem(value: 'piece', child: Text('piece')),
                  ],
                  onChanged: (v) => setSt(() => unit = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final categoryId = selectedCat;
    if (categoryId == null) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: categoryId,
            name: nameCtrl.text.trim(),
            defaultUnit: unit,
          );
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Item created')));
      }
    } on DioException catch (e) {
      final existing = _existingItemIdFrom409(e);
      if (existing != null && context.mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Item already exists'),
            content: const Text('Open the existing catalog item?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open')),
            ],
          ),
        );
        if (go == true && context.mounted) {
          context.push('/catalog/item/$existing');
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _editItem(
    BuildContext context,
    List<Map<String, dynamic>> cats,
    Map<String, dynamic> it,
  ) async {
    if (cats.isEmpty) return;
    final id = it['id']?.toString() ?? '';
    var selectedCat = it['category_id']?.toString();
    final nameCtrl = TextEditingController(text: it['name']?.toString() ?? '');
    var unit = it['default_unit']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Edit catalog item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedCat),
                  initialValue: selectedCat,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: cats
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c['id']?.toString(),
                          child: Text(c['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setSt(() => selectedCat = v),
                ),
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name')),
                DropdownButtonFormField<String?>(
                  key: ValueKey(unit),
                  initialValue: unit,
                  decoration: const InputDecoration(
                      labelText: 'Default unit (optional)'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('—')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'box', child: Text('box')),
                    DropdownMenuItem(value: 'piece', child: Text('piece')),
                  ],
                  onChanged: (v) => setSt(() => unit = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty || selectedCat == null) {
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: id,
            categoryId: selectedCat,
            name: nameCtrl.text.trim(),
            defaultUnit: unit,
          );
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      final existing = _existingItemIdFrom409(e);
      if (existing != null && context.mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Name already used'),
            content: const Text(
                'Another item in that category has this name. Open it?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open')),
            ],
          ),
        );
        if (go == true && context.mounted) {
          context.push('/catalog/item/$existing');
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _deleteItem(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete “$name” from the catalog?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteCatalogItem(
          businessId: session.primaryBusiness.id, itemId: id);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Item removed')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }
}
