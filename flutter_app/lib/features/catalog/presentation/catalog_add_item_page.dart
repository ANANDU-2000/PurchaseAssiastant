import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/form_feedback.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../shared/widgets/inline_search_field.dart';

const _kUnits = <String>['bag', 'box', 'kg', 'tin', 'piece'];

/// Add catalog item: category, subcategory, unit, defaults, at least one supplier.
class CatalogAddItemPage extends ConsumerStatefulWidget {
  const CatalogAddItemPage({
    super.key,
    required this.categoryId,
    required this.typeId,
  });

  final String categoryId;
  final String typeId;

  @override
  ConsumerState<CatalogAddItemPage> createState() => _CatalogAddItemPageState();
}

class _CatalogAddItemPageState extends ConsumerState<CatalogAddItemPage> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _kg = TextEditingController();
  final _perBox = TextEditingController();
  final _perTin = TextEditingController();
  final _hsn = TextEditingController();
  final _itemCode = TextEditingController();
  final _tax = TextEditingController();
  final _supplierSearch = TextEditingController();
  final _brokerSearch = TextEditingController();

  String? _categoryId;
  String? _typeId;
  String? _unit;
  final _supplierIds = <String>[];
  final _brokerIds = <String>[];

  bool _saving = false;
  bool _touched = false;
  String? _kgErr;
  String? _boxErr;
  String? _tinErr;

  static const _fieldPad = EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  static InputBorder _fieldBorder(BuildContext context) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      );

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _typeId = widget.typeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_offerResumeDraft()));
  }

  String get _activeDraftKey =>
      'catalog_draft_item_${_categoryId ?? widget.categoryId}_${_typeId ?? widget.typeId}';

  Future<void> _offerResumeDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_activeDraftKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    Map<String, dynamic>? m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>?;
    } catch (_) {}
    if (m == null) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resume item creation?'),
        content: const Text('You have an unsaved draft for this subcategory.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (!mounted) return;
    if (go == true) {
      setState(() {
        _name.text = m!['name']?.toString() ?? '';
        final rawU = m['unit']?.toString().trim();
        _unit = (rawU != null && rawU.isNotEmpty) ? rawU.toLowerCase() : null;
        _kg.text = m['kg']?.toString() ?? '';
        _perBox.text = m['perBox']?.toString() ?? '';
        _perTin.text = m['perTin']?.toString() ?? '';
        _hsn.text = m['hsn']?.toString() ?? '';
        _itemCode.text = m['itemCode']?.toString() ?? '';
        _tax.text = m['tax']?.toString() ?? '';
        if (m['categoryId'] != null) _categoryId = m['categoryId']?.toString();
        if (m['typeId'] != null) _typeId = m['typeId']?.toString();
        if (m['supplierIds'] is List) {
          _supplierIds
            ..clear()
            ..addAll((m['supplierIds'] as List).map((e) => e.toString()));
        }
        if (m['brokerIds'] is List) {
          _brokerIds
            ..clear()
            ..addAll((m['brokerIds'] as List).map((e) => e.toString()));
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    } else {
      await prefs.remove(_activeDraftKey);
    }
  }

  Future<void> _saveDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (_name.text.trim().isEmpty && _unit == null) {
      await prefs.remove(_activeDraftKey);
      return;
    }
    await prefs.setString(
      _activeDraftKey,
      jsonEncode({
        'name': _name.text,
        'unit': _unit,
        'kg': _kg.text,
        'perBox': _perBox.text,
        'perTin': _perTin.text,
        'hsn': _hsn.text,
        'itemCode': _itemCode.text,
        'tax': _tax.text,
        'categoryId': _categoryId,
        'typeId': _typeId,
        'supplierIds': _supplierIds,
        'brokerIds': _brokerIds,
      }),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _kg.dispose();
    _perBox.dispose();
    _perTin.dispose();
    _hsn.dispose();
    _itemCode.dispose();
    _tax.dispose();
    _supplierSearch.dispose();
    _brokerSearch.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_categoryId == null || _typeId == null) return false;
    if (_name.text.trim().isEmpty) return false;
    if (_unit == null || _unit!.isEmpty) return false;
    if (_supplierIds.isEmpty) return false;
    if (_unit == 'bag' && parseOptionalKgPerBag(_kg.text) == null) return false;
    if (_unit == 'box') {
      final v = double.tryParse(_perBox.text.trim());
      if (v == null || v <= 0) return false;
    }
    if (_unit == 'tin' && _perTin.text.trim().isNotEmpty) {
      final w = double.tryParse(_perTin.text.trim());
      if (w == null || w <= 0) return false;
    }
    return true;
  }

  String? _existingItemIdFrom409(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final d = e.response?.data;
    if (d is Map && d['detail'] is Map) {
      return (d['detail'] as Map)['existing_item_id']?.toString();
    }
    return null;
  }

  Future<void> _create() async {
    if (!_isValid) {
      setState(() => _touched = true);
      return;
    }
    if (_unit == 'bag') {
      final kg = parseOptionalKgPerBag(_kg.text);
      if (kg == null) {
        setState(() => _kgErr = 'Enter kg per bag (must be > 0)');
        return;
      }
    }
    if (_unit == 'box') {
      final v = double.tryParse(_perBox.text.trim());
      if (v == null || v <= 0) {
        setState(() => _boxErr = 'Items per box must be > 0');
        return;
      }
    }
    if (_unit == 'tin' && _perTin.text.trim().isNotEmpty) {
      final w = double.tryParse(_perTin.text.trim());
      if (w == null || w <= 0) {
        setState(() => _tinErr = 'Weight must be > 0');
        return;
      }
    }
    final taxRaw = _tax.text.trim();
    double? taxPct;
    if (taxRaw.isNotEmpty) {
      taxPct = double.tryParse(taxRaw);
      if (taxPct == null || taxPct < 0 || taxPct > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tax % must be between 0 and 100')),
          );
        }
        return;
      }
    }
    final hsn = _hsn.text.trim();
    final ic = _itemCode.text.trim();
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _saving = true);
    final tinW = _unit == 'tin' && _perTin.text.trim().isNotEmpty
        ? double.tryParse(_perTin.text.trim())
        : null;
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: _categoryId!,
            typeId: _typeId,
            name: _name.text.trim(),
            defaultUnit: _unit!,
            defaultSupplierIds: List<String>.from(_supplierIds),
            defaultBrokerIds: List<String>.from(_brokerIds),
            hsnCode: hsn.isEmpty ? null : hsn,
            itemCode: ic.isEmpty ? null : ic,
            taxPercent: taxPct,
            defaultPurchaseUnit: _unit,
            defaultKgPerBag: _unit == 'bag' ? parseOptionalKgPerBag(_kg.text) : null,
            defaultItemsPerBox: _unit == 'box' ? double.tryParse(_perBox.text.trim()) : null,
            defaultWeightPerTin: (tinW != null && tinW > 0) ? tinW : null,
          );
      await ref.read(sharedPreferencesProvider).remove(_activeDraftKey);
      ref.invalidate(catalogItemsListProvider);
      invalidateBusinessAggregates(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item created')),
        );
        context.pop(true);
      }
    } on DioException catch (e) {
      final existing = _existingItemIdFrom409(e);
      if (existing != null && mounted) {
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Similar item exists'),
            content: const Text('Open the existing catalog item?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
            ],
          ),
        );
        if (open == true) {
          if (!mounted) return;
          context.pop(false);
          if (!mounted) return;
          context.push('/catalog/item/$existing');
        }
        return;
      }
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: () {
          if (context.mounted) _create();
        });
      }
    } catch (e) {
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: () {
          if (context.mounted) _create();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Widget> _reviewLines(
    BuildContext context, {
    required List<Map<String, dynamic>> supplierRows,
    required List<Map<String, dynamic>> brokerRows,
  }) {
    final tt = Theme.of(context).textTheme;
    final name = _name.text.trim().isEmpty ? '—' : _name.text.trim();
    final u = _unit == null ? '—' : _unit!.toUpperCase();
    String unitDetail;
    if (_unit == 'bag') {
      final kg = _kg.text.trim().isEmpty ? '—' : _kg.text.trim();
      unitDetail = '$u · $kg kg/bag';
    } else if (_unit == 'box') {
      final pb = _perBox.text.trim().isEmpty ? '—' : _perBox.text.trim();
      unitDetail = '$u · $pb items/box';
    } else if (_unit == 'tin' && _perTin.text.trim().isNotEmpty) {
      unitDetail = '$u · ${_perTin.text.trim()} / tin';
    } else {
      unitDetail = u;
    }
    final supNames = _supplierIds
        .map((id) {
          for (final s in supplierRows) {
            if (s['id']?.toString() == id) {
              return s['name']?.toString() ?? id;
            }
          }
          return id;
        })
        .toList();
    final broNames = _brokerIds
        .map((id) {
          for (final b in brokerRows) {
            if (b['id']?.toString() == id) {
              return b['name']?.toString() ?? id;
            }
          }
          return id;
        })
        .toList();
    final code = _itemCode.text.trim();
    final hsn = _hsn.text.trim();
    final tax = _tax.text.trim();
    return [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            TextSpan(
              text: ' · $unitDetail',
              style: tt.bodySmall?.copyWith(
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      if (code.isNotEmpty || hsn.isNotEmpty || tax.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          [
            if (code.isNotEmpty) 'Code: $code',
            if (hsn.isNotEmpty) 'HSN: $hsn',
            if (tax.isNotEmpty) 'Tax: $tax%',
          ].join('  ·  '),
          style: tt.bodySmall?.copyWith(
            color: const Color(0xFF334155),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      if (supNames.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          'Suppliers: ${supNames.join(', ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tt.bodySmall?.copyWith(color: const Color(0xFF64748B)),
        ),
      ],
      if (broNames.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          'Brokers: ${broNames.join(', ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tt.bodySmall?.copyWith(color: const Color(0xFF64748B)),
        ),
      ],
    ];
  }

  Future<void> _onCategoryChanged(String? cid) async {
    if (cid == null) return;
    setState(() {
      _categoryId = cid;
      _typeId = null;
    });
    final types = await ref.read(categoryTypesListProvider(cid).future);
    if (!mounted) return;
    if (types.isNotEmpty) {
      setState(() => _typeId = types.first['id']?.toString());
    }
  }

  Widget _supplierChips(List<Map<String, dynamic>> allRows) {
    final nameById = {
      for (final s in allRows)
        if ((s['id']?.toString() ?? '').isNotEmpty)
          s['id'].toString(): s['name']?.toString() ?? '',
    };
    if (_supplierIds.isEmpty) {
      return Text(
        'Required — add at least one supplier who sells this item.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _touched && _supplierIds.isEmpty
                  ? HexaColors.loss
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final id in _supplierIds)
          InputChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                nameById[id] ?? id,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onDeleted: () => setState(() => _supplierIds.remove(id)),
          ),
      ],
    );
  }

  List<InlineSearchItem> _supplierPickItems(List<Map<String, dynamic>> list) {
    return [
      for (final s in list)
        if (!_supplierIds.contains(s['id']?.toString()))
          InlineSearchItem(
            id: s['id']?.toString() ?? '',
            label: s['name']?.toString() ?? 'Supplier',
            subtitle: (s['phone']?.toString() ?? '').trim().isEmpty
                ? null
                : s['phone']?.toString(),
          ),
    ];
  }

  List<InlineSearchItem> _brokerPickItems(List<Map<String, dynamic>> list) {
    return [
      for (final b in list)
        if (!_brokerIds.contains(b['id']?.toString()))
          InlineSearchItem(
            id: b['id']?.toString() ?? '',
            label: b['name']?.toString() ?? 'Broker',
            subtitle: (b['phone']?.toString() ?? '').trim().isEmpty
                ? null
                : b['phone']?.toString(),
          ),
    ];
  }

  Widget _brokerChips(List<Map<String, dynamic>> allRows) {
    final nameById = {
      for (final b in allRows)
        if ((b['id']?.toString() ?? '').isNotEmpty)
          b['id'].toString(): b['name']?.toString() ?? '',
    };
    if (_brokerIds.isEmpty) {
      return Text(
        'Optional default brokers for purchases.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final id in _brokerIds)
          InputChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                nameById[id] ?? id,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onDeleted: () => setState(() => _brokerIds.remove(id)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(itemCategoriesListProvider);
    final typesAsync = _categoryId != null
        ? ref.watch(categoryTypesListProvider(_categoryId!))
        : null;

    final typeName = typesAsync?.maybeWhen(
          data: (types) {
            for (final t in types) {
              if (t['id']?.toString() == _typeId) {
                return t['name']?.toString() ?? '';
              }
            }
            return '';
          },
          orElse: () => '',
        ) ??
        '';

    final items = ref.watch(catalogItemsListProvider).maybeWhen(
          data: (x) => x,
          orElse: () => <Map<String, dynamic>>[],
        );
    final sameType = items
        .where((it) => it['type_id']?.toString() == _typeId)
        .toList();
    final similar = catalogFuzzyRank(
      _name.text,
      sameType,
      (it) => it['name']?.toString() ?? '',
      minScore: 55,
      limit: 4,
    ).where((it) => (it['name']?.toString() ?? '').toLowerCase() != _name.text.trim().toLowerCase());

    final nameErr = _touched && _name.text.trim().isEmpty;
    final unitErr = _touched && (_unit == null || _unit!.isEmpty);
    final supErr = _touched && _supplierIds.isEmpty;
    final supRows = ref.watch(suppliersListProvider).maybeWhen(
          data: (raw) => raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          orElse: () => <Map<String, dynamic>>[],
        );
    final broRows = ref.watch(brokersListProvider).maybeWhen(
          data: (raw) => raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          orElse: () => <Map<String, dynamic>>[],
        );

    /// Bottom strip (review + create) sits in [Scaffold.bottomNavigationBar]; pad the scroll view
    /// so fields stay above it, the home indicator, and the keyboard.
    final bottomOverlay =
        MediaQuery.paddingOf(context).bottom + 200 + MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveDraft();
        if (!mounted) return;
        Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New item'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving
                ? null
                : () async {
                    await _saveDraft();
                    if (!mounted) return;
                    context.pop(false);
                  },
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomOverlay),
            children: [
              Text('Category & subcategory', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              categoriesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Could not load categories'),
                data: (cats) {
                  final cl = cats.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                  return DropdownButtonFormField<String>(
                    value: _categoryId,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      contentPadding: _fieldPad,
                      border: _fieldBorder(context),
                    ),
                    items: [
                      for (final c in cl)
                        DropdownMenuItem(
                          value: c['id']?.toString(),
                          child: Text(c['name']?.toString() ?? ''),
                        ),
                    ],
                    onChanged: (v) => _onCategoryChanged(v),
                  );
                },
              ),
              const SizedBox(height: 8),
              if (typesAsync != null)
                typesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Could not load subcategories'),
                  data: (types) {
                    final tl = types.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                    if (tl.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No subcategory (type) for this category yet. Add a type in Catalog for this category, then you can add products here.',
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _categoryId == null
                                  ? null
                                  : () => context.push('/catalog/category/$_categoryId'),
                              child: const Text('Open this category in Catalog'),
                            ),
                          ],
                        ),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      value: _typeId != null && tl.any((t) => t['id']?.toString() == _typeId)
                          ? _typeId
                          : tl.first['id']?.toString(),
                      decoration: InputDecoration(
                        labelText: 'Subcategory (type)',
                        contentPadding: _fieldPad,
                        border: _fieldBorder(context),
                      ),
                      items: [
                        for (final t in tl)
                          DropdownMenuItem(
                            value: t['id']?.toString(),
                            child: Text(t['name']?.toString() ?? ''),
                          ),
                      ],
                      onChanged: (v) => setState(() => _typeId = v),
                    );
                  },
                ),
              if (typeName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  typeName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                focusNode: _nameFocus,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Item name',
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                  errorText: nameErr ? 'Required' : null,
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: HexaColors.loss, width: 1.5),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_name.text.trim().length >= 2 && similar.isNotEmpty) ...[
                const SizedBox(height: 8),
                Material(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Similar in this subcategory',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF9A3412),
                              ),
                        ),
                        for (final it in similar)
                          Text(
                            '· ${it['name']}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text('Unit type', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in _kUnits)
                    ChoiceChip(
                      label: Text(u.toUpperCase()),
                      selected: _unit == u,
                      onSelected: (_) => setState(() {
                        _unit = u; // _kUnits are lowercase — keeps review + chips in sync
                        _kgErr = null;
                        _boxErr = null;
                        _tinErr = null;
                      }),
                    ),
                ],
                ),
              if (unitErr)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Select a unit',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HexaColors.loss),
                  ),
                ),
              if (_unit == 'bag') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _kg,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Kg per bag',
                    errorText: _kgErr,
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                  onChanged: (_) {
                    if (_kgErr != null) setState(() => _kgErr = null);
                  },
                ),
                const SizedBox(height: 8),
                const BagDefaultUnitHint(),
              ],
              if (_unit == 'box') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _perBox,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Items per box',
                    errorText: _boxErr,
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                  onChanged: (_) {
                    if (_boxErr != null) setState(() => _boxErr = null);
                    setState(() {});
                  },
                ),
              ],
              if (_unit == 'tin') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _perTin,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Weight per tin (optional)',
                    errorText: _tinErr,
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                  onChanged: (_) {
                    if (_tinErr != null) setState(() => _tinErr = null);
                    setState(() {});
                  },
                ),
              ],
              const SizedBox(height: 12),
              Text('Product code, HSN & tax', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              Text(
                'Match your price list: code, hsn, tax_rate (optional).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _itemCode,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Product / item code (optional)',
                  hintText: 'e.g. 2104',
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hsn,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'HSN / SAC (optional)',
                  hintText: 'e.g. 11010000',
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tax,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Default tax % (optional, GST)',
                  hintText: 'e.g. 5 or 0',
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text('Default suppliers *', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 4),
              if (supErr)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Add at least one supplier',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HexaColors.loss),
                  ),
                ),
              ref.watch(suppliersListProvider).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Could not load suppliers'),
                    data: (rows) {
                      final list =
                          rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                      if (list.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No suppliers yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => context.push('/contacts'),
                              icon: const Icon(Icons.group_add_outlined, size: 20),
                              label: const Text('Open Contacts to add a supplier'),
                            ),
                          ],
                        );
                      }
                      final pick = _supplierPickItems(list);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _supplierChips(list),
                          const SizedBox(height: 6),
                          if (pick.isNotEmpty) ...[
                            Text(
                              'Search and pick supplier (name or phone)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            InlineSearchField(
                              key: ValueKey('sup_srch_${_supplierIds.length}'),
                              items: pick,
                              controller: _supplierSearch,
                              placeholder: 'Type to search…',
                              minQueryLength: 1,
                              onSelected: (it) {
                                setState(() {
                                  if (it.id.isNotEmpty && !_supplierIds.contains(it.id)) {
                                    _supplierIds.add(it.id);
                                  }
                                  _supplierSearch.clear();
                                });
                              },
                            ),
                          ] else
                            Text(
                              _supplierIds.isEmpty
                                  ? '—'
                                  : 'All available suppliers are already added',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      );
                    },
                  ),
              const SizedBox(height: 12),
              Text('Default brokers (optional)', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 4),
              ref.watch(brokersListProvider).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Could not load brokers'),
                    data: (rows) {
                      final list =
                          rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                      if (list.isEmpty) {
                        return const Text('No brokers yet — you can skip.');
                      }
                      final pick = _brokerPickItems(list);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _brokerChips(list),
                          const SizedBox(height: 6),
                          if (pick.isNotEmpty) ...[
                            Text(
                              'Search and pick broker (optional)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            InlineSearchField(
                              key: ValueKey('bro_srch_${_brokerIds.length}'),
                              items: pick,
                              controller: _brokerSearch,
                              placeholder: 'Type to search…',
                              minQueryLength: 1,
                              onSelected: (it) {
                                setState(() {
                                  if (it.id.isNotEmpty && !_brokerIds.contains(it.id)) {
                                    _brokerIds.add(it.id);
                                  }
                                  _brokerSearch.clear();
                                });
                              },
                            ),
                          ] else
                            Text(
                              _brokerIds.isEmpty
                                  ? '—'
                                  : 'All available brokers are already added',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      );
                    },
                  ),
            ],
          ),
        ),
      ),
    ],
  ),
        bottomNavigationBar: Material(
          color: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
          elevation: 2,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Review', style: HexaDsType.formSectionLabel),
                  const SizedBox(height: 6),
                  ..._reviewLines(
                    context,
                    supplierRows: supRows,
                    brokerRows: broRows,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Unit prices are set on each purchase.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: (_saving || !_isValid) ? null : _create,
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: HexaColors.brandDisabledBg,
                      disabledForegroundColor: HexaColors.brandDisabledText,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isValid ? 'Create item' : 'Complete required fields'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
