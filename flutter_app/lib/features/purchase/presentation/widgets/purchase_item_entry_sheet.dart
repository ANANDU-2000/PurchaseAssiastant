import 'package:flutter/material.dart';

import '../../../../core/calc_engine.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/inline_search_field.dart';

/// One purchase line: catalog search, qty/unit, landing, selling, optional
/// tax/discount (per kg for bag/sack with a catalog kg snapshot, else per unit).
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
  final _sellingKey = GlobalKey();
  final _kgPerBagKey = GlobalKey();

  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'kg');
  final _landingCtrl = TextEditingController();
  final _discCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();
  /// Manual kg per bag (when no catalog row or catalog row has no default_kg_per_bag).
  final _kgPerBagCtrl = TextEditingController();

  String? _catalogItemId;
  /// When true: bag/sack with kg snapshot — user enters landing & selling per kg.
  bool _weightPricing = false;
  /// kg per bag/sack (from `default_kg_per_bag` or saved line).
  double? _kgPerUnit;

  String? _errItem;
  String? _errQty;
  String? _errUnit;
  String? _errLanding;
  String? _errSelling;
  String? _errKgPerBag;

  void _onItemTextChanged() {
    if (!mounted) return;
    // If the user edits the typed label away from the selected catalog row,
    // unlink automatically so we don't persist a stale `catalog_item_id`.
    // Without this, selecting "Rice" then typing "Rice123" would silently save
    // the line against the Rice catalog id.
    if (_catalogItemId != null && _catalogItemId!.isNotEmpty) {
      final row = _catalogRowById(_catalogItemId!);
      final selectedLabel = (row?['name']?.toString() ?? '').trim();
      if (_itemCtrl.text.trim() != selectedLabel) {
        setState(() {
          _catalogItemId = null;
          _errItem = null;
        });
        return;
      }
    }
    if (_errItem != null) setState(() => _errItem = null);
  }

  void _onKgPerBagChanged() {
    final v = _parseD(_kgPerBagCtrl.text);
    if (!mounted) return;
    setState(() {
      _kgPerUnit = (v != null && v > 0) ? v : null;
      _weightPricing = _kgPerUnit != null && _kgPerUnit! > 0;
      if (_errKgPerBag != null) _errKgPerBag = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _itemCtrl.addListener(_onItemTextChanged);
    _kgPerBagCtrl.addListener(_onKgPerBagChanged);
    final init = widget.initial;
    if (init != null) {
      _itemCtrl.text = init['item_name']?.toString() ?? '';
      _catalogItemId = init['catalog_item_id']?.toString();
      final q = init['qty'];
      _qtyCtrl.text = q is num && q == q.roundToDouble() ? q.round().toString() : '${q ?? ''}';
      _unitCtrl.text = init['unit']?.toString() ?? 'kg';

      final kpu = (init['kg_per_unit'] as num?)?.toDouble();
      final lck = (init['landing_cost_per_kg'] as num?)?.toDouble();
      if (kpu != null && kpu > 0) {
        _weightPricing = true;
        _kgPerUnit = kpu;
        _kgPerBagCtrl.text = _fmtQty(kpu);
        if (lck != null && lck > 0) {
          _landingCtrl.text = lck.toString();
        } else {
          final lc = (init['landing_cost'] as num?)?.toDouble();
          if (lc != null && lc > 0) {
            _landingCtrl.text = (lc / kpu).toString();
          } else {
            _landingCtrl.text = '';
          }
        }
        final sc = init['selling_cost'];
        if (sc is num) {
          _sellingCtrl.text = (sc.toDouble() / kpu).toStringAsFixed(2);
        } else {
          _sellingCtrl.text = '';
        }
      } else {
        _weightPricing = false;
        _kgPerUnit = null;
        final r = init['landing_cost'];
        _landingCtrl.text = r is num && r > 0 ? r.toString() : '';
        final s = init['selling_cost'];
        if (s is num) {
          _sellingCtrl.text = s.toString();
        } else {
          _sellingCtrl.text = '';
        }
      }

      final d = init['discount'];
      _discCtrl.text = d is num && d > 0 ? d.toString() : '';
      final t = init['tax_percent'];
      _taxCtrl.text = t is num && t > 0 ? t.toString() : '';
    }
    _syncKgStateFromCatalogRow();
  }

  void _syncKgStateFromCatalogRow() {
    if (_catalogItemId == null || _catalogItemId!.isEmpty) return;
    if (_kgPerUnit != null && _kgPerUnit! > 0) return;
    final r = _catalogRowById(_catalogItemId!);
    if (r == null) return;
    for (final key in <String>['default_kg_per_bag', 'kg_per_bag', 'kg_per_unit']) {
      final v = r[key];
      if (v is num && v > 0) {
        _kgPerUnit = v.toDouble();
        _weightPricing = true;
        return;
      }
    }
  }

  @override
  void dispose() {
    _itemCtrl.removeListener(_onItemTextChanged);
    _kgPerBagCtrl.removeListener(_onKgPerBagChanged);
    _scrollController.dispose();
    _itemCtrl.dispose();
    _itemFocus.dispose();
    _qtyFocus.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _landingCtrl.dispose();
    _discCtrl.dispose();
    _taxCtrl.dispose();
    _sellingCtrl.dispose();
    _kgPerBagCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _catalogRowById(String id) {
    for (final m in widget.catalog) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  static bool _isWeightUnit(String? u) {
    final x = (u ?? '').trim().toLowerCase();
    return x == 'bag' || x == 'sack';
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: HexaColors.brandPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.red[700]!, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.red[700]!, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }

  double? _parseD(String s) => double.tryParse(s.trim());

  double _qtyVal() => _parseD(_qtyCtrl.text) ?? 0;

  String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();

  /// kg/bag resolved to a number; single source of truth = `_kgPerUnit` (seeded
  /// from catalog row on pick OR from the manual "Kg per bag" input).
  double? _kgPer() =>
      (_kgPerUnit != null && _kgPerUnit! > 0) ? _kgPerUnit : null;

  /// Catalog item selected AND catalog row carries kg/bag.
  bool _hasCatalogKg() {
    final id = _catalogItemId;
    if (id == null || id.isEmpty) return false;
    final r = _catalogRowById(id);
    if (r == null) return false;
    for (final key in <String>['default_kg_per_bag', 'kg_per_bag', 'kg_per_unit']) {
      final v = r[key];
      if (v is num && v > 0) return true;
    }
    return false;
  }

  /// Weight pricing = unit is bag/sack OR a kg/bag is resolved. This flips the
  /// whole UI to ₹/kg — even before the user has entered kg in manual flow.
  bool get _isWeightMode =>
      _isWeightUnit(_unitCtrl.text) || (_kgPer() != null && _kgPer()! > 0);

  /// Kept for code paths that need "ready to calculate" (have a kg number).
  bool get _isWeightItemLine {
    final k = _kgPer();
    return k != null && k > 0;
  }

  double _totalKg() {
    if (!_isWeightItemLine) return 0;
    final k = _kgPer()!;
    return _qtyVal() * k;
  }

  TradeCalcLine _currentLine() {
    final qty = _qtyVal();
    final disc = _parseD(_discCtrl.text);
    final tax = _parseD(_taxCtrl.text);
    if (_isWeightItemLine) {
      final kpu = _kgPer()!;
      final perKg = _parseD(_landingCtrl.text) ?? 0;
      return TradeCalcLine(
        qty: qty,
        landingCost: kpu * perKg,
        kgPerUnit: kpu,
        landingCostPerKg: perKg,
        discountPercent: disc,
        taxPercent: tax,
      );
    }
    return TradeCalcLine(
      qty: qty,
      landingCost: _parseD(_landingCtrl.text) ?? 0,
      discountPercent: disc,
      taxPercent: tax,
    );
  }

  double _lineTotalPreview() => lineMoney(_currentLine());

  double _profitPreview() {
    final sell = _parseD(_sellingCtrl.text);
    if (sell == null) return 0;
    if (_isWeightItemLine) {
      final k = _kgPer()!;
      final perKgLand = _parseD(_landingCtrl.text) ?? 0;
      final totalK = _qtyVal() * k;
      return (sell - perKgLand) * totalK;
    }
    final rate = _parseD(_landingCtrl.text) ?? 0;
    return (sell - rate) * _qtyVal();
  }

  void _clearFieldErrors() {
    setState(() {
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
      _errSelling = null;
      _errKgPerBag = null;
    });
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: Duration.zero,
        curve: Curves.linear,
      );
    });
  }

  /// Selling stored per line unit on the wire; weight mode: multiply per-kg × kg_per_unit.
  /// Call only after validation; [sell] must be non-null and >= 0.
  double _sellingForPayloadForWire(double sell) {
    if (_isWeightItemLine) {
      final k = _kgPer()!;
      return sell * k;
    }
    return sell;
  }

  Map<String, dynamic>? _validateAndBuildLine() {
    final name = _itemCtrl.text.trim();
    final qty = _qtyVal();
    final unit = _unitCtrl.text.trim();
    final rate = _parseD(_landingCtrl.text) ?? 0;

    final catalogId = _catalogItemId;
    setState(() {
      if (name.isEmpty) {
        _errItem = 'Required';
      } else if (catalogId == null || catalogId.isEmpty) {
        _errItem = 'Pick item from list';
      } else {
        _errItem = null;
      }
      _errQty = qty <= 0 ? 'Must be > 0' : null;
      _errUnit = unit.isEmpty ? 'Required' : null;
      if (_isWeightMode) {
        final k = _kgPer();
        _errKgPerBag = (k == null || k <= 0) ? 'Must be > 0' : null;
      } else {
        _errKgPerBag = null;
      }
      if (_isWeightItemLine) {
        _errLanding = rate <= 0 ? '₹/kg must be > 0' : null;
      } else {
        _errLanding = rate <= 0 ? 'Must be > 0' : null;
      }
      final sellT = _sellingCtrl.text.trim();
      if (sellT.isEmpty) {
        _errSelling = null;
      } else {
        final sv = _parseD(sellT);
        if (sv == null) {
          _errSelling = 'Invalid';
        } else if (sv < 0) {
          _errSelling = 'Min 0';
        } else {
          _errSelling = null;
        }
      }
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
    if (_errKgPerBag != null) {
      _scrollToKey(_kgPerBagKey);
      return null;
    }
    if (_errLanding != null) {
      _scrollToKey(_landingKey);
      return null;
    }
    if (_errSelling != null) {
      _scrollToKey(_sellingKey);
      return null;
    }

    final disc = _parseD(_discCtrl.text);
    final tax = _parseD(_taxCtrl.text);
    final sellSt = _sellingCtrl.text.trim();

    final m = <String, dynamic>{
      if (_catalogItemId != null && _catalogItemId!.isNotEmpty) 'catalog_item_id': _catalogItemId,
      'item_name': name,
      'qty': qty,
      'unit': unit,
    };

    if (_isWeightItemLine) {
      final kpu = _kgPer()!;
      m['kg_per_unit'] = kpu;
      m['landing_cost_per_kg'] = rate;
      m['landing_cost'] = kpu * rate;
    } else {
      m['landing_cost'] = rate;
    }
    if (disc != null && disc > 0) m['discount'] = disc;
    if (tax != null && tax > 0) m['tax_percent'] = tax;
    if (sellSt.isNotEmpty) {
      m['selling_cost'] = _sellingForPayloadForWire(_parseD(sellSt)!);
    }
    return m;
  }

  void _resetAfterAdd() {
    setState(() {
      _itemCtrl.clear();
      _catalogItemId = null;
      _weightPricing = false;
      _kgPerUnit = null;
      _qtyCtrl.text = '1';
      _unitCtrl.text = 'kg';
      _landingCtrl.clear();
      _discCtrl.clear();
      _taxCtrl.clear();
      _sellingCtrl.clear();
      _kgPerBagCtrl.clear();
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
      _errSelling = null;
      _errKgPerBag = null;
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

  /// Picks line unit: when the item has a bag weight but purchase unit is
  /// `kg` in the catalog, prefer the physical [default_unit] (bag) so
  /// per-kg × kg/bag math applies.
  String _lineUnitForCatalog(
    Map<String, dynamic> row, {
    required double? kpbD,
  }) {
    final dpu = row['default_purchase_unit']?.toString().trim();
    final du = row['default_unit']?.toString().trim();
    if (kpbD != null && kpbD > 0) {
      if (du != null && _isWeightUnit(du) && (dpu == null || dpu.toLowerCase() == 'kg')) {
        return du;
      }
    }
    if (dpu != null && dpu.isNotEmpty) return dpu;
    if (du != null && du.isNotEmpty) return du;
    return 'kg';
  }

  void _recomputeModeFromUnitAndCatalog() {
    if (_catalogItemId == null || _catalogItemId!.isEmpty) return;
    final row = _catalogRowById(_catalogItemId!);
    if (row == null) return;
    final kpb = row['default_kg_per_bag'];
    final kpbD = kpb is num && kpb > 0 ? kpb.toDouble() : null;
    if (kpbD == null) {
      if (_kgPerUnit != null && _hasCatalogKg() == false) {
        setState(() {
          _weightPricing = false;
          _kgPerUnit = null;
          _kgPerBagCtrl.clear();
        });
      }
      return;
    }
    if (_kgPerUnit != kpbD || !_weightPricing) {
      setState(() {
        _weightPricing = true;
        _kgPerUnit = kpbD;
        _kgPerBagCtrl.text = _fmtQty(kpbD);
      });
    }
  }

  void _onCatalogPick(InlineSearchItem it) {
    if (it.id.isEmpty) {
      setState(() {
        _catalogItemId = null;
        _weightPricing = false;
        _kgPerUnit = null;
        _kgPerBagCtrl.clear();
        _errItem = null;
      });
      return;
    }
    final row = _catalogRowById(it.id);
    if (row == null) {
      setState(() {
        _catalogItemId = it.id;
        _itemCtrl.text = it.label;
        _errItem = null;
      });
      return;
    }
    final kpb = row['default_kg_per_bag'];
    final kpbD = kpb is num && kpb > 0 ? kpb.toDouble() : null;
    final unit0 = _lineUnitForCatalog(row, kpbD: kpbD);
    setState(() {
      _catalogItemId = it.id;
      _itemCtrl.text = it.label;
      _unitCtrl.text = unit0;
      if (kpbD != null && kpbD > 0) {
        _weightPricing = true;
        _kgPerUnit = kpbD;
        _kgPerBagCtrl.text = _fmtQty(kpbD);
        var perKg = 0.0;
        final lp = row['default_landing_cost'];
        if (lp is num && lp > 0) {
          perKg = lp.toDouble() / kpbD;
        }
        _landingCtrl.text = perKg > 0 ? perKg.toString() : '';
        final sc = row['default_selling_cost'];
        if (sc is num) {
          _sellingCtrl.text = (sc.toDouble() / kpbD).toString();
        } else {
          _sellingCtrl.clear();
        }
      } else {
        _weightPricing = false;
        _kgPerUnit = null;
        _kgPerBagCtrl.clear();
        var rate = 0.0;
        final lp = row['default_landing_cost'];
        if (lp is num && lp > 0) rate = lp.toDouble();
        _landingCtrl.text = rate > 0 ? rate.toString() : '';
        final sc2 = row['default_selling_cost'];
        if (sc2 is num) {
          _sellingCtrl.text = sc2.toString();
        } else {
          _sellingCtrl.clear();
        }
      }
      final tax = row['tax_percent'];
      _taxCtrl.text = tax is num && tax > 0 ? tax.toString() : '';
      _errItem = null;
    });
  }

  /// Line total + profit: weight lines show "qty × kgkg = total_kg" and ₹/kg → ₹total.
  Widget _liveTotalsCard(ThemeData theme) {
    final total = _lineTotalPreview();
    final sell = _parseD(_sellingCtrl.text);
    final profit = _profitPreview();
    final k = _kgPer();
    final q = _qtyVal();
    final u = _unitCtrl.text.trim();
    final unitLabel = u.isEmpty ? 'units' : u;
    final per = _parseD(_landingCtrl.text) ?? 0;

    final lines = <Widget>[];

    if (_isWeightMode) {
      if (k != null && q > 0) {
        lines.add(Text(
          '${_fmtQty(q)} × ${_fmtQty(k)}kg = ${_fmtQty(_totalKg())} kg',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ));
        lines.add(const SizedBox(height: 2));
        lines.add(Text(
          '₹${per.toStringAsFixed(0)}/kg → ₹${total.toStringAsFixed(0)}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.blueGrey[900],
          ),
        ));
      } else {
        lines.add(Text(
          'Enter kg per bag to calculate',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[700],
          ),
        ));
      }
    } else {
      lines.add(Text(
        '${_fmtQty(q)} $unitLabel × ₹${per.toStringAsFixed(0)} = ₹${total.toStringAsFixed(0)}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ));
    }

    lines.add(const SizedBox(height: 2));
    lines.add(Text(
      sell == null ? 'Profit —' : 'Profit ₹${profit.toStringAsFixed(0)}',
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.blueGrey[900],
      ),
    ));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      ),
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
    final k = _kgPer();
    final showPerKgFields = _isWeightMode;
    final showManualKgField = _isWeightMode && !_hasCatalogKg();
    // Compact, stable fields — Tally-style density.
    final sheetTheme = theme.copyWith(visualDensity: VisualDensity.compact);

    return Theme(
      data: sheetTheme,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.isEdit ? 'Edit line' : 'Add item',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              KeyedSubtree(
                key: _itemKey,
                child: InlineSearchField(
                  controller: _itemCtrl,
                  focusNode: _itemFocus,
                  placeholder: 'Search item (2+ letters)…',
                  prefixIcon: const Icon(Icons.inventory_2_outlined, size: 18),
                  items: searchItems,
                  minQueryLength: 2,
                  focusAfterSelection: _qtyFocus,
                  onSelected: _onCatalogPick,
                ),
              ),
              if (_errItem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2),
                  child: Text(_errItem!, style: TextStyle(color: Colors.red[800], fontSize: 11)),
                ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: KeyedSubtree(
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
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 5,
                    child: KeyedSubtree(
                      key: _unitKey,
                      child: (showPerKgFields && _hasCatalogKg())
                          ? InputDecorator(
                              decoration: _deco('Unit *', errorText: _errUnit),
                              child: Text(
                                '${_unitCtrl.text.trim()} (${(k ?? 0).toStringAsFixed(0)} kg)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : TextField(
                              controller: _unitCtrl,
                              decoration: _deco('Unit *', errorText: _errUnit),
                              onChanged: (v) {
                                _clearFieldErrors();
                                if (!_isWeightUnit(v) && !_hasCatalogKg()) {
                                  _kgPerUnit = null;
                                  _kgPerBagCtrl.clear();
                                }
                                _recomputeModeFromUnitAndCatalog();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ],
              ),
              if (showManualKgField) ...[
                const SizedBox(height: 6),
                KeyedSubtree(
                  key: _kgPerBagKey,
                  child: TextField(
                    controller: _kgPerBagCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _deco('Kg per bag *', errorText: _errKgPerBag),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              KeyedSubtree(
                key: _landingKey,
                child: TextField(
                  controller: _landingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco(
                    showPerKgFields ? 'Landing cost (₹/kg) *' : 'Landing cost *',
                    prefixText: '₹ ',
                    errorText: _errLanding,
                  ),
                  onChanged: (_) {
                    _clearFieldErrors();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 6),
              KeyedSubtree(
                key: _sellingKey,
                child: TextField(
                  controller: _sellingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco(
                    showPerKgFields ? 'Selling price (₹/kg)' : 'Selling price',
                    prefixText: '₹ ',
                    errorText: _errSelling,
                  ),
                  onChanged: (_) {
                    _clearFieldErrors();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 2),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                  title: Text(
                    'Discount / Tax',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  initiallyExpanded: false,
                  expansionAnimationStyle: const AnimationStyle(
                    duration: Duration.zero,
                    curve: Curves.linear,
                    reverseCurve: Curves.linear,
                    reverseDuration: Duration.zero,
                  ),
                  children: [
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
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _taxCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: _deco('Tax %'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              _liveTotalsCard(theme),
              const SizedBox(height: 8),
              if (widget.isEdit)
                FilledButton(
                  onPressed: () => _commit(closeSheet: true),
                  child: const Text('SAVE'),
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
                    const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _commit(closeSheet: true),
                        child: const Text('SAVE'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
