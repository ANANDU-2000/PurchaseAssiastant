import 'package:flutter/material.dart';

import '../../../../core/calc_engine.dart';
import '../../../../core/purchase_unit_warning.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/inline_search_field.dart';

/// Bottom sheet for one purchase line — catalog search, qty/unit, landing cost, tax/discount, optional selling + profit.
class PurchaseItemEntrySheet extends StatefulWidget {
  const PurchaseItemEntrySheet({
    super.key,
    required this.catalog,
    this.initial,
    required this.isEdit,
    required this.onCommitted,
  });

  final List<Map<String, dynamic>> catalog;
  final Map<String, dynamic>? initial;
  final bool isEdit;
  final void Function(Map<String, dynamic> line) onCommitted;

  @override
  State<PurchaseItemEntrySheet> createState() => _PurchaseItemEntrySheetState();
}

class _PurchaseItemEntrySheetState extends State<PurchaseItemEntrySheet> {
  final _scrollController = ScrollController();
  final _itemKey = GlobalKey();
  final _qtyKey = GlobalKey();
  final _unitKey = GlobalKey();
  final _landingKey = GlobalKey();

  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'kg');
  final _rateCtrl = TextEditingController();
  final _discCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();

  String? _catalogItemId;

  String? _errItem;
  String? _errQty;
  String? _errUnit;
  String? _errLanding;

  void _onItemTextChanged() {
    if (_errItem != null && mounted) setState(() => _errItem = null);
  }

  @override
  void initState() {
    super.initState();
    _itemCtrl.addListener(_onItemTextChanged);
    final init = widget.initial;
    if (init != null) {
      _itemCtrl.text = init['item_name']?.toString() ?? '';
      _catalogItemId = init['catalog_item_id']?.toString();
      final q = init['qty'];
      _qtyCtrl.text = q is num && q == q.roundToDouble() ? q.round().toString() : '${q ?? ''}';
      _unitCtrl.text = init['unit']?.toString() ?? 'kg';
      final r = init['landing_cost'];
      _rateCtrl.text = r is num && r > 0 ? r.toString() : '';
      final d = init['discount'];
      _discCtrl.text = d is num && d > 0 ? d.toString() : '';
      final t = init['tax_percent'];
      _taxCtrl.text = t is num && t > 0 ? t.toString() : '';
      final s = init['selling_cost'];
      _sellingCtrl.text = s is num && s > 0 ? s.toString() : '';
    }
  }

  @override
  void dispose() {
    _itemCtrl.removeListener(_onItemTextChanged);
    _scrollController.dispose();
    _itemCtrl.dispose();
    _itemFocus.dispose();
    _qtyFocus.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _rateCtrl.dispose();
    _discCtrl.dispose();
    _taxCtrl.dispose();
    _sellingCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _catalogRowById(String id) {
    for (final m in widget.catalog) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  InputDecoration _deco(
    String label, {
    String? prefixText,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      errorText: errorText,
      errorMaxLines: 2,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: HexaColors.brandPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red[700]!, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red[700]!, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );
  }

  double? _parseD(String s) => double.tryParse(s.trim());

  TradeCalcLine _currentLine() {
    final qty = _parseD(_qtyCtrl.text) ?? 0;
    final rate = _parseD(_rateCtrl.text) ?? 0;
    final disc = _parseD(_discCtrl.text);
    final tax = _parseD(_taxCtrl.text);
    return TradeCalcLine(
      qty: qty,
      landingCost: rate,
      discountPercent: disc,
      taxPercent: tax,
    );
  }

  /// Gross qty × rate (before line discount).
  double _landingGrossTotal() {
    final li = _currentLine();
    return li.qty * li.landingCost;
  }

  /// Net stock value after line discount, before tax (matches engine mid-step).
  double _landingNetExTax() {
    final li = _currentLine();
    final base = li.qty * li.landingCost;
    final ld = li.discountPercent != null ? li.discountPercent! : 0.0;
    final d = ld > 100 ? 100.0 : ld;
    return base * (1.0 - d / 100.0);
  }

  double _lineTotalPreview() => lineMoney(_currentLine());

  double _profitPreview() {
    final sell = _parseD(_sellingCtrl.text);
    if (sell == null || sell <= 0) return 0;
    final rate = _parseD(_rateCtrl.text) ?? 0;
    final qty = _parseD(_qtyCtrl.text) ?? 0;
    return (sell - rate) * qty;
  }

  void _clearFieldErrors() {
    setState(() {
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
    });
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: Duration.zero,
        curve: Curves.linear,
      );
    });
  }

  Map<String, dynamic>? _validateAndBuildLine() {
    final name = _itemCtrl.text.trim();
    final qty = _parseD(_qtyCtrl.text) ?? 0;
    final unit = _unitCtrl.text.trim();
    final rate = _parseD(_rateCtrl.text) ?? 0;

    setState(() {
      _errItem = name.isEmpty ? 'Required' : null;
      _errQty = qty <= 0 ? 'Must be > 0' : null;
      _errUnit = unit.isEmpty ? 'Required' : null;
      _errLanding = rate <= 0 ? 'Must be > 0' : null;
    });

    if (_errItem != null) {
      _scrollToKey(_itemKey);
      return null;
    }
    if (_errQty != null) {
      _scrollToKey(_qtyKey);
      return null;
    }
    if (_errUnit != null) {
      _scrollToKey(_unitKey);
      return null;
    }
    if (_errLanding != null) {
      _scrollToKey(_landingKey);
      return null;
    }

    final disc = _parseD(_discCtrl.text);
    final tax = _parseD(_taxCtrl.text);
    final sell = _parseD(_sellingCtrl.text);

    return <String, dynamic>{
      if (_catalogItemId != null && _catalogItemId!.isNotEmpty) 'catalog_item_id': _catalogItemId,
      'item_name': name,
      'qty': qty,
      'unit': unit,
      'landing_cost': rate,
      if (disc != null && disc > 0) 'discount': disc,
      if (tax != null && tax > 0) 'tax_percent': tax,
      if (sell != null && sell > 0) 'selling_cost': sell,
    };
  }

  void _resetAfterAdd() {
    setState(() {
      _itemCtrl.clear();
      _catalogItemId = null;
      _qtyCtrl.text = '1';
      _unitCtrl.text = 'kg';
      _rateCtrl.clear();
      _discCtrl.clear();
      _taxCtrl.clear();
      _sellingCtrl.clear();
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _itemFocus.requestFocus();
    });
  }

  void _commit({required bool closeSheet}) {
    final line = _validateAndBuildLine();
    if (line == null) return;
    widget.onCommitted(line);
    if (closeSheet) {
      Navigator.of(context).pop();
    } else {
      _resetAfterAdd();
    }
  }

  Widget _liveTotalsCard(ThemeData theme) {
    final rate = _parseD(_rateCtrl.text) ?? 0;
    final gross = _landingGrossTotal();
    final netExTax = _landingNetExTax();
    final profit = _profitPreview();
    final sell = _parseD(_sellingCtrl.text);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live amounts',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Landing (per unit): ₹${rate.toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'Landing total (qty × landing cost): ₹${gross.toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey[800]),
          ),
          const SizedBox(height: 2),
          Text(
            'After line discount (ex. tax): ₹${netExTax.toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey[800]),
          ),
          const SizedBox(height: 2),
          Text(
            'Tax on line: ₹${(_lineTotalPreview() - netExTax).clamp(0.0, double.infinity).toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey[800]),
          ),
          const SizedBox(height: 2),
          Text(
            'Final line total: ₹${_lineTotalPreview().toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.green[800],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sell != null && sell > 0
                ? 'Profit (qty × (selling − landing)): ₹${profit.toStringAsFixed(0)}'
                : 'Profit: — (optional selling price)',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.blueGrey[900],
            ),
          ),
        ],
      ),
    );
  }

  String? get _unitWarning {
    if (_catalogItemId == null || _catalogItemId!.isEmpty) return null;
    return purchaseUnitMismatchWarning(
      catalogRow: _catalogRowById(_catalogItemId!),
      unitText: _unitCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchItems = <InlineSearchItem>[
      for (final row in widget.catalog)
        InlineSearchItem(
          id: row['id']?.toString() ?? '',
          label: row['name']?.toString() ?? '',
          subtitle: row['default_unit']?.toString(),
        ),
    ];

    return Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.isEdit ? 'Edit line' : 'Add item',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Item',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              KeyedSubtree(
                key: _itemKey,
                child: InlineSearchField(
                  controller: _itemCtrl,
                  focusNode: _itemFocus,
                  placeholder: 'Type at least 2 characters to search…',
                  prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
                  items: searchItems,
                  minQueryLength: 2,
                  focusAfterSelection: _qtyFocus,
                  onSelected: (it) {
                    if (it.id.isEmpty) {
                      setState(() {
                        _catalogItemId = null;
                        _errItem = null;
                      });
                      return;
                    }
                    final row = _catalogRowById(it.id);
                    setState(() {
                      _catalogItemId = it.id;
                      _itemCtrl.text = it.label;
                      _unitCtrl.text = row?['default_purchase_unit']?.toString() ??
                          row?['default_unit']?.toString() ??
                          'kg';
                      var rate = 0.0;
                      final lp = row?['default_landing_cost'];
                      if (lp is num && lp > 0) rate = lp.toDouble();
                      _rateCtrl.text = rate > 0 ? rate.toString() : '';
                      final tax = row?['tax_percent'];
                      _taxCtrl.text = tax is num && tax > 0 ? tax.toString() : '';
                      _errItem = null;
                    });
                  },
                ),
              ),
              if (_errItem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(_errItem!, style: TextStyle(color: Colors.red[800], fontSize: 12)),
                ),
              const SizedBox(height: 8),
              KeyedSubtree(
                key: _qtyKey,
                child: TextField(
                  controller: _qtyCtrl,
                  focusNode: _qtyFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco('Qty *', errorText: _errQty),
                  onChanged: (_) {
                    _clearFieldErrors();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 8),
              KeyedSubtree(
                key: _unitKey,
                child: TextField(
                  controller: _unitCtrl,
                  decoration: _deco('Unit *', errorText: _errUnit),
                  onChanged: (_) {
                    _clearFieldErrors();
                    setState(() {});
                  },
                ),
              ),
              if (_unitWarning != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Text(
                    _unitWarning!,
                    style: TextStyle(
                      color: Colors.amber[900],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              KeyedSubtree(
                key: _landingKey,
                child: TextField(
                  controller: _rateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco('Landing cost (per unit) *', prefixText: '₹ ', errorText: _errLanding),
                  onChanged: (_) {
                    _clearFieldErrors();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Discount, tax & selling',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tax % can be prefilled from catalog; selling price is optional (profit).',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _discCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _deco('Discount %'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _taxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _deco('Tax % (from HSN)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sellingCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _deco('Selling price (per unit, optional)', prefixText: '₹ '),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _liveTotalsCard(theme),
              const SizedBox(height: 14),
              if (widget.isEdit)
                FilledButton(
                  onPressed: () => _commit(closeSheet: true),
                  child: const Text('SAVE LINE'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _commit(closeSheet: false),
                        child: const Text('ADD MORE'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _commit(closeSheet: true),
                        child: const Text('DONE'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
    );
  }
}
