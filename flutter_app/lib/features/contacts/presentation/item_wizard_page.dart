import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../shared/widgets/full_screen_form_scaffold.dart';

class ItemWizardPage extends ConsumerStatefulWidget {
  const ItemWizardPage({super.key, this.initialCategoryId});

  final String? initialCategoryId;

  @override
  ConsumerState<ItemWizardPage> createState() => _ItemWizardPageState();
}

class _ItemWizardPageState extends ConsumerState<ItemWizardPage> {
  int _step = 0;
  bool _dirty = false;
  String? _selectedCategoryId;
  String? _selectedTypeId;
  String? _unit;
  final _name = TextEditingController();
  final _kg = TextEditingController();
  final _hsn = TextEditingController();
  final _tax = TextEditingController();
  final _landing = TextEditingController();
  final _selling = TextEditingController();
  final _supplierIds = <String>{};
  final _brokerIds = <String>{};
  String? _nameError;
  final _supplierFilter = TextEditingController();
  final _brokerFilter = TextEditingController();
  static const _typeGeneralValue = '__general__';

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
  }

  @override
  void dispose() {
    _name.dispose();
    _kg.dispose();
    _hsn.dispose();
    _tax.dispose();
    _landing.dispose();
    _selling.dispose();
    _supplierFilter.dispose();
    _brokerFilter.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  InputDecoration _d(String label, {String? hint}) => InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Future<void> _exit() async {
    if (!_dirty || !mounted) {
      if (mounted) context.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save draft?'),
        content: const Text('You have unsaved item changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
        ],
      ),
    );
    if (leave == true && mounted) context.pop();
  }

  bool _validateBasic() {
    _nameError = null;
    if (_selectedCategoryId == null || _selectedCategoryId!.isEmpty) {
      _nameError = 'Pick a category';
    } else if (_name.text.trim().isEmpty) {
      _nameError = 'Item name is required';
    }
    setState(() {});
    return _nameError == null;
  }

  Map<String, dynamic> _parsePrefs(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return {'category_ids': <String>[], 'type_ids': <String>[], 'item_ids': <String>[]};
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'category_ids': ((m['category_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
        'type_ids': ((m['type_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
        'item_ids': ((m['item_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
      };
    } catch (_) {
      return {'category_ids': <String>[], 'type_ids': <String>[], 'item_ids': <String>[]};
    }
  }

  Future<void> _syncSupplierItemMap(String businessId, String itemId) async {
    final rows = await ref.read(suppliersListProvider.future);
    for (final r in rows) {
      final s = Map<String, dynamic>.from(r as Map);
      final sid = s['id']?.toString();
      if (sid == null || !_supplierIds.contains(sid)) continue;
      final prefs = _parsePrefs(s['preferences_json']?.toString());
      final categoryIds = List<String>.from(prefs['category_ids'] as List);
      final typeIds = List<String>.from(prefs['type_ids'] as List);
      final itemIds = List<String>.from(prefs['item_ids'] as List);
      if (_selectedCategoryId != null && !categoryIds.contains(_selectedCategoryId)) {
        categoryIds.add(_selectedCategoryId!);
      }
      if (_selectedTypeId != null && !typeIds.contains(_selectedTypeId)) {
        typeIds.add(_selectedTypeId!);
      }
      if (!itemIds.contains(itemId)) itemIds.add(itemId);
      await ref.read(hexaApiProvider).updateSupplier(
            businessId: businessId,
            supplierId: sid,
            preferences: {
              'category_ids': categoryIds,
              'type_ids': typeIds,
              'item_ids': itemIds,
            },
          );
    }
  }

  Future<void> _syncBrokerItemMap(String businessId, String itemId) async {
    final rows = await ref.read(brokersListProvider.future);
    for (final r in rows) {
      final b = Map<String, dynamic>.from(r as Map);
      final bid = b['id']?.toString();
      if (bid == null || !_brokerIds.contains(bid)) continue;
      final prefs = _parsePrefs(b['preferences_json']?.toString());
      final categoryIds = List<String>.from(prefs['category_ids'] as List);
      final typeIds = List<String>.from(prefs['type_ids'] as List);
      final itemIds = List<String>.from(prefs['item_ids'] as List);
      if (_selectedCategoryId != null && !categoryIds.contains(_selectedCategoryId)) {
        categoryIds.add(_selectedCategoryId!);
      }
      if (_selectedTypeId != null && !typeIds.contains(_selectedTypeId)) {
        typeIds.add(_selectedTypeId!);
      }
      if (!itemIds.contains(itemId)) itemIds.add(itemId);
      await ref.read(hexaApiProvider).updateBroker(
            businessId: businessId,
            brokerId: bid,
            preferences: {
              'category_ids': categoryIds,
              'type_ids': typeIds,
              'item_ids': itemIds,
            },
          );
    }
  }

  Future<void> _save() async {
    if (!_validateBasic()) {
      setState(() => _step = 0);
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    try {
      final created = await ref.read(hexaApiProvider).createCatalogItem(
            businessId: bid,
            categoryId: _selectedCategoryId!,
            typeId: _selectedTypeId,
            name: _name.text.trim(),
            defaultUnit: _unit,
            defaultKgPerBag:
                _unit == 'bag' ? parseOptionalKgPerBag(_kg.text) : null,
            defaultPurchaseUnit: _unit,
            hsnCode: _hsn.text.trim().isEmpty ? null : _hsn.text.trim(),
            taxPercent: double.tryParse(_tax.text),
            defaultLandingCost: double.tryParse(_landing.text),
            defaultSellingCost: double.tryParse(_selling.text),
          );
      final itemId = created['id']?.toString();
      if (itemId != null && itemId.isNotEmpty) {
        await _syncSupplierItemMap(bid, itemId);
        await _syncBrokerItemMap(bid, itemId);
      }
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(itemCategoriesListProvider);
      invalidateBusinessAggregates(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Item created')));
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    }
  }

  Widget _stepBasic() {
    final cats = ref.watch(itemCategoriesListProvider);
    final typesAsync = _selectedCategoryId == null
        ? const AsyncData<List<Map<String, dynamic>>>([])
        : ref.watch(categoryTypesListProvider(_selectedCategoryId!));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        cats.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load categories'),
          data: (rows) {
            if (rows.isEmpty) {
              return const Text('No categories — add one in catalog first.');
            }
            final entries = rows
                .map(
                  (c) => DropdownMenuEntry<String>(
                    value: c['id']?.toString() ?? '',
                    label: c['name']?.toString() ?? '',
                  ),
                )
                .toList();
            final nameById = {
              for (final c in rows) c['id']?.toString() ?? '': c['name']?.toString() ?? '',
            };
            return LayoutBuilder(
              builder: (context, c) {
                return DropdownMenu<String>(
                  width: c.maxWidth,
                  menuHeight: 320,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  label: const Text('Category *'),
                  hintText: 'Search categories',
                  initialSelection:
                      _selectedCategoryId != null && rows.any((r) => r['id']?.toString() == _selectedCategoryId)
                          ? _selectedCategoryId
                          : null,
                  filterCallback: (list, filter) {
                    final q = filter.trim();
                    if (q.isEmpty) return list;
                    final ids = list.map((e) => e.value).toList();
                    final ranked = catalogFuzzyRank(
                      q,
                      ids,
                      (id) => nameById[id] ?? '',
                      minScore: 18,
                      limit: 200,
                    );
                    if (ranked.isEmpty) return const <DropdownMenuEntry<String>>[];
                    final set = ranked.toSet();
                    return list.where((e) => set.contains(e.value)).toList();
                  },
                  onSelected: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedCategoryId = v;
                      _selectedTypeId = null;
                      _markDirty();
                    });
                  },
                  dropdownMenuEntries: entries,
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
        typesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) {
            final entries = <DropdownMenuEntry<String>>[
              const DropdownMenuEntry<String>(
                value: _typeGeneralValue,
                label: 'General (no subcategory)',
              ),
              ...rows.map(
                (t) => DropdownMenuEntry<String>(
                  value: t['id']?.toString() ?? '',
                  label: t['name']?.toString() ?? '',
                ),
              ),
            ];
            final nameById = <String, String>{
              _typeGeneralValue: 'General',
              for (final t in rows) t['id']?.toString() ?? '': t['name']?.toString() ?? '',
            };
            final initial = _selectedTypeId != null &&
                    rows.any((t) => t['id']?.toString() == _selectedTypeId)
                ? _selectedTypeId!
                : _typeGeneralValue;
            return LayoutBuilder(
              builder: (context, c) {
                return DropdownMenu<String>(
                  width: c.maxWidth,
                  menuHeight: 280,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  label: const Text('Subcategory / type'),
                  hintText: 'Search subcategories',
                  initialSelection: initial,
                  filterCallback: (list, filter) {
                    final q = filter.trim();
                    if (q.isEmpty) return list;
                    final ids = list.map((e) => e.value).toList();
                    final ranked = catalogFuzzyRank(
                      q,
                      ids,
                      (id) => nameById[id] ?? '',
                      minScore: 18,
                      limit: 200,
                    );
                    if (ranked.isEmpty) return const <DropdownMenuEntry<String>>[];
                    final set = ranked.toSet();
                    return list.where((e) => set.contains(e.value)).toList();
                  },
                  onSelected: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedTypeId = v == _typeGeneralValue ? null : v;
                      _markDirty();
                    });
                  },
                  dropdownMenuEntries: entries,
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: _d('Item Name *', hint: 'e.g. Ponni rice')
              .copyWith(errorText: _nameError),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: ValueKey(_unit),
          initialValue: _unit,
          decoration: _d('Unit Type'),
          items: const [
            DropdownMenuItem(value: null, child: Text('—')),
            DropdownMenuItem(value: 'kg', child: Text('kg')),
            DropdownMenuItem(value: 'bag', child: Text('bag')),
            DropdownMenuItem(value: 'box', child: Text('box')),
            DropdownMenuItem(value: 'tin', child: Text('tin')),
            DropdownMenuItem(value: 'piece', child: Text('pc')),
          ],
          onChanged: (v) {
            setState(() {
              _unit = v;
              _markDirty();
            });
          },
        ),
        if (_unit == 'bag') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _kg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _d('Default kg per bag'),
            onChanged: (_) => _markDirty(),
          ),
        ],
      ],
    );
  }

  Widget _stepTaxAndPricing() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Advanced: HSN & tax %',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          subtitle: const Text('Optional — hide until you need compliance fields'),
          children: [
            TextField(
              controller: _hsn,
              decoration: _d('HSN Code'),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tax,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _d('Tax %'),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 8),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _landing,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _d(
            'Delivered / landed cost (₹)',
            hint: 'Optional default per unit — same as purchase “landing”',
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _selling,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _d(
            'Billing / sell rate (₹)',
            hint: 'Optional default sell price per unit',
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 10),
        Text(
          'Freight, mandi fees, and billing adjustments are tracked on each purchase entry. '
          'Tax/HSN here sync to catalog when the API accepts them.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _stepSupplierMap() {
    final async = ref.watch(suppliersListProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        TextField(
          controller: _supplierFilter,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search suppliers',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () async {
                final rows = await ref.read(suppliersListProvider.future);
                setState(() {
                  for (final e in rows) {
                    final sid = Map<String, dynamic>.from(e as Map)['id']?.toString();
                    if (sid != null && sid.isNotEmpty) _supplierIds.add(sid);
                  }
                  _markDirty();
                });
              },
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _supplierIds.clear();
                _markDirty();
              }),
              child: const Text('Clear all'),
            ),
          ],
        ),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load suppliers'),
          data: (rows) {
            final q = _supplierFilter.text.trim();
            final list = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final filtered = q.isEmpty
                ? list
                : catalogFuzzyRank(
                    q,
                    list,
                    (s) =>
                        '${s['name'] ?? ''} ${s['location'] ?? ''} ${s['phone'] ?? ''}',
                    minScore: 18,
                    limit: 500,
                  );
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No suppliers match “$q”.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            return Column(
              children: filtered.map((s) {
                final sid = s['id']?.toString() ?? '';
                final checked = _supplierIds.contains(sid);
                final lbl = s['name']?.toString() ?? '';
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _supplierIds.add(sid);
                      } else {
                        _supplierIds.remove(sid);
                      }
                      _markDirty();
                    });
                  },
                  title: Text(lbl),
                  subtitle: Text(s['location']?.toString() ?? ''),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _stepBrokerMap() {
    final async = ref.watch(brokersListProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        TextField(
          controller: _brokerFilter,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search brokers',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () async {
                final rows = await ref.read(brokersListProvider.future);
                setState(() {
                  for (final e in rows) {
                    final bid = Map<String, dynamic>.from(e as Map)['id']?.toString();
                    if (bid != null && bid.isNotEmpty) _brokerIds.add(bid);
                  }
                  _markDirty();
                });
              },
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _brokerIds.clear();
                _markDirty();
              }),
              child: const Text('Clear all'),
            ),
          ],
        ),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load brokers'),
          data: (rows) {
            final q = _brokerFilter.text.trim();
            final list = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final filtered = q.isEmpty
                ? list
                : catalogFuzzyRank(
                    q,
                    list,
                    (b) =>
                        '${b['name'] ?? ''} ${b['location'] ?? ''} ${b['phone'] ?? ''}',
                    minScore: 18,
                    limit: 500,
                  );
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No brokers match “$q”.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            return Column(
              children: filtered.map((b) {
                final bid = b['id']?.toString() ?? '';
                final checked = _brokerIds.contains(bid);
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _brokerIds.add(bid);
                      } else {
                        _brokerIds.remove(bid);
                      }
                      _markDirty();
                    });
                  },
                  title: Text(b['name']?.toString() ?? ''),
                  subtitle: Text('Commission: ${b['commission_value'] ?? '—'}'),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _stepReview() {
    String categoryLabel() {
      if (_selectedCategoryId == null) return '—';
      final rows = ref.watch(itemCategoriesListProvider).valueOrNull;
      if (rows == null) return _selectedCategoryId!;
      for (final c in rows) {
        if (c['id']?.toString() == _selectedCategoryId) {
          return c['name']?.toString() ?? _selectedCategoryId!;
        }
      }
      return _selectedCategoryId!;
    }

    String typeLabel() {
      if (_selectedTypeId == null) return 'General';
      if (_selectedCategoryId == null) return _selectedTypeId!;
      final rows = ref.watch(categoryTypesListProvider(_selectedCategoryId!)).valueOrNull;
      if (rows == null) return _selectedTypeId!;
      for (final t in rows) {
        if (t['id']?.toString() == _selectedTypeId) {
          return t['name']?.toString() ?? _selectedTypeId!;
        }
      }
      return _selectedTypeId!;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        _card('Basic', [
          _kv('Name', _name.text.trim().isEmpty ? '—' : _name.text.trim()),
          _kv('Category', categoryLabel()),
          _kv('Type', typeLabel()),
          _kv('Unit', _unit ?? '—'),
        ]),
        _card('Tax & Pricing', [
          _kv('HSN', _hsn.text.trim().isEmpty ? '—' : _hsn.text.trim()),
          _kv('Tax %', _tax.text.trim().isEmpty ? '—' : _tax.text.trim()),
          _kv('Delivered cost', _landing.text.trim().isEmpty ? '—' : _landing.text.trim()),
          _kv('Billing / sell', _selling.text.trim().isEmpty ? '—' : _selling.text.trim()),
        ]),
        _card('Connections', [
          _kv('Suppliers linked', '${_supplierIds.length}'),
          _kv('Brokers linked', '${_brokerIds.length}'),
        ]),
      ],
    );
  }

  Widget _card(String t, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ...rows,
      ]),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
              width: 120,
              child: Text(k,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        return _stepBasic();
      case 1:
        return _stepTaxAndPricing();
      case 2:
        return _stepSupplierMap();
      case 3:
        return _stepBrokerMap();
      default:
        return _stepReview();
    }
  }

  Widget _footer() {
    final finalStep = _step == 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          TextButton(onPressed: _exit, child: const Text('Cancel')),
          const Spacer(),
          if (finalStep)
            FilledButton(onPressed: _save, child: const Text('Save Item'))
          else
            FilledButton(
              onPressed: () {
                if (_step == 0 && !_validateBasic()) return;
                setState(() {
                  _step++;
                  _dirty = true;
                });
              },
              child: const Text('Next'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Basic',
      'Tax & Identification',
      'Supplier Mapping',
      'Broker Mapping',
      'Review',
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _exit();
      },
      child: FullScreenFormScaffold(
        title: 'New item',
        subtitle: '${titles[_step]} · Step ${_step + 1} of ${titles.length}',
        onBackPressed: () {
          if (_step > 0) {
            setState(() => _step--);
          } else {
            unawaited(_exit());
          }
        },
        body: _body(),
        bottom: _footer(),
      ),
    );
  }
}
