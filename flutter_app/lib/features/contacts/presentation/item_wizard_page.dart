import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/contacts_hub_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
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
      ref.invalidate(contactsSuppliersEnrichedProvider);
      ref.invalidate(contactsBrokersEnrichedProvider);
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
          data: (rows) => DropdownButtonFormField<String>(
            key: ValueKey(_selectedCategoryId),
            initialValue: rows.any((c) => c['id']?.toString() == _selectedCategoryId)
                ? _selectedCategoryId
                : null,
            decoration: _d('Category *'),
            items: rows
                .map((c) => DropdownMenuItem<String>(
                      value: c['id']?.toString(),
                      child: Text(c['name']?.toString() ?? ''),
                    ))
                .toList(),
            onChanged: (v) {
              setState(() {
                _selectedCategoryId = v;
                _selectedTypeId = null;
                _markDirty();
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        typesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => DropdownButtonFormField<String?>(
            key: ValueKey('${_selectedCategoryId ?? ''}|${_selectedTypeId ?? ''}'),
            initialValue: rows.any((t) => t['id']?.toString() == _selectedTypeId)
                ? _selectedTypeId
                : null,
            decoration: _d('Subcategory / Type'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('General')),
              ...rows.map((t) => DropdownMenuItem<String?>(
                    value: t['id']?.toString(),
                    child: Text(t['name']?.toString() ?? ''),
                  )),
            ],
            onChanged: (v) {
              setState(() {
                _selectedTypeId = v;
                _markDirty();
              });
            },
          ),
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
        TextField(
          controller: _landing,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _d('Default landing cost'),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _selling,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _d('Default selling cost'),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 10),
        Text(
          'Tax/HSN fields are prepared in UX and can be persisted once catalog API accepts these columns.',
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
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load suppliers'),
          data: (rows) => Column(
            children: rows.map((e) {
              final s = Map<String, dynamic>.from(e as Map);
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
          ),
        ),
      ],
    );
  }

  Widget _stepBrokerMap() {
    final async = ref.watch(brokersListProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load brokers'),
          data: (rows) => Column(
            children: rows.map((e) {
              final b = Map<String, dynamic>.from(e as Map);
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
          ),
        ),
      ],
    );
  }

  Widget _stepReview() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        _card('Basic', [
          _kv('Name', _name.text.trim().isEmpty ? '—' : _name.text.trim()),
          _kv('Category', _selectedCategoryId ?? '—'),
          _kv('Type', _selectedTypeId ?? 'General'),
          _kv('Unit', _unit ?? '—'),
        ]),
        _card('Tax & Pricing', [
          _kv('HSN', _hsn.text.trim().isEmpty ? '—' : _hsn.text.trim()),
          _kv('Tax %', _tax.text.trim().isEmpty ? '—' : _tax.text.trim()),
          _kv('Landing', _landing.text.trim().isEmpty ? '—' : _landing.text.trim()),
          _kv('Selling', _selling.text.trim().isEmpty ? '—' : _selling.text.trim()),
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
