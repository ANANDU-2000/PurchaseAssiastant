import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strict_decimal.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';
import '../widgets/party_inline_suggest_field.dart';

typedef OpenAdvancedItemSheet = Future<void> Function({
  int? editIndex,
  Map<String, dynamic>? initialOverride,
});

/// Keyboard-first bulk item entry — heavy editor is fallback only.
class PurchaseFastItemsStep extends ConsumerStatefulWidget {
  const PurchaseFastItemsStep({
    super.key,
    required this.catalog,
    required this.businessIdOrNull,
    required this.resolveLastTradeDefaults,
    required this.resolveCatalogItemRow,
    required this.onDraftChanged,
    required this.openAdvancedItemEditor,
    this.defaultsSideEffect,
  });

  final List<Map<String, dynamic>> catalog;
  final String? businessIdOrNull;
  final Future<Map<String, dynamic>> Function(String catalogItemId)
      resolveLastTradeDefaults;
  final Future<Map<String, dynamic>> Function(String catalogItemId)
      resolveCatalogItemRow;
  final VoidCallback onDraftChanged;
  final OpenAdvancedItemSheet openAdvancedItemEditor;

  /// When last-defaults resolves header tweaks (broker, payment days) — mirror wizard/sheet parity.
  final void Function(Map<String, dynamic> payload)? defaultsSideEffect;

  @override
  ConsumerState<PurchaseFastItemsStep> createState() =>
      _PurchaseFastItemsStepState();
}

class _PurchaseFastItemsStepState extends ConsumerState<PurchaseFastItemsStep> {
  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rateCtrl = TextEditingController();

  String? _pickedCatalogId;
  Map<String, dynamic>? _pickedCatalogRow;
  Map<String, dynamic>? _lastDefaults;
  String? _hint;
  Timer? _defaultsDebounced;

  int _defsSeq = 0;

