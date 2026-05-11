import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';

/// Bottom sheet for quick item creation from home dashboard.
class QuickAddItemSheet extends ConsumerStatefulWidget {
  const QuickAddItemSheet({super.key});

  @override
  ConsumerState<QuickAddItemSheet> createState() => _QuickAddItemSheetState();
}

class _QuickAddItemSheetState extends ConsumerState<QuickAddItemSheet> {
  final _nameCtrl = TextEditingController();
  final _kgCtrl = TextEditingController();

  String? _categoryId;
  String? _typeId;
  String _unit = 'kg';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(itemCategoriesListProvider);
    final typesAsync = _categoryId == null
        ? const AsyncValue<List<Map<String, dynamic>>>.data([])
        : ref.watch(categoryTypesListProvider(_categoryId!));

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add New Item',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          categoriesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load categories: $e'),
            data: (cats) {
              if (cats.isEmpty) {
                return const Text('No categories yet — create one in Catalog.');
              }
              return DropdownButtonFormField<String>(
                key: ValueKey<String?>('qa_cat_$_categoryId'),
                decoration: const InputDecoration(
                  labelText: 'Category *',
                  border: OutlineInputBorder(),
                ),
                initialValue: _categoryId,
                hint: const Text('Select category'),
                items: cats
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: c['id']?.toString(),
                        child: Text(
                          c['name']?.toString() ?? '—',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .where((e) => e.value != null && e.value!.isNotEmpty)
                    .toList(),
                onChanged: (id) => setState(() {
                  _categoryId = id;
                  _typeId = null;
                }),
              );
            },
          ),
          const SizedBox(height: 12),
          typesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load types: $e'),
            data: (types) {
              if (_categoryId == null) {
                return const SizedBox.shrink();
              }
              if (types.isEmpty) {
                return const Text(
                  'No subcategories (types) in this category yet.',
                );
              }
              return DropdownButtonFormField<String>(
                key: ValueKey<String?>('qa_type_${_categoryId}_$_typeId'),
                decoration: const InputDecoration(
                  labelText: 'Subcategory (type) *',
                  border: OutlineInputBorder(),
                ),
                initialValue: _typeId,
                hint: const Text('Select type'),
                items: types
                    .map(
                      (t) => DropdownMenuItem<String>(
                        value: t['id']?.toString(),
                        child: Text(
                          t['name']?.toString() ?? '—',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .where((e) => e.value != null && e.value!.isNotEmpty)
                    .toList(),
                onChanged: (id) => setState(() => _typeId = id),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Item name *',
              hintText: 'e.g. THUVARA JP 50 KG',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Unit: '),
              const SizedBox(width: 8),
              for (final u in ['kg', 'bag', 'box', 'tin', 'piece'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(u),
                    selected: _unit == u,
                    onSelected: (_) => setState(() {
                      _unit = u;
                      _kgCtrl.clear();
                    }),
                  ),
                ),
            ],
          ),
          if (_unit == 'bag') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _kgCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Kg per bag',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Item'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _error = 'Item name is required.');
      return;
    }
    if (_categoryId == null || _categoryId!.isEmpty) {
      setState(() => _error = 'Select a category.');
      return;
    }
    if (_typeId == null || _typeId!.isEmpty) {
      setState(() => _error = 'Select a subcategory (type).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final session = ref.read(sessionProvider);
    if (session == null) {
      setState(() => _saving = false);
      return;
    }
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: _categoryId!,
            name: name,
            typeId: _typeId,
            defaultUnit: _unit,
            defaultSupplierIds: const [],
            defaultKgPerBag: _unit == 'bag'
                ? double.tryParse(_kgCtrl.text.trim())
                : null,
          );
      ref.invalidate(catalogItemsListProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Item "$name" created')),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not create item: $e';
      });
    }
  }
}
