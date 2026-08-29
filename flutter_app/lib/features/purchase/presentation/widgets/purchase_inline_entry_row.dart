import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/pricing/tax_mode.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../domain/purchase_draft.dart';
import 'item_entry/purchase_inline_line_builder.dart';

final _inrFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _inr0(num n) => _inrFmt.format(n);

/// Dense spreadsheet-style purchase line editor (desktop / wide tablet).
///
/// Keyboard: Item → Qty → Unit → Buy → Sell → Tax → Enter commits → next row.
/// Esc cancels. Does not own draft writes — calls [onCommit] / [onCancel].
class PurchaseInlineEntryRow extends StatefulWidget {
  const PurchaseInlineEntryRow({
    super.key,
    required this.catalog,
    required this.searchItems,
    required this.onCommit,
    required this.onCancel,
    this.onOpenAdvanced,
    this.initial,
    this.autofocusItem = true,
    this.preferredSupplierId,
  });

  final List<Map<String, dynamic>> catalog;
  final List<InlineSearchItem> searchItems;
  final void Function(Map<String, dynamic> line) onCommit;
  final VoidCallback onCancel;
  final VoidCallback? onOpenAdvanced;
  final PurchaseLineDraft? initial;
  final bool autofocusItem;
  final String? preferredSupplierId;

  @override
  State<PurchaseInlineEntryRow> createState() => _PurchaseInlineEntryRowState();
}

class _PurchaseInlineEntryRowState extends State<PurchaseInlineEntryRow> {
  late final TextEditingController _itemCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _buyCtrl;
  late final TextEditingController _sellCtrl;

  late final FocusNode _itemFocus;
  late final FocusNode _qtyFocus;
  late final FocusNode _unitFocus;
  late final FocusNode _buyFocus;
  late final FocusNode _sellFocus;
  late final FocusNode _taxFocus;

  String? _catalogItemId;
  String _unit = 'kg';
  TaxMode _taxMode = TaxMode.none;
  double _taxPercent = 0;
  String? _hsn;
  String? _itemCode;
  double? _catalogKgPerBag;
  double? _catalogTaxPercent;

  InlineLineValidation _errors = const InlineLineValidation();
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _itemCtrl = TextEditingController(text: init?.itemName ?? '');
    _qtyCtrl = TextEditingController(
      text: init != null && init.qty > 0
          ? (init.qty == init.qty.roundToDouble()
              ? '${init.qty.round()}'
              : init.qty.toString())
          : '1',
    );
    _buyCtrl = TextEditingController(
      text: init != null && init.landingCost > 0
          ? init.landingCost.toStringAsFixed(2)
          : '',
    );
    _sellCtrl = TextEditingController(
      text: init != null && (init.sellingPrice ?? 0) > 0
          ? init.sellingPrice!.toStringAsFixed(2)
          : '',
    );
    _itemFocus = FocusNode(debugLabel: 'inlineItem');
    _qtyFocus = FocusNode(debugLabel: 'inlineQty');
    _unitFocus = FocusNode(debugLabel: 'inlineUnit');
    _buyFocus = FocusNode(debugLabel: 'inlineBuy');
    _sellFocus = FocusNode(debugLabel: 'inlineSell');
    _taxFocus = FocusNode(debugLabel: 'inlineTax');

    if (init != null) {
      _catalogItemId = init.catalogItemId;
      _unit = init.unit.trim().isEmpty ? 'kg' : init.unit.trim();
      if (_unit.toLowerCase() == 'sack') _unit = 'bag';
      _hsn = init.hsnCode;
      _itemCode = init.itemCode;
      _catalogKgPerBag = init.kgPerUnit;
      final tp = init.taxPercent ?? 0;
      if (tp <= 0) {
        _taxMode = TaxMode.none;
        _taxPercent = 0;
      } else {
        _taxMode = TaxMode.exclusive;
        _taxPercent = tp;
      }
    }

    for (final c in [_qtyCtrl, _buyCtrl, _sellCtrl]) {
      c.addListener(_onFieldChanged);
    }