  @override
  void dispose() {
    _defaultsDebounced?.cancel();
    _itemCtrl.dispose();
    _itemFocus.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  static double? _num(Object? x) {
    if (x is num) return x.toDouble();
    return null;
  }

  Future<void> _scheduleDefaultsFetch(String catalogId) async {
    _defaultsDebounced?.cancel();
    if (widget.businessIdOrNull == null ||
        catalogId.isEmpty ||
        widget.catalog.isEmpty) {
      setState(() {
        _lastDefaults = null;
        _hint = null;
      });
      return;
    }
    final seq = ++_defsSeq;
    _defaultsDebounced = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted || seq != _defsSeq) return;
      try {
        Map<String, dynamic>? catalogRowLocal;
        for (final m in widget.catalog) {
          if (m['id']?.toString() == catalogId) {
            catalogRowLocal = Map<String, dynamic>.from(m);
            break;
          }
        }

        Map<String, dynamic> fetchedRow =
            catalogRowLocal ?? <String, dynamic>{};
        if (fetchedRow.isEmpty) {
          final fetched = await widget.resolveCatalogItemRow(catalogId);
          if (fetched.isNotEmpty) {
            fetchedRow = Map<String, dynamic>.from(fetched);
          }
        }
        if (!mounted || seq != _defsSeq) return;

        final def =
            Map<String, dynamic>.from(await widget.resolveLastTradeDefaults(catalogId));
        if (!mounted || seq != _defsSeq) return;

        widget.defaultsSideEffect?.call(def);

        setState(() {
          _pickedCatalogRow = fetchedRow.isEmpty ? null : fetchedRow;

          final src = def['source']?.toString();
          final rate = _num(def['purchase_rate'] ?? def['landing_cost']);
          final unit = def['unit']?.toString().trim();

          final displayName = (fetchedRow['name'] ??
                  fetchedRow['item_name'] ??
                  _itemCtrl.text)
              .toString()
              .trim();

          final dateHint =
              def['purchase_date']?.toString().split('T').first;

          final supHint =
              unit != null && unit.isNotEmpty ? ' • unit $unit' : '';

          _lastDefaults = def;
          if (rate != null && rate > 0) {
            _rateCtrl.text =
                StrictDecimal.fromObject(rate).format(3, trim: true);
          }
          if (src != null && src != 'none') {
            _hint =
                '${displayName.isNotEmpty ? displayName + ' · ' : ''}Last purchase: $src${dateHint != null ? ' ($dateHint)' : ''}$supHint';
          } else {
            _hint =
                '${displayName.isNotEmpty ? displayName + ' — ' : ''}No matched prior trade defaults for supplier/broker/item (use Advanced for complex units).';
          }
          if (_qtyCtrl.text.trim().isEmpty) {
            _qtyCtrl.text = '1';
          }
        });
      } catch (_) {
        if (!mounted || seq != _defsSeq) return;
        setState(() {
          _hint = null;
          _lastDefaults = const {'source': 'none'};
        });
      }
    });
  }

  List<InlineSearchItem> _catalogItems() {
    return [
      for (final m in widget.catalog)
        if ((m['id']?.toString() ?? '').isNotEmpty)          InlineSearchItem(
            id: m['id'].toString(),
            label:
                (m['name'] ?? m['item_name'] ?? m['catalog_name'] ?? 'Item')
                    .toString(),
            subtitle: () {
              final s =
                  '${m['default_unit'] ?? m['purchase_unit'] ?? ''}'.trim();
              return s.isEmpty ? null : s;
            }(),
          ),
    ];
  }

  PurchaseLineDraft _buildQuickLine({
    required String catalogId,
    required String itemName,
    required double qty,
    required Map<String, dynamic> defs,
    required Map<String, dynamic>? catalogRow,
  }) {
    String? u = defs['unit']?.toString().trim().toLowerCase();
    if (u == null || u.isEmpty) {
      u = (catalogRow?['default_unit'] ?? catalogRow?['purchase_unit'])
          ?.toString()
          .trim()
          .toLowerCase();
    }
    final unit = (u == null || u.isEmpty) ? 'kg' : u;
    final rate =
        _num(defs['purchase_rate'] ?? defs['landing_cost']) ?? 0;
    final kpu = _num(defs['kg_per_unit'] ?? defs['weight_per_unit']);
    if (kpu != null && kpu > 0 && (unit == 'bag' || unit == 'sack')) {
      final rPk = rate > 0 ? rate : 0.01;
      return PurchaseLineDraft(
        catalogItemId: catalogId,
        itemName: itemName,
        qty: qty,
        unit: unit,
        landingCost: 0,
        kgPerUnit: kpu,
        landingCostPerKg: rPk,
      );
    }
    final landing = rate > 0 ? rate : 0.01;
    return PurchaseLineDraft(
      catalogItemId: catalogId,
      itemName: itemName,
      qty: qty,
      unit: unit.isEmpty ? 'kg' : unit,
      landingCost: landing,
    );
  }

  void _clearQuickPick() {
    _defsSeq++;
    _defaultsDebounced?.cancel();
    setState(() {
      _pickedCatalogId = null;
      _pickedCatalogRow = null;
      _lastDefaults = null;
      _hint = null;
      _itemCtrl.clear();
      _qtyCtrl.text = '1';
      _rateCtrl.clear();
    });
  }

  void _submitQuickLine() {
    final cid = _pickedCatalogId;
    if (cid == null || cid.isEmpty) return;
    final name = (_pickedCatalogRow?['name'] ??
            _pickedCatalogRow?['item_name'] ??
            _itemCtrl.text)
        .toString()
        .trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) return;
    final defs = _lastDefaults ?? const <String, dynamic>{'source': 'none'};
    final line =
        _buildQuickLine(catalogId: cid, itemName: name, qty: qty, defs: defs, catalogRow: _pickedCatalogRow);
    ref.read(purchaseDraftProvider.notifier).addOrReplaceLine(line);
    widget.onDraftChanged();
    _clearQuickPick();
    _itemFocus.requestFocus();
    HapticFeedback.lightImpact();
  }

  void _removeAt(int i) {
    ref.read(purchaseDraftProvider.notifier).removeLineAt(i);
    widget.onDraftChanged();
    setState(() {});
  }

  Future<void> _editAdvanced(int i) async {
    await widget.openAdvancedItemEditor(editIndex: i);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(purchaseDraftProvider.select((d) => d.lines));
    final supplierId =
        ref.watch(purchaseDraftProvider.select((d) => d.supplierId));
    final blocked = supplierId == null || supplierId.isEmpty;
    final items = _catalogItems();

    Widget quickForm = IgnorePointer(
      ignoring: blocked,
      child: Opacity(
        opacity: blocked ? 0.45 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Quick add',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            PartyInlineSuggestField(
              controller: _itemCtrl,
              focusNode: _itemFocus,
              hintText: 'Search catalog item…',
              prefixIcon: const Icon(Icons.inventory_2_outlined),
              minQueryLength: 1,
              maxMatches: 12,
              dense: true,
              textInputAction: TextInputAction.next,
              onSubmitted: () => FocusScope.of(context).nextFocus(),
              items: items,
              showAddRow: false,
              onSelected: (it) {
                if (it.id.isEmpty) return;
                setState(() {
                  _pickedCatalogId = it.id;
                  _itemCtrl.text = it.label;
                });
                unawaited(_scheduleDefaultsFetch(it.id));
              },
            ),
            if (_hint != null) ...[
              const SizedBox(height: 8),
              Text(
                _hint!,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Colors.grey[800]),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Rate (₹)',
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: (_pickedCatalogId != null &&
                      !_pickedCatalogId!.isEmpty &&
                      !blocked)
                  ? _submitQuickLine
                  : null,
              child: const Text('Add item'),
            ),
            const Divider(height: 24),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Pick a supplier on the previous step to add catalog lines.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
                fontSize: 13,
              ),
            ),
          ),
        quickForm,
        Row(
          children: [
            Text(
              'Items (${lines.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: blocked ? null : () => _clearQuickPick(),
              child: const Text('Reset row'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (lines.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  blocked
                      ? 'Supplier required for catalog links.'
                      : 'Add rows above or open Advanced.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: lines.length,
              itemBuilder: (ctx, i) {
                final ln = lines[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    title: Text(
                      ln.itemName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${StrictDecimal.fromObject(ln.qty).format(3, trim: true)} ${ln.unit}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Advanced',
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () => _editAdvanced(i),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _removeAt(i),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        OutlinedButton.icon(
          onPressed: blocked
              ? null
              : () => widget.openAdvancedItemEditor(),
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Advanced add / edit…'),
        ),
      ],
    );
  }
}
