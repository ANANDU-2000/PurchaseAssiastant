import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';

/// Master categories + catalog items (per business).
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

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
      body: TabBarView(
        controller: _tabs,
        children: [
          _categoriesBody(context),
          _itemsBody(context),
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
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(itemCategoriesListProvider);
          await ref.read(itemCategoriesListProvider.future);
        },
        child: list.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No categories yet. Tap Category to add one.')),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  final id = c['id']?.toString() ?? '';
                  final name = c['name']?.toString() ?? '';
                  return Card(
                    child: ListTile(
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editCategory(context, id, name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteCategory(context, id, name),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _itemsBody(BuildContext context) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    return catsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (cats) {
        return itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (items) {
            final catName = <String, String>{
              for (final c in cats) c['id'].toString(): c['name'].toString(),
            };
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(itemCategoriesListProvider);
                ref.invalidate(catalogItemsListProvider);
                await ref.read(catalogItemsListProvider.future);
              },
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            cats.isEmpty ? 'Add a category first, then catalog items.' : 'No catalog items yet.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final id = it['id']?.toString() ?? '';
                        final cid = it['category_id']?.toString() ?? '';
                        final name = it['name']?.toString() ?? '';
                        final du = it['default_unit']?.toString();
                        final subtitle =
                            '${catName[cid] ?? cid}${du != null && du.isNotEmpty ? ' · default $du' : ''}';
                        return Card(
                          child: ListTile(
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(subtitle),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editItem(context, cats, it),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteItem(context, id, name),
                                ),
                              ],
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category created')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.response?.data?.toString() ?? '$e')));
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
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
      await ref.read(hexaApiProvider).deleteItemCategory(businessId: session.primaryBusiness.id, categoryId: id);
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                DropdownButtonFormField<String?>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Default unit (optional)'),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item created')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                DropdownButtonFormField<String?>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Default unit (optional)'),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty || selectedCat == null) return;
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteCatalogItem(businessId: session.primaryBusiness.id, itemId: id);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item removed')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