    if (widget.autofocusItem) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _itemFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_qtyCtrl, _buyCtrl, _sellCtrl]) {
      c.removeListener(_onFieldChanged);
    }
    _itemCtrl.dispose();
    _qtyCtrl.dispose();
    _buyCtrl.dispose();
    _sellCtrl.dispose();
    _itemFocus.dispose();
    _qtyFocus.dispose();
    _unitFocus.dispose();
    _buyFocus.dispose();
    _sellFocus.dispose();
    _taxFocus.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  InputDecoration _cellDeco({String? hint, String? errorText}) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      errorText: errorText,
      errorStyle: const TextStyle(fontSize: 9, height: 1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: HexaColors.slateBorder),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: HexaColors.brandPrimary, width: 1.5),
      ),
    );
  }

  void _applyCatalogRow(Map<String, dynamic> row, String fallbackName) {
    final name = (row['name']?.toString() ?? fallbackName).trim();
    final du = (row['default_unit']?.toString() ?? 'kg').trim();
    var unit = du.isEmpty ? 'kg' : du;
    if (unit.toLowerCase() == 'sack') unit = 'bag';

    final landing = catalogNumeric(row['default_landing_cost']);
    final selling = catalogNumeric(row['default_selling_cost']);
    final tax = catalogNumeric(row['default_tax_percent'] ?? row['tax_percent']);
    final kpb = catalogNumeric(row['default_kg_per_bag']);

    setState(() {
      _catalogItemId = row['id']?.toString();
      _itemCtrl.text = name.isNotEmpty ? name : fallbackName;
      _unit = kPurchaseInlineUnitChoices.contains(unit.toLowerCase())
          ? unit.toLowerCase()
          : unit;
      _hsn = (row['hsn_code'] ?? row['hsn'])?.toString();
      _itemCode = row['item_code']?.toString();
      _catalogKgPerBag = kpb;
      _catalogTaxPercent = tax;
      if (landing != null && landing > 0) {
        _buyCtrl.text = landing.toStringAsFixed(2);
      }
      if (selling != null && selling > 0) {
        _sellCtrl.text = selling.toStringAsFixed(2);
      } else {
        _sellCtrl.clear();
      }
      if (tax != null && tax > 0) {
        _taxMode = TaxMode.exclusive;
        _taxPercent = tax;
      } else {
        _taxMode = TaxMode.none;
        _taxPercent = 0;
      }
      _errors = const InlineLineValidation();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _qtyFocus.requestFocus();
    });
  }

  void _onItemPicked(InlineSearchItem it) {
    final row = catalogRowById(widget.catalog, it.id);
    if (row != null) {
      _applyCatalogRow(row, it.label);
    } else {
      setState(() {
        _catalogItemId = it.id;
        _itemCtrl.text = it.label;
        _errors = const InlineLineValidation();
      });
      _qtyFocus.requestFocus();
    }
  }

  bool get _needsAdvanced {
    final u = _unit.toLowerCase();
    if (u != 'bag' && u != 'sack') return false;
    return _catalogKgPerBag == null || _catalogKgPerBag! <= 0;
  }

  double get _previewTotal {
    final qty = parseInlineDecimal(_qtyCtrl.text) ?? 0;
    final buy = parseInlineDecimal(_buyCtrl.text) ?? 0;
    if (qty <= 0 || buy <= 0) return 0;
    return inlineLineTotalPreview(
      qty: qty,
      landingCost: buy,
      kgPerUnit: (_unit.toLowerCase() == 'bag' || _unit.toLowerCase() == 'sack')
          ? _catalogKgPerBag
          : null,
      taxPercent: _taxPercent,
      taxMode: _taxMode,
    );
  }

  void _tryCommit() {
    if (_committing) return;
    final result = buildInlinePurchaseLineMap(
      catalogItemId: _catalogItemId,
      itemName: _itemCtrl.text,
      qtyText: _qtyCtrl.text,
      unit: _unit,
      buyRateText: _buyCtrl.text,
      sellRateText: _sellCtrl.text,
      taxMode: _taxMode,
      taxPercent: _taxPercent,
      hsnCode: _hsn,
      itemCode: _itemCode,
      catalogKgPerBag: _catalogKgPerBag,
      catalogTaxPercent: _catalogTaxPercent,
    );
    if (!result.ok || result.line == null) {
      setState(() => _errors = result.errors);
      if (result.errors.item != null) {
        _itemFocus.requestFocus();
      } else if (result.errors.qty != null) {
        _qtyFocus.requestFocus();
      } else if (result.errors.buy != null) {
        _buyFocus.requestFocus();
      }
      return;
    }
    if (_needsAdvanced && widget.onOpenAdvanced != null) {
      // Bag without kg snapshot — hand off to full sheet for safety.
      widget.onOpenAdvanced!();
      return;
    }
    setState(() {
      _committing = true;
      _errors = const InlineLineValidation();
    });
    widget.onCommit(result.line!);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final unitChoices = <String>{
      ...kPurchaseInlineUnitChoices,
      if (_unit.isNotEmpty) _unit.toLowerCase(),
    }.toList();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _tryCommit,
      },
      child: Focus(
        onKeyEvent: _onKey,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Material(
            color: HexaColors.tealWashAlt.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: InlineSearchField(
                            items: widget.searchItems,
                            controller: _itemCtrl,
                            focusNode: _itemFocus,
                            placeholder: 'Search item…',
                            minQueryLength: 1,
                            textInputAction: TextInputAction.next,
                            focusAfterSelection: _qtyFocus,
                            onSelected: _onItemPicked,
                          ),
                        ),
                        if (_errors.item != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 4),
                            child: Text(
                              _errors.item!,
                              style: TextStyle(
                                fontSize: 10,
                                color: HexaColors.materialRed,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: TextField(
                        controller: _qtyCtrl,
                        focusNode: _qtyFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _cellDeco(
                          hint: 'Qty',
                          errorText: _errors.qty,
                        ),
                        onSubmitted: (_) => _unitFocus.requestFocus(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('unit-$_unit'),
                        focusNode: _unitFocus,
                        initialValue: unitChoices.contains(_unit.toLowerCase())
                            ? _unit.toLowerCase()
                            : unitChoices.first,
                        isDense: true,
                        decoration: _cellDeco(errorText: _errors.unit),
                        items: [
                          for (final u in unitChoices)
                            DropdownMenuItem(
                              value: u,
                              child: Text(
                                u.toUpperCase(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _unit = v);
                          _buyFocus.requestFocus();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: TextField(
                        controller: _buyCtrl,
                        focusNode: _buyFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _cellDeco(
                          hint: 'Buy ₹',
                          errorText: _errors.buy,
                        ),
                        onSubmitted: (_) => _sellFocus.requestFocus(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(5),
                      child: TextField(
                        controller: _sellCtrl,
                        focusNode: _sellFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _cellDeco(
                          hint: 'Sell ₹',
                          errorText: _errors.sell,
                        ),
                        onSubmitted: (_) => _tryCommit(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(6),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('tax-${_taxDropdownValue()}'),
                        focusNode: _taxFocus,
                        isDense: true,
                        initialValue: _taxDropdownValue(),
                        decoration: _cellDeco(),
                        items: const [
                          DropdownMenuItem(
                            value: 'none',
                            child: Text('No GST', style: TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: '5',
                            child: Text('5%', style: TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: '12',
                            child: Text('12%', style: TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: '18',
                            child: Text('18%', style: TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: '28',
                            child: Text('28%', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            if (v == 'none') {
                              _taxMode = TaxMode.none;
                              _taxPercent = 0;
                            } else {
                              _taxMode = TaxMode.exclusive;
                              _taxPercent = double.tryParse(v) ?? 0;
                            }
                          });
                          _tryCommit();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _previewTotal > 0 ? _inr0(_previewTotal) : '—',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: HexaColors.textOnLightSurface,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        IconButton(
                          tooltip: 'Save row (Enter)',
                          icon: _committing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 20),
                          onPressed: _committing ? null : _tryCommit,
                          visualDensity: VisualDensity.compact,
                        ),
                        if (widget.onOpenAdvanced != null)
                          TextButton(
                            onPressed: widget.onOpenAdvanced,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 24),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _needsAdvanced ? 'Adv…' : 'More',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _taxDropdownValue() {
    if (_taxMode == TaxMode.none || _taxPercent <= 0) return 'none';
    final p = _taxPercent;
    for (final preset in kPurchaseInlineTaxPresets) {
      if (preset > 0 && (p - preset).abs() < 0.01) {
        return preset == preset.roundToDouble()
            ? '${preset.round()}'
            : preset.toString();
      }
    }
    if ((p - 5).abs() < 0.01) return '5';
    if ((p - 12).abs() < 0.01) return '12';
    if ((p - 18).abs() < 0.01) return '18';
    if ((p - 28).abs() < 0.01) return '28';
    return '18';
  }
}
