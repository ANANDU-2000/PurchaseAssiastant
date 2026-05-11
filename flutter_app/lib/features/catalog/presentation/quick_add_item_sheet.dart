import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';

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
  String? _supplierId;
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
    final dropdownMenuMax =
        math.min(260.0, MediaQuery.sizeOf(context).height * 0.38);
    final categoriesAsync = ref.watch(itemCategoriesListProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);
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
      child: SingleChildScrollView(
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
            error: (e, st) {
              logSilencedApiError(e, st);
              return Text(
                'Could not load categories. ${userFacingError(e)}',
                style: const TextStyle(color: Colors.red),
              );
            },
            data: (cats) {
              if (cats.isEmpty) {
                return const Text('No categories yet — create one in Catalog.');
              }
              return DropdownButtonFormField<String>(
                key: ValueKey<String?>('qa_cat_$_categoryId'),
                menuMaxHeight: dropdownMenuMax,
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
            error: (e, st) {
              logSilencedApiError(e, st);
              return Text(
                'Could not load subcategories. ${userFacingError(e)}',
                style: const TextStyle(color: Colors.red),
              );
            },
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
                menuMaxHeight: dropdownMenuMax,
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
          suppliersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, st) {
              logSilencedApiError(e, st);
              return Text(
                'Could not load suppliers. ${userFacingError(e)}',
                style: const TextStyle(color: Colors.red),
              );
            },
            data: (sups) {
              if (sups.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Add at least one supplier in Contacts before creating items.',
                    style: TextStyle(
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                );
              }
              if (sups.length == 1) {
                final n = sups.first['name']?.toString() ?? 'Supplier';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Default supplier: $n',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String?>('qa_sup_$_supplierId'),
                  menuMaxHeight: dropdownMenuMax,
                  decoration: const InputDecoration(
                    labelText: 'Default supplier *',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _supplierId,
                  hint: const Text('Select supplier'),
                  items: sups
                      .map(
                        (s) => DropdownMenuItem<String>(
                          value: s['id']?.toString(),
                          child: Text(
                            s['name']?.toString() ?? '—',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .where((e) => e.value != null && e.value!.isNotEmpty)
                      .toList(),
                  onChanged: (id) => setState(() => _supplierId = id),
                ),
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
              for (final u in ['kg', 'bag', 'piece'])
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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Box or tin units: use Catalog → Add item.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (_unit == 'bag') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _kgCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Weight per bag (kg)',
                hintText: 'e.g. 50',
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
    final sups = ref.read(suppliersListProvider).valueOrNull ?? [];
    if (sups.isEmpty) {
      setState(() => _error = 'Add at least one supplier in Contacts before creating an item.');
      return;
    }
    final supplierId = sups.length == 1
        ? (sups.first['id']?.toString() ?? '')
        : (_supplierId ?? '');
    if (supplierId.isEmpty) {
      setState(() => _error = 'Select a default supplier.');
      return;
    }
    if (_unit == 'bag') {
      final kg = double.tryParse(_kgCtrl.text.trim());
      if (kg == null || kg <= 0) {
        setState(() => _error = 'Please enter weight per bag (kg).');
        return;
      }
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
            defaultSupplierIds: [supplierId],
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
    } catch (e, st) {
      logSilencedApiError(e, st);
      setState(() {
        _saving = false;
        _error = 'Unable to save item. ${userFacingError(e)}';
      });
    }
  }
}
