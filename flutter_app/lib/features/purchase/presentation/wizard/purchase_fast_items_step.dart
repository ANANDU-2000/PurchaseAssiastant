import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strict_decimal.dart';
import '../../../../core/theme/hexa_colors.dart';
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
      PurchaseFastItemsStepState();
}

/// Public state for wizard footer callbacks (reset quick-add form).
class PurchaseFastItemsStepState extends ConsumerState<PurchaseFastItemsStep> {
  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rateCtrl = TextEditingController();
  final _sellCtrl = TextEditingController();

  /// Quick-add UI unit (landing line); kg/bag/box/tin.
  String _quickUnit = 'kg';

  String? _pickedCatalogId;
  Map<String, dynamic>? _pickedCatalogRow;
  Map<String, dynamic>? _lastDefaults;
  String? _hint;
  Timer? _defaultsDebounced;

  int _defsSeq = 0;
  bool _showMoreQuickOptions = false;

  @override
  void dispose() {
    _defaultsDebounced?.cancel();
    _itemCtrl.dispose();
    _itemFocus.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    _sellCtrl.dispose();
    super.dispose();
  }

  static double? _num(Object? x) {
    if (x is num) return x.toDouble();
    return null;
  }

  Future<void> _resolveTradeDefaults(String catalogId) async {
    if (widget.businessIdOrNull == null ||
        catalogId.isEmpty ||
        widget.catalog.isEmpty) {
      if (mounted) {
        setState(() {
          _lastDefaults = null;
          _hint = null;
        });
      }
      return;
    }
    final seq = ++_defsSeq;
    try {
      Map<String, dynamic>? catalogRowLocal;
      for (final m in widget.catalog) {
        if (m['id']?.toString() == catalogId) {
          catalogRowLocal = Map<String, dynamic>.from(m);
          break;
        }
      }

      var fetchedRow = catalogRowLocal ?? <String, dynamic>{};
      if (fetchedRow.isEmpty) {
        final fetched = await widget.resolveCatalogItemRow(catalogId);
        if (fetched.isNotEmpty) {
          fetchedRow = Map<String, dynamic>.from(fetched);
        }
      }
      if (!mounted || seq != _defsSeq) return;

      final def = Map<String, dynamic>.from(
        await widget.resolveLastTradeDefaults(catalogId),
      );
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

        final dateHint = def['purchase_date']?.toString().split('T').first;

        final supHint =
            unit != null && unit.isNotEmpty ? ' • defaults used $unit' : '';

        _lastDefaults = def;
        if (rate != null && rate > 0) {
          _rateCtrl.text =
              StrictDecimal.fromObject(rate).format(3, trim: true);
        }
        final sell = _num(def['selling_rate'] ?? def['selling_cost']);
        final sellManual = _sellCtrl.text.trim().isNotEmpty;
        if (!sellManual && sell != null && sell > 0) {
          _sellCtrl.text =
              StrictDecimal.fromObject(sell).format(2, trim: true);
        }
        if (src != null && src != 'none') {
          _hint =
              '${displayName.isNotEmpty ? displayName + ' · ' : ''}Last trade: $src${dateHint != null ? ' ($dateHint)' : ''}$supHint';
        } else {
          _hint =
              '${displayName.isNotEmpty ? displayName + ' — ' : ''}No prior defaults for this party + item.';
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
  }

  /// Immediate defaults on catalog pick plus a trailing refresh for churned context.
  void _kickTradeDefaultsResolution(String catalogId) {
    _defaultsDebounced?.cancel();
    if (catalogId.isEmpty) return;
    unawaited(_resolveTradeDefaults(catalogId));
    _defaultsDebounced = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _pickedCatalogId != catalogId) return;
      unawaited(_resolveTradeDefaults(catalogId));
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
    double? sellingOverride,
  }) {
    String? u = defs['unit']?.toString().trim().toLowerCase();
    if (u == null || u.isEmpty) {
      u = (catalogRow?['default_unit'] ?? catalogRow?['purchase_unit'])
          ?.toString()
          .trim()
          .toLowerCase();
    }
    final unit = (_quickUnit.trim().toLowerCase().isNotEmpty)
        ? _quickUnit.trim().toLowerCase()
        : ((u == null || u.isEmpty) ? 'kg' : u);
    final rate =
        _num(defs['purchase_rate'] ?? defs['landing_cost']) ?? 0;
    double? selling = sellingOverride;
    if (selling == null) {
      selling = _num(defs['selling_rate'] ?? defs['selling_cost']);
      if (selling != null && selling <= 0) selling = null;
    }

    double? resolvedSelling() =>
        selling != null && selling > 0 ? selling : null;

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
        sellingPrice: resolvedSelling(),
      );
    }
    final landing = rate > 0 ? rate : 0.01;
    return PurchaseLineDraft(
      catalogItemId: catalogId,
      itemName: itemName,
      qty: qty,
      unit: unit.isEmpty ? 'kg' : unit,
      landingCost: landing,
      sellingPrice: resolvedSelling(),
    );
  }

  double? _parseSellingForSubmit(Map<String, dynamic> defs) {
    final st = _sellCtrl.text.trim();
    if (st.isNotEmpty) {
      final v = double.tryParse(st);
      if (v != null && v > 0) return v;
      return null;
    }
    final s = _num(defs['selling_rate'] ?? defs['selling_cost']);
    if (s != null && s > 0) return s;
    return null;
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
      _sellCtrl.clear();
      _quickUnit = 'kg';
      _showMoreQuickOptions = false;
    });
  }

  Future<void> _pickQuickUnit(BuildContext context) async {
    const opts = ['kg', 'bag', 'box', 'tin'];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Unit',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              for (final o in opts)
                ListTile(
                  title: Text(o),
                  trailing: _quickUnit == o
                      ? Icon(Icons.check, color: HexaColors.brandPrimary)
                      : null,
                  onTap: () => Navigator.pop(ctx, o),
                ),
            ],
          ),
        );
      },
    );
    if (choice != null && mounted) {
      setState(() => _quickUnit = choice);
    }
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
    final sellOv = _parseSellingForSubmit(defs);
    final line = _buildQuickLine(
      catalogId: cid,
      itemName: name,
      qty: qty,
      defs: defs,
      catalogRow: _pickedCatalogRow,
      sellingOverride: sellOv,
    );
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

  /// Called from wizard footer "Add more items" — clears quick row only.
  void resetQuickAddRow() {
    FocusScope.of(context).unfocus();
    _clearQuickPick();
    Future.microtask(() {
      if (mounted) _itemFocus.requestFocus();
    });
  }

  double _approxLinePurchase(PurchaseLineDraft l) {
    final kpu = l.kgPerUnit;
    final pk = l.landingCostPerKg;
    if (kpu != null && pk != null && kpu > 0 && pk > 0) {
      return l.qty * kpu * pk;
    }
    return l.qty * l.landingCost;
  }

  double? _approxLineSell(PurchaseLineDraft l) {
    final sp = l.sellingPrice;
    if (sp == null || sp <= 0) return null;
    return sp * l.qty;
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
              fieldBorderRadius: 12,
              minFieldHeight: 52,
              idleOutlineColor: Colors.grey.shade200,
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
                _kickTradeDefaultsResolution(it.id);
              },
            ),
            if (_hint != null) ...[
              const SizedBox(height: 6),
              Text(
                _hint!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: HexaColors.brandAccent,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: OutlinedButton(
                    onPressed: blocked ? null : () => _pickQuickUnit(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(_quickUnit.toUpperCase()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Purchase (₹)',
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _sellCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Selling (₹)',
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'More options',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                initiallyExpanded: _showMoreQuickOptions,
                onExpansionChanged: (o) =>
                    setState(() => _showMoreQuickOptions = o),
                children: [
                  Text(
                    'Box or tin packing needs weights in Advanced.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: blocked
                          ? null
                          : () => widget.openAdvancedItemEditor(),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open advanced line editor'),
                    ),
                  ),
                ],
              ),
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
                final buy = _approxLinePurchase(ln);
                final sellTot = _approxLineSell(ln);
                final subtitle = sellTot != null
                    ? '${StrictDecimal.fromObject(ln.qty).format(3, trim: true)} ${ln.unit} · est. buy ₹${buy.toStringAsFixed(2)} · est. sell ₹${sellTot.toStringAsFixed(2)}'
                    : '${StrictDecimal.fromObject(ln.qty).format(3, trim: true)} ${ln.unit} · est. buy ₹${buy.toStringAsFixed(2)}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          HexaColors.brandPrimary.withValues(alpha: 0.1),
                      foregroundColor: HexaColors.brandPrimary,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(
                      ln.itemName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(subtitle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
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
        if (lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Consumer(
              builder: (cx, rf, _) {
                final bd = rf.watch(purchaseStrictBreakdownProvider);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFEFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: HexaColors.brandPrimary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Goods approx',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '₹${bd.subtotalGross.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Est. payable',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '₹${bd.grand.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: HexaColors.brandPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
