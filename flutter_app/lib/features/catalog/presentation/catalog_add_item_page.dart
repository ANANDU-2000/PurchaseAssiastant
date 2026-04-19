import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';

const _kUnits = <String>['bag', 'box', 'kg', 'piece'];

String _draftKey(String categoryId, String typeId) =>
    'catalog_draft_item_${categoryId}_$typeId';

/// Full-screen single-step add catalog item (no HSN/tax/variants).
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
  String? _unit;
  bool _saving = false;
  bool _touched = false;
  bool _showAdvanced = false;

  static const _fieldPad = EdgeInsets.symmetric(horizontal: 14, vertical: 16);
  static InputBorder _fieldBorder(BuildContext context) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerResumeDraft());
  }

  Future<void> _offerResumeDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_draftKey(widget.categoryId, widget.typeId));
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
        _unit = m['unit']?.toString();
        _kg.text = m['kg']?.toString() ?? '';
        _perBox.text = m['perBox']?.toString() ?? '';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    } else {
      await prefs.remove(_draftKey(widget.categoryId, widget.typeId));
    }
  }

  Future<void> _saveDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (_name.text.trim().isEmpty && _unit == null) {
      await prefs.remove(_draftKey(widget.categoryId, widget.typeId));
      return;
    }
    await prefs.setString(
      _draftKey(widget.categoryId, widget.typeId),
      jsonEncode({
        'name': _name.text,
        'unit': _unit,
        'kg': _kg.text,
        'perBox': _perBox.text,
      }),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _kg.dispose();
    _perBox.dispose();
    super.dispose();
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
    final n = _name.text.trim();
    if (n.isEmpty) {
      setState(() => _touched = true);
      return;
    }
    if (_unit == null || _unit!.isEmpty) {
      setState(() => _touched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a unit type')),
      );
      return;
    }
    if (_unit == 'bag') {
      final kg = parseOptionalKgPerBag(_kg.text);
      if (kg == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter kg per bag for bag unit')),
        );
        return;
      }
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: widget.categoryId,
            typeId: widget.typeId,
            name: n,
            defaultUnit: _unit,
            defaultPurchaseUnit: _unit,
            defaultKgPerBag: _unit == 'bag' ? parseOptionalKgPerBag(_kg.text) : null,
          );
      await ref.read(sharedPreferencesProvider).remove(_draftKey(widget.categoryId, widget.typeId));
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
          // ignore: use_build_context_synchronously
          context.pop(false);
          if (!mounted) return;
          // ignore: use_build_context_synchronously
          context.push('/catalog/item/$existing');
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _reviewLine() {
    final name = _name.text.trim().isEmpty ? '—' : _name.text.trim();
    final u = _unit == null ? '—' : _unit!.toUpperCase();
    if (_unit == 'bag') {
      final kg = _kg.text.trim().isEmpty ? '—' : _kg.text.trim();
      return '$name · $u · $kg kg/bag';
    }
    if (_unit == 'box') {
      final pb = _perBox.text.trim().isEmpty ? '—' : _perBox.text.trim();
      return '$name · $u · $pb items/box';
    }
    return '$name · $u';
  }

  @override
  Widget build(BuildContext context) {
    final typeName = ref.watch(categoryTypesListProvider(widget.categoryId)).maybeWhen(
          data: (types) {
            for (final t in types) {
              if (t['id']?.toString() == widget.typeId) {
                return t['name']?.toString() ?? '';
              }
            }
            return '';
          },
          orElse: () => '',
        );

    final items = ref.watch(catalogItemsListProvider).maybeWhen(
          data: (x) => x,
          orElse: () => <Map<String, dynamic>>[],
        );
    final sameType = items
        .where((it) => it['type_id']?.toString() == widget.typeId)
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveDraft();
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New item'),
              if (typeName.isNotEmpty)
                Text(
                  typeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving
                ? null
                : () async {
                    await _saveDraft();
                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    context.pop(false);
                  },
          ),
        ),
        body: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              TextField(
                controller: _name,
                focusNode: _nameFocus,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Item name',
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
              const SizedBox(height: 16),
              Text(
                'Unit type',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in _kUnits)
                    ChoiceChip(
                      label: Text(u.toUpperCase()),
                      selected: _unit == u,
                      onSelected: (_) => setState(() => _unit = u),
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
                const SizedBox(height: 14),
                TextField(
                  controller: _kg,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Kg per bag',
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                ),
                const SizedBox(height: 8),
                const BagDefaultUnitHint(),
              ],
              if (_unit == 'box') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _perBox,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Items per box (optional, local note)',
                    helperText: 'Not synced to server yet — for your reference only.',
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _reviewLine(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rates and profit are set on each purchase — not here.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text('Show advanced'),
                initiallyExpanded: _showAdvanced,
                onExpansionChanged: (v) => setState(() => _showAdvanced = v),
                children: [
                  Text(
                    'Supplier and broker defaults are set when you record a purchase with that party — not on the catalog item.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _create,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create item'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
