import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/calc_engine.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/strict_decimal.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/line_display.dart';
import '../../../../core/utils/unit_classifier.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../../../shared/widgets/keyboard_safe_form_viewport.dart';
import 'party_inline_suggest_field.dart';

/// One purchase line: catalog search, qty/unit, landing, selling, optional
/// tax/discount (per kg for bag with a catalog kg snapshot, else per unit).
class PurchaseItemEntrySheet extends StatefulWidget {
  const PurchaseItemEntrySheet({
    super.key,
    required this.catalog,
    this.initial,
    required this.isEdit,
    required this.onCommitted,
    /// When set, each catalog pick refetches the item so HSN/tax/kg match the server
    /// (list payloads may be incomplete). Failures keep list-row data only.
    this.resolveCatalogItem,
    this.resolveLastDefaults,
    this.onDefaultsResolved,
    /// Full-screen [Scaffold] (ENTRY Prompt 1) instead of a bottom sheet.
    this.fullPage = false,
    /// When true, line payload omits freight / delivered / billty / line discount (purchase header carries these).
    this.omitLineFreightDeliveredBilltyDiscount = false,
    /// Optional: push catalog add-item route; caller invalidates catalog + returns `{id,name}`.
    this.navigateCatalogQuickAddItem,
    /// Boosts catalog suggestions when they match this supplier (defaults / last buy).
    this.preferredSupplierId,
  });

  final List<Map<String, dynamic>> catalog;
  final Map<String, dynamic>? initial;
  final bool isEdit;
  final void Function(Map<String, dynamic> line) onCommitted;
  final Future<Map<String, dynamic>> Function(String catalogItemId)?
      resolveCatalogItem;
  final Future<Map<String, dynamic>> Function(String catalogItemId)?
      resolveLastDefaults;
  final void Function(Map<String, dynamic> defaults)? onDefaultsResolved;
  final bool fullPage;
  final bool omitLineFreightDeliveredBilltyDiscount;
  final Future<Map<String, dynamic>?> Function()? navigateCatalogQuickAddItem;
  final String? preferredSupplierId;

  @override
  State<PurchaseItemEntrySheet> createState() => _PurchaseItemEntrySheetState();
}

class _PurchaseItemEntrySheetState extends State<PurchaseItemEntrySheet> {
  // Master rebuild default wholesale mode: inventory is count-only for BOX/TIN.
  // Advanced weight/item tracking for BOX/TIN is intentionally disabled for now.
  static const bool _advancedInventoryEnabled = false;
  final _scrollController = ScrollController();
  final _itemKey = GlobalKey();
  final _qtyKey = GlobalKey();
  final _unitKey = GlobalKey();
  final _landingKey = GlobalKey();
  final _sellingKey = GlobalKey();
  final _kgPerBagKey = GlobalKey();
  final _taxKey = GlobalKey();

  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _landingFocus = FocusNode();
  final _sellingFocus = FocusNode();
  final _kgManualFocus = FocusNode();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'kg');
  final _landingCtrl = TextEditingController();
  final _discCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();
  /// Manual kg per bag (when no catalog row or catalog row has no default_kg_per_bag).
  final _kgPerBagCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();
  final _deliveredCtrl = TextEditingController();
  final _billtyCtrl = TextEditingController();
  final _itemsPerBoxCtrl = TextEditingController();
  final _weightPerItemCtrl = TextEditingController();
  final _kgPerBoxCtrl = TextEditingController();
  final _weightPerTinCtrl = TextEditingController();
  final _lineNotesCtrl = TextEditingController();

  /// Persisted catalog row id for the line (`catalog_item_id` on save).
  String? _selectedCatalogItemId;
  /// When true: bag with kg snapshot — user enters landing & selling per kg.
  bool _weightPricing = false;
  /// kg per bag (from `default_kg_per_bag` or saved line).
  double? _kgPerUnit;
  String _freightType = 'separate';
  bool _boxFixedWeight = true;

  /// For bag lines: allow qty entry as **bags** or **kg** (converted to bags on save).
  String _qtyEntryMode = 'bags'; // 'bags' | 'kg'

  /// For weight-bag ₹/kg economics: text fields hold **per kg** vs **per bag** amounts.
  bool _rateFieldsPerKg = true;

  String? _errItem;
  String? _errQty;
  String? _errUnit;
  String? _errLanding;
  String? _errSelling;
  String? _errKgPerBag;
  String? _errHsn;
  String? _hsnCode;
  String? _itemCode;
  final Map<String, Map<String, dynamic>> _catalogFetchById = {};
  /// Non-null after [resolveLastDefaults] applied meaningful trade history.
  String? _lastPurchaseAutofillHint;
  /// Ignore stale default fetches when the user selects another catalog row mid-flight.
  int _catalogPickSeq = 0;
  /// True while a suggestion pick mutates `_itemCtrl` + `_selectedCatalogItemId`; skips
  /// the label-vs-row unlink in `_onItemTextChanged` for that microtask window.
  bool _suppressCatalogTextUnlink = false;
  Timer? _defaultsDebounceTimer;

  late final Listenable _lineTotalsListenable;

  /// Memoized catalog rows as [InlineSearchItem] (rebuilt when [widget.catalog] changes).
  List<InlineSearchItem> _catalogSearchItems = const [];

  /// Short hint driven by [_activeClassification()] after catalog/name changes.
  String? _unitDetectHint;

  /// Snapshot of text fields after init / reset — for unsaved-change guard (full-page).
  Map<String, String>? _fieldBaseline;

  /// Indian grouping for weight line (display only).
  static final NumberFormat _inQtyWtFmt =
      NumberFormat('#,##,##0.###', 'en_IN');

  void _onItemTextChanged() {
    if (!mounted) return;
    if (_suppressCatalogTextUnlink) return;
    // If the user edits the typed label away from the selected catalog row,
    // unlink automatically so we don't persist a stale `catalog_item_id`.
    // Without this, selecting "Rice" then typing "Rice123" would silently save
    // the line against the Rice catalog id.
    if (_selectedCatalogItemId != null && _selectedCatalogItemId!.isNotEmpty) {
      final row = _catalogRowById(_selectedCatalogItemId!);
      final selectedLabel = (row?['name']?.toString() ?? '').trim();
      if (_itemCtrl.text.trim() != selectedLabel) {
        setState(() {
          _catalogPickSeq++;
          _selectedCatalogItemId = null;
          _lastPurchaseAutofillHint = null;
          _unitDetectHint = null;
          _errItem = null;
          _hsnCode = null;
          _itemCode = null;
        });
        return;
      }
    }
    _maybeAutoSeedKgFromName();
    if (_errItem != null) setState(() => _errItem = null);
  }

  /// [Bug 2 fix] When unit is `bag` and the item label contains "NN KG"
  /// (e.g. "SUGAR 50 KG"), auto-populate `_kgPerUnit` and the kg-per-bag input
  /// so 100 bags × 50kg = 5000 kg renders correctly without a manual entry.
  /// Catalog kg/bag (when present) wins over name parsing.
  void _maybeAutoSeedKgFromName() {
    if (_kgPerUnit != null && _kgPerUnit! > 0) return;
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return;
    if (_hasCatalogKg()) return;
    final c = _activeClassification();
    final kn = c.kgFromName;
    if (kn == null || kn <= 0) return;
    setState(() {
      _kgPerUnit = kn;
      _weightPricing = true;
      _kgPerBagCtrl.text = _fmtQty(kn);
    });
  }

  void _onKgPerBagChanged() {
    final v = _parseD(_kgPerBagCtrl.text);
    if (!mounted) return;
    final u = _unitCtrl.text.trim().toLowerCase();
    final bagFamily = u == 'bag' || u == 'sack'; // legacy sack treated as bag
    setState(() {
      _kgPerUnit = (v != null && v > 0) ? v : null;
      _weightPricing = bagFamily && _kgPerUnit != null && _kgPerUnit! > 0;
      if (_errKgPerBag != null) _errKgPerBag = null;
    });
  }

  void _maybeCoerceQtyModeForUnit() {
    if (!_isBagFamilyUnit()) {
      if (_qtyEntryMode != 'bags') {
        setState(() => _qtyEntryMode = 'bags');
      }
      return;
    }
    final k = _kgPer();
    if (k == null || k <= 0) {
      if (_qtyEntryMode != 'bags') {
        setState(() => _qtyEntryMode = 'bags');
      }
    }
  }

  void _schedulePreviewRebuild() {}

  @override
  void initState() {
    super.initState();
    _itemCtrl.addListener(_onItemTextChanged);
    _kgPerBagCtrl.addListener(_onKgPerBagChanged);
    final init = widget.initial;
    if (init != null) {
      _itemCtrl.text = init['item_name']?.toString() ?? '';
      _selectedCatalogItemId = init['catalog_item_id']?.toString();
      final qVal = coerceToDoubleNullable(init['qty']);
      if (qVal != null) {
        _qtyCtrl.text = (qVal - qVal.roundToDouble()).abs() < 1e-9
            ? qVal.round().toString()
            : qVal.toString();
      } else {
        _qtyCtrl.text = '';
      }
      _unitCtrl.text = init['unit']?.toString() ?? 'kg';
      _qtyEntryMode = 'bags';

      final kpu = coerceToDoubleNullable(
          init['kg_per_unit'] ?? init['weight_per_unit']);
      final lck = coerceToDoubleNullable(init['landing_cost_per_kg']);
      if (kpu != null && kpu > 0) {
        _weightPricing = true;
        _kgPerUnit = kpu;
        _kgPerBagCtrl.text = _fmtQty(kpu);
        if (lck != null && lck > 0) {
          _landingCtrl.text = lck.toStringAsFixed(2);
        } else {
          final lc = coerceToDoubleNullable(
              init['landing_cost'] ?? init['purchase_rate']);
          if (lc != null && lc > 0) {
            _landingCtrl.text = (lc / kpu).toStringAsFixed(2);
          } else {
            _landingCtrl.text = '';
          }
        }
        final sc = coerceToDoubleNullable(
            init['selling_cost'] ?? init['selling_rate']);
        if (sc != null && sc > 0) {
          _sellingCtrl.text = (sc / kpu).toStringAsFixed(2);
        } else {
          _sellingCtrl.text = '';
        }
      } else {
        _weightPricing = false;
        _kgPerUnit = null;
        final r = coerceToDoubleNullable(
            init['landing_cost'] ?? init['purchase_rate']);
        _landingCtrl.text =
            r != null && r > 0 ? r.toStringAsFixed(2) : '';
        final s = coerceToDoubleNullable(
            init['selling_cost'] ?? init['selling_rate']);
        if (s != null && s > 0) {
          _sellingCtrl.text = s.toStringAsFixed(2);
        } else {
          _sellingCtrl.text = '';
        }
      }

      final d = coerceToDoubleNullable(init['discount']);
      _discCtrl.text = d != null && d > 0 ? d.toString() : '';
      final t = coerceToDoubleNullable(init['tax_percent']);
      _taxCtrl.text = t != null && t > 0 ? t.toString() : '';
      final hsn = init['hsn_code']?.toString().trim() ?? '';
      _hsnCode = hsn.isEmpty ? null : hsn;
      final ic = init['item_code']?.toString().trim() ?? '';
      _itemCode = ic.isEmpty ? null : ic;
      _lineNotesCtrl.text = init['description']?.toString() ?? '';
      final ft = init['freight_type']?.toString();
      if (ft == 'included' || ft == 'separate') _freightType = ft!;
      _freightCtrl.text = _fmtInput(init['freight_value'] ?? init['freight_amount'], 2);
      _deliveredCtrl.text = _fmtInput(init['delivered_rate'], 2);
      _billtyCtrl.text = _fmtInput(init['billty_rate'], 2);
      _itemsPerBoxCtrl.text = _fmtInput(init['items_per_box'], 3, trim: true);
      _weightPerItemCtrl.text = _fmtInput(init['weight_per_item'], 3, trim: true);
      _kgPerBoxCtrl.text = _fmtInput(init['kg_per_box'], 3, trim: true);
      _weightPerTinCtrl.text = _fmtInput(init['weight_per_tin'], 3, trim: true);
      _boxFixedWeight = (init['box_mode']?.toString() != 'items_per_box');
    }
    _syncKgStateFromCatalogRow();
    _lineTotalsListenable = Listenable.merge([
      _qtyCtrl,
      _unitCtrl,
      _landingCtrl,
      _discCtrl,
      _taxCtrl,
      _sellingCtrl,
      _freightCtrl,
      _deliveredCtrl,
      _billtyCtrl,
      _itemsPerBoxCtrl,
      _weightPerItemCtrl,
      _kgPerBoxCtrl,
      _weightPerTinCtrl,
      _kgPerBagCtrl,
      _lineNotesCtrl,
    ]);
    _rebuildCatalogSearchItems();
    _storeFieldBaseline();
  }

  void _syncKgStateFromCatalogRow() {
    if (_selectedCatalogItemId == null || _selectedCatalogItemId!.isEmpty) return;
    if (_kgPerUnit != null && _kgPerUnit! > 0) return;
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return;
    final r = _catalogRowById(_selectedCatalogItemId!);
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
    _defaultsDebounceTimer?.cancel();
    _scrollController.dispose();
    _itemCtrl.dispose();
    _itemFocus.dispose();
    _qtyFocus.dispose();
    _landingFocus.dispose();
    _sellingFocus.dispose();
    _kgManualFocus.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _landingCtrl.dispose();
    _discCtrl.dispose();
    _taxCtrl.dispose();
    _sellingCtrl.dispose();
    _kgPerBagCtrl.dispose();
    _freightCtrl.dispose();
    _deliveredCtrl.dispose();
    _billtyCtrl.dispose();
    _itemsPerBoxCtrl.dispose();
    _weightPerItemCtrl.dispose();
    _kgPerBoxCtrl.dispose();
    _weightPerTinCtrl.dispose();
    _lineNotesCtrl.dispose();
    super.dispose();
  }

  String _fmtInput(Object? value, int scale, {bool trim = false}) {
    if (value == null) return '';
    try {
      final d = StrictDecimal.fromObject(value);
      if (d.isZero) return '';
      return d.format(scale, trim: trim);
    } on FormatException {
      return '';
    }
  }

  Map<String, dynamic>? _catalogRowById(String id) {
    final cached = _catalogFetchById[id];
    if (cached != null) return cached;
    for (final m in widget.catalog) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  Map<String, dynamic>? _rowForClassification() {
    final id = _selectedCatalogItemId;
    if (id == null || id.isEmpty) return null;
    return _catalogRowById(id);
  }

  double? _catalogKpb(Map<String, dynamic>? row) {
    if (row == null) return null;
    for (final key in <String>[
      'default_kg_per_bag',
      'kg_per_bag',
      'kg_per_unit',
    ]) {
      final v = row[key];
      if (v is num && v > 0) return v.toDouble();
    }
    return null;
  }

  /// Current label + catalog + wired unit → [UnitClassification] for UI/validation/math.
  UnitClassification _activeClassification() {
    final row = _rowForClassification();
    return UnitClassifier.classify(
      itemName: _itemCtrl.text.trim(),
      lineUnit: _unitCtrl.text,
      catalogDefaultUnit: row?['default_unit']?.toString(),
      catalogDefaultKgPerBag: _catalogKpb(row),
      categoryName: row?['category_name']?.toString() ??
          row?['category']?.toString(),
      subcategoryName: row?['subcategory_name']?.toString() ??
          row?['subcategory']?.toString(),
    );
  }

  String _wireUnitFromClassification({
    required UnitClassification c,
    required Map<String, dynamic>? row,
    required double? kpbD,
    required String displayName,
  }) {
    final dn = displayName.toUpperCase();
    switch (c.type) {
      case UnitType.weightBag:
        if (row == null) return 'bag';
        final du = row['default_unit']?.toString().trim().toLowerCase();
        if (du == 'sack') return 'bag';
        return 'bag';
      case UnitType.multiPackBox:
        return 'box';
      case UnitType.singlePack:
        if (dn.contains('TIN')) return 'tin';
        if (dn.contains('BOX') ||
            dn.contains('CTN') ||
            dn.contains('CARTON')) {
          return 'box';
        }
        if (row == null) return 'kg';
        return _lineUnitForCatalog(row, kpbD: kpbD);
    }
  }

  String? _hintFromClassification(UnitClassification c, String wireUnit) {
    switch (c.type) {
      case UnitType.weightBag:
        if (c.kgFromName != null && c.kgFromName! > 0) {
          return 'Classified: ${_fmtQty(c.kgFromName!)} kg bag';
        }
        return 'Classified: weight bag';
      case UnitType.multiPackBox:
        return 'Classified: items/box';
      case UnitType.singlePack:
        if (wireUnit == 'box' && c.kgFromName != null && c.kgFromName! > 0) {
          return 'Classified: ${_fmtQty(c.kgFromName!)} kg box';
        }
        if (wireUnit == 'tin' && c.kgFromName != null && c.kgFromName! > 0) {
          return 'Classified: ${_fmtQty(c.kgFromName!)} kg tin';
        }
        return null;
    }
  }

  void _adjustBoxFixedForClassification(UnitClassification c) {
    if (!_lineUnitIsBox(_unitCtrl.text)) return;
    if (c.type == UnitType.multiPackBox) _boxFixedWeight = false;
    if (c.type == UnitType.singlePack) _boxFixedWeight = true;
  }

  String? _hsnFromRow(Map<String, dynamic> row) {
    final a = row['hsn_code']?.toString().trim() ?? '';
    if (a.isNotEmpty) return a;
    final b = row['hsn']?.toString().trim() ?? '';
    return b.isEmpty ? null : b;
  }

  String? _itemCodeFromRow(Map<String, dynamic> row) {
    final a = row['item_code']?.toString().trim() ?? '';
    return a.isEmpty ? null : a;
  }

  static bool _lineUnitIsBox(String? u) =>
      (u ?? '').trim().toLowerCase() == 'box';
  static bool _lineUnitIsTin(String? u) =>
      (u ?? '').trim().toLowerCase() == 'tin';

  static bool _isWeightUnit(String? u) {
    final x = (u ?? '').trim().toLowerCase();
    // Back-compat: treat legacy `sack` as canonical `bag`.
    return x == 'bag' || x == 'sack';
  }

  // Master rebuild: only kg / bag / box / tin are allowed for new lines.
  // `sack` and `piece` removed from the dropdown; legacy rows still display
  // (sack normalized to bag for back-compat, see _onUnitDropdownChanged).
  static const _unitDropdownBaseChoices = <String>[
    'kg',
    'bag',
    'box',
    'tin',
  ];

  List<String> _suggestedUnitChoices() {
    final row = _selectedCatalogItemId != null ? _catalogRowById(_selectedCatalogItemId!) : null;
    final du = (row?['default_unit']?.toString() ?? '').trim().toLowerCase();
    final c = _activeClassification();

    // Default: keep the list short to reduce mis-taps.
    // Always include the currently selected unit (even if it isn't in the base list).
    final out = <String>{};

    if (du == 'bag' || du == 'sack') {
      out.addAll(const {'bag', 'kg'});
    } else if (du == 'box') {
      out.addAll(const {'box', 'kg'});
    } else if (du == 'tin') {
      out.addAll(const {'tin', 'kg'});
    } else if (du == 'kg') {
      out.addAll(const {'kg', 'bag'});
    }

    if (c.type == UnitType.weightBag) {
      out.addAll(const {'bag', 'kg'});
    } else if (c.type == UnitType.multiPackBox) {
      out.addAll(const {'box', 'kg'});
    } else if (c.type == UnitType.singlePack) {
      out.addAll(const {'kg'});
      if (_lineUnitIsBox(_unitCtrl.text)) out.add('box');
      if (_lineUnitIsTin(_unitCtrl.text)) out.add('tin');
    }

    // Fallback when we couldn't infer anything.
    if (out.isEmpty) {
      out.addAll(_unitDropdownBaseChoices);
    }

    final current = _unitCtrl.text.trim().toLowerCase();
    if (current.isNotEmpty) out.add(current == 'qtl' ? 'quintal' : current);

    // Return ordered by our base list first, then anything else.
    final ordered = <String>[
      for (final u in _unitDropdownBaseChoices)
        if (out.contains(u)) u,
      for (final u in out)
        if (!_unitDropdownBaseChoices.contains(u)) u,
    ];
    return ordered;
  }

  String _unitDropdownValue() {
    var t = _unitCtrl.text.trim().toLowerCase();
    if (t == 'qtl') t = 'quintal';
    if (t.isNotEmpty && !_unitDropdownBaseChoices.contains(t)) return t;
    if (_unitDropdownBaseChoices.contains(t)) return t;
    return 'kg';
  }

  void _onUnitDropdownChanged(String? value) {
    if (value == null) return;
    var v = value;
    // Back-compat: normalize legacy `sack` to canonical `bag`.
    if (v.trim().toLowerCase() == 'sack') v = 'bag';
    _clearFieldErrors();
    final vLow = v.trim().toLowerCase();

    // Default wholesale mode: BOX/TIN are count-only. Clear any weight fields so
    // we never accidentally derive kg totals or show hidden inputs.
    if (!_advancedInventoryEnabled && (vLow == 'box' || vLow == 'tin')) {
      _weightPricing = false;
      _rateFieldsPerKg = false;
      _kgPerUnit = null;
      _kgPerBagCtrl.clear();
      _itemsPerBoxCtrl.clear();
      _weightPerItemCtrl.clear();
      _kgPerBoxCtrl.clear();
      _weightPerTinCtrl.clear();
      if (_qtyEntryMode != 'bags') _qtyEntryMode = 'bags';
    }
    if (!_isWeightUnit(v) && !_hasCatalogKg()) {
      _kgPerUnit = null;
      _kgPerBagCtrl.clear();
    }
    _recomputeModeFromUnitAndCatalog();
    _maybeCoerceQtyModeForUnit();
    setState(() {
      _unitCtrl.text = v;
      _adjustBoxFixedForClassification(_activeClassification());
    });
    // [Bug 2] After switching to bag, seed kg-per-bag from item name if catalog
    // didn't provide one (`SUGAR 50 KG` → 50, `RICE 26 KG` → 26).
    _maybeAutoSeedKgFromName();
  }

  Widget _unitDropdownField({required String? errorText}) {
    final v = _unitDropdownValue();
    final ordered = _suggestedUnitChoices();
    final itemSet = <String>{...ordered, v};
    final finalOrdered = <String>[
      for (final u in ordered)
        if (itemSet.contains(u)) u,
      for (final x in itemSet)
        if (!ordered.contains(x)) x,
    ];
    return KeyedSubtree(
      key: ValueKey<String>('unit|$v'),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: v,
        decoration: _deco('Unit *', errorText: errorText),
        items: [
          for (final u in finalOrdered)
            DropdownMenuItem<String>(
              value: u,
              child: Text(
                u,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
        ],
        onChanged: _onUnitDropdownChanged,
      ),
    );
  }

  /// Weight bags: ₹/kg landing × total kg purchased.
  bool get _ratesPerKgEconomics {
    return _activeClassification().type == UnitType.weightBag &&
        _kgPer() != null &&
        _kgPer()! > 0;
  }

  bool get _showPerKgLandingLabels {
    return _activeClassification().type == UnitType.weightBag;
  }

  void _onRateBasisChanged(bool wantPerKg) {
    if (wantPerKg == _rateFieldsPerKg) return;
    final k = _kgPer();
    final land = _parseD(_landingCtrl.text);
    final sell = _parseD(_sellingCtrl.text);
    setState(() {
      if (k != null && k > 0) {
        if (_rateFieldsPerKg && !wantPerKg) {
          if (land != null && land > 0) {
            _landingCtrl.text = _fmtMoney(land * k);
          }
          if (sell != null && sell > 0) {
            _sellingCtrl.text = _fmtMoney(sell * k);
          }
        } else if (!_rateFieldsPerKg && wantPerKg) {
          if (land != null && land > 0) {
            _landingCtrl.text = _fmtMoney(land / k);
          }
          if (sell != null && sell > 0) {
            _sellingCtrl.text = _fmtMoney(sell / k);
          }
        }
      }
      _rateFieldsPerKg = wantPerKg;
    });
  }

  /// Landing field interpreted as **₹/kg** for wire when [_ratesPerKgEconomics].
  double? _landingParsedAsPerKg() {
    final raw = _parseD(_landingCtrl.text);
    if (raw == null) return null;
    if (!_ratesPerKgEconomics) return raw;
    if (_rateFieldsPerKg) return raw;
    final k = _kgPer();
    if (k == null || k <= 0) return raw;
    return raw / k;
  }

  /// Selling field interpreted as **₹/kg** for wire when [_ratesPerKgEconomics].
  double? _sellingParsedAsPerKg() {
    final raw = _parseD(_sellingCtrl.text);
    if (raw == null) return null;
    if (!_ratesPerKgEconomics) return raw;
    if (_rateFieldsPerKg) return raw;
    final k = _kgPer();
    if (k == null || k <= 0) return raw;
    return raw / k;
  }

  InputDecoration _deco(
    String label, {
    String? prefixText,
    String? errorText,
  }) {
    final pad = widget.fullPage
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 8);
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
      contentPadding: pad,
    );
  }

  /// Rounded section shell for full-page add item only.
  Widget _fpShell(Widget child) {
    if (!widget.fullPage) return child;
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: const Color(0xFF17A8A7).withValues(alpha: 0.22),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }

  double? _parseD(String s) {
    final v = s.trim();
    if (v.isEmpty) return null;
    if (!isValidNonNegativeDecimalInput(v, maxDecimals: 3)) return null;
    try {
      return StrictDecimal.parse(v).toDouble();
    } on FormatException {
      return null;
    }
  }

  double? _numD(Object? v) {
    if (v == null) return null;
    try {
      return StrictDecimal.fromObject(v).toDouble();
    } on FormatException {
      return null;
    }
  }

  double _enteredQtyRaw() => _parseD(_qtyCtrl.text) ?? 0;

  bool _isBagFamilyUnit() {
    final u = _unitCtrl.text.trim().toLowerCase();
    return u == 'bag' || u == 'sack';
  }

  bool _bagQtyIsWhole(double bags) =>
      (bags - bags.roundToDouble()).abs() < 1e-6;

  /// Quantity interpreted as **bags** for calculations and payload.
  /// When [_qtyEntryMode] == 'kg', interpret the input as kg and convert to bags.
  double _qtyVal() {
    final raw = _enteredQtyRaw();
    if (raw <= 0) return 0;
    if (_qtyEntryMode != 'kg') return raw;
    if (!_isBagFamilyUnit()) return raw;
    final k = _kgPer();
    if (k == null || k <= 0) return raw;
    return raw / k;
  }

  /// Entered kg when in kg-mode for bag.
  double? _enteredKgForBagMode() {
    if (_qtyEntryMode != 'kg') return null;
    if (!_isBagFamilyUnit()) return null;
    final raw = _enteredQtyRaw();
    return raw > 0 ? raw : null;
  }

  String _fmtQty(double q) =>
      StrictDecimal.fromObject(q).format(3, trim: true);

  String _fmtMoney(double q) => StrictDecimal.fromObject(q).format(2);

  TextInputFormatter _decimalFormatter(int maxDecimals) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      return isValidNonNegativeDecimalInput(
        newValue.text,
        maxDecimals: maxDecimals,
      )
          ? newValue
          : oldValue;
    });
  }

  /// kg/bag resolved to a number; single source of truth = `_kgPerUnit` (seeded
  /// from catalog row on pick OR from the manual "Kg per bag" input).
  double? _kgPer() =>
      (_kgPerUnit != null && _kgPerUnit! > 0) ? _kgPerUnit : null;

  /// Catalog item selected AND catalog row carries kg/bag.
  bool _hasCatalogKg() {
    final id = _selectedCatalogItemId;
    if (id == null || id.isEmpty) return false;
    final r = _catalogRowById(id);
    if (r == null) return false;
    for (final key in <String>['default_kg_per_bag', 'kg_per_bag', 'kg_per_unit']) {
      final v = r[key];
      if (v is num && v > 0) return true;
    }
    return false;
  }

  double _sheetPhysicalKgTotal() {
    final c = _activeClassification();
    double? kgName = c.kgFromName;
    if (!(c.type == UnitType.singlePack &&
        ((_lineUnitIsBox(_unitCtrl.text) ||
            _lineUnitIsTin(_unitCtrl.text) ||
            (_unitCtrl.text.trim().toLowerCase() == 'kg'))))) {
      kgName = null;
    }
    return classifierLineWeightKg(
      type: c.type,
      qty: _qtyVal(),
      kgPerUnit: _kgPer(),
      kgFromName: kgName,
      itemsPerBox: _parseD(_itemsPerBoxCtrl.text),
      weightPerItem: _parseD(_weightPerItemCtrl.text),
    );
  }

  String _capitalUnitWord(String u) {
    final t = u.trim();
    if (t.isEmpty) return 'Unit';
    final lower = t.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.length > 1 ? lower.substring(1) : ''}';
  }

  String _qtyFieldLabel() {
    final u = _unitCtrl.text.trim().toLowerCase();
    if (_qtyEntryMode == 'kg' && (u == 'bag' || u == 'sack')) {
      return 'Qty (kg) *';
    }
    if (u == 'bag') return 'No. of bags *';
    if (u == 'sack') return 'No. of bags *';
    if (u == 'box') return 'No. of boxes *';
    if (u == 'tin') return 'No. of tins *';
    if (u == 'kg' || u == 'kgs' || u == 'quintal' || u == 'qtl') {
      return 'Qty (kg) *';
    }
    return 'Qty *';
  }

  String _qtyAndUnitWeightSummaryLine() {
    final q = _qtyVal();
    final u = _unitCtrl.text.trim();
    if (q <= 0 || u.isEmpty) return '—';
    final c = _activeClassification();

    if (c.type == UnitType.multiPackBox) {
      final qtyTxt = _inQtyWtFmt.format(q);
      final items = classifierTotalItems(
        type: c.type,
        qty: q,
        itemsPerBox: _parseD(_itemsPerBoxCtrl.text),
      );
      final boxWord = _capitalUnitWord('box');
      return '$qtyTxt $boxWord • ${_inQtyWtFmt.format(items)} Items';
    }

    final totalKg = _sheetPhysicalKgTotal();
    return formatLineQtyWeight(
      qty: q,
      unit: u,
      kgPerUnit: _kgPer(),
      totalWeightKg: totalKg > 1e-9 ? totalKg : null,
    );
  }

  Widget? _qtyEntryModeSegmented() {
    if (!_isBagFamilyUnit()) return null;
    final k = _kgPer();
    if (k == null || k <= 0) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'bags', label: Text('Bags')),
            ButtonSegment(value: 'kg', label: Text('Kg')),
          ],
          selected: {_qtyEntryMode},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setState(() {
              _qtyEntryMode = s.first;
              _errQty = null;
            });
            _schedulePreviewRebuild();
          },
        ),
      ),
    );
  }

  Widget? _kgEntryConversionHint() {
    final k = _kgPer();
    if (k == null || k <= 0) return null;
    final enteredKg = _enteredKgForBagMode();
    if (enteredKg == null || enteredKg <= 0) return null;
    final bags = enteredKg / k;
    final theme = Theme.of(context);

    final bagsTxt =
        _bagQtyIsWhole(bags) ? '${bags.round()}' : _fmtQty(bags);
    final kgTxt = _inQtyWtFmt.format(enteredKg);
    final totalKgTxt = _inQtyWtFmt.format(bags * k);
    final needsWhole = !_bagQtyIsWhole(bags);

    return Material(
      color: needsWhole ? const Color(0xFFFFF7ED) : const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '$kgTxt kg → $bagsTxt ${_unitCtrl.text.trim()}'
                '${needsWhole ? ' (needs whole bags)' : ''}'
                '  ·  $bagsTxt × ${_fmtQty(k)} kg/bag = $totalKgTxt kg',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: needsWhole
                      ? const Color(0xFF9A3412)
                      : const Color(0xFF065F46),
                  height: 1.25,
                ),
              ),
            ),
            if (needsWhole) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  final flo = (bags).floorToDouble();
                  final nextKg = flo * k;
                  setState(() {
                    _qtyCtrl.text = _fmtQty(nextKg);
                    _errQty = null;
                  });
                  _schedulePreviewRebuild();
                },
                child: const Text('Round down'),
              ),
              TextButton(
                onPressed: () {
                  final cei = (bags).ceilToDouble();
                  final nextKg = cei * k;
                  setState(() {
                    _qtyCtrl.text = _fmtQty(nextKg);
                    _errQty = null;
                  });
                  _schedulePreviewRebuild();
                },
                child: const Text('Round up'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  TradeCalcLine _currentLine() {
    final qty = _qtyVal();
    final disc = _parseD(_discCtrl.text);
    final tax = _parseD(_taxCtrl.text);
    if (_ratesPerKgEconomics) {
      final kpu = _kgPer()!;
      final perKg = _landingParsedAsPerKg() ?? 0;
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

  Widget? _rateEntryBasisSegmented(double? kPer, bool showPerKg) {
    if (!showPerKg || kPer == null || kPer <= 0) return null;
    final unitLabel = _isBagFamilyUnit() ? '₹/bag' : '₹/unit';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<bool>(
          segments: [
            const ButtonSegment(value: true, label: Text('₹/kg')),
            ButtonSegment(value: false, label: Text(unitLabel)),
          ],
          selected: {_rateFieldsPerKg},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            _onRateBasisChanged(s.first);
          },
        ),
      ),
    );
  }

  double _profitPreview() {
    final sell = _ratesPerKgEconomics
        ? _sellingParsedAsPerKg()
        : _parseD(_sellingCtrl.text);
    if (sell == null) return 0;
    final lineCharges = widget.omitLineFreightDeliveredBilltyDiscount
        ? 0.0
        : (_freightType == 'separate' ? (_parseD(_freightCtrl.text) ?? 0) : 0) +
            (_parseD(_deliveredCtrl.text) ?? 0) +
            (_parseD(_billtyCtrl.text) ?? 0);
    if (_ratesPerKgEconomics) {
      final k = _kgPer()!;
      final perKgLand = _landingParsedAsPerKg() ?? 0;
      final totalK = _qtyVal() * k;
      return ((sell - perKgLand) * totalK) - lineCharges;
    }
    final rate = _parseD(_landingCtrl.text) ?? 0;
    return ((sell - rate) * _qtyVal()) - lineCharges;
  }

  void _clearFieldErrors() {
    setState(() {
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
      _errSelling = null;
      _errKgPerBag = null;
      _errHsn = null;
    });
  }

  void _rebuildCatalogSearchItems() {
    final pref = widget.preferredSupplierId?.trim();
    final out = <InlineSearchItem>[];
    for (final row in widget.catalog) {
      var boost = 0;
      if (pref != null && pref.isNotEmpty) {
        final ls = row['last_supplier_id']?.toString().trim();
        if (ls == pref) boost += 120;
        final ids = row['default_supplier_ids'];
        if (ids is List) {
          for (final e in ids) {
            if (e != null && e.toString().trim() == pref) {
              boost += 80;
              break;
            }
          }
        }
      }
      final blob = _catalogSearchBlob(row);
      out.add(
        InlineSearchItem(
          id: row['id']?.toString() ?? '',
          label: row['name']?.toString() ?? '',
          subtitle: row['default_unit']?.toString(),
          searchText: blob.isEmpty ? null : blob,
          sortBoost: boost,
        ),
      );
    }
    _catalogSearchItems = out;
  }

  /// Space-joined lowercase tokens for typeahead (name + code + HSN).
  String _catalogSearchBlob(Map<String, dynamic> row) {
    final parts = <String>[
      row['name']?.toString().trim() ?? '',
      row['item_code']?.toString().trim() ?? '',
      row['hsn_code']?.toString().trim() ?? '',
      row['hsn']?.toString().trim() ?? '',
    ].where((s) => s.isNotEmpty);
    return parts.join(' ').toLowerCase();
  }

  @override
  void didUpdateWidget(covariant PurchaseItemEntrySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog ||
        oldWidget.preferredSupplierId != widget.preferredSupplierId) {
      _rebuildCatalogSearchItems();
    }
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

  Map<String, String> _snapshotFields() {
    return {
      'item': _itemCtrl.text,
      'qty': _qtyCtrl.text,
      'unit': _unitCtrl.text,
      'landing': _landingCtrl.text,
      'selling': _sellingCtrl.text,
      'disc': _discCtrl.text,
      'tax': _taxCtrl.text,
      'kgpb': _kgPerBagCtrl.text,
      'notes': _lineNotesCtrl.text,
    };
  }

  void _storeFieldBaseline() {
    _fieldBaseline = _snapshotFields();
  }

  bool _isDirtySheet() {
    final b = _fieldBaseline;
    if (b == null) return false;
    final n = _snapshotFields();
    for (final e in n.entries) {
      if ((b[e.key] ?? '') != e.value) return true;
    }
    return false;
  }

  Future<void> _confirmDiscardAndPop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You will lose edits to this line.'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) context.pop();
  }

  Future<void> _handleLeadingBack() async {
    if (!_isDirtySheet()) {
      if (mounted && context.canPop()) context.pop();
      return;
    }
    await _confirmDiscardAndPop();
  }

  bool _showHsnFooterMeta() {
    final tax = _parseD(_taxCtrl.text) ?? 0;
    if (tax > 1e-9) return true;
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u == 'bag' || u == 'sack') return true;
    return _activeClassification().type == UnitType.weightBag;
  }

  Widget? _suggestOneBagInsteadOfKgBanner() {
    final c = _activeClassification();
    final kn = c.kgFromName;
    if (kn == null || kn <= 0) return null;
    if (_unitCtrl.text.trim().toLowerCase() != 'kg') return null;
    final q = _qtyVal();
    if (q <= 0 || (q - kn).abs() > 0.01 * math.max(1.0, kn)) return null;
    final theme = Theme.of(context);
    final knLabel =
        (kn - kn.roundToDouble()).abs() < 1e-6 ? '${kn.round()}' : kn.toStringAsFixed(1);
    return Material(
      color: const Color(0xFFE0F2FE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'This name looks like a $knLabel kg pack. Record as 1 bag instead?',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0369A1),
                  height: 1.25,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _unitCtrl.text = 'bag';
                  _qtyCtrl.text = '1';
                  _weightPricing = true;
                  _kgPerUnit = kn;
                  _kgPerBagCtrl.text = _fmtQty(kn);
                  _recomputeModeFromUnitAndCatalog();
                });
              },
              child: const Text('Use 1 bag'),
            ),
          ],
        ),
      ),
    );
  }

  /// Bag qty × kg/bag implies a huge total — user may have meant **kg** as the unit.
  Widget? _didYouMeanKgNotBagsBanner() {
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return null;
    final k = _kgPer();
    if (k == null || k <= 0) return null;
    final q = _qtyVal();
    if (q <= 0) return null;
    final totalK = q * k;
    if (totalK <= 50000 && q <= 200) return null;
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Did you mean ${_inQtyWtFmt.format(q)} kg (not ${_inQtyWtFmt.format(q)} bags × ${_fmtQty(k)} kg)?',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A3412),
                  height: 1.25,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _unitCtrl.text = 'kg';
                  _qtyCtrl.text = _fmtQty(q);
                  _weightPricing = false;
                  _kgPerUnit = null;
                  _kgPerBagCtrl.clear();
                  _recomputeModeFromUnitAndCatalog();
                });
              },
              child: const Text('Use kg'),
            ),
          ],
        ),
      ),
    );
  }

  /// Name encodes a weight bag but unit is kg — qty is **kg**, not bag count.
  Widget? _nameImpliesBagButKgUnitBanner() {
    final c = _activeClassification();
    if (c.type != UnitType.weightBag || c.kgFromName == null || c.kgFromName! <= 0) {
      return null;
    }
    if (_unitCtrl.text.trim().toLowerCase() != 'kg') return null;
    final theme = Theme.of(context);
    final kn = c.kgFromName!;
    final knLabel = (kn - kn.roundToDouble()).abs() < 1e-6
        ? '${kn.round()}'
        : kn.toStringAsFixed(1);
    return Material(
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          'Name looks like a $knLabel kg/bag item — quantity is in **kg**, not bags. Switch unit to bag to count bags.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF065F46),
            height: 1.25,
          ),
        ),
      ),
    );
  }

  /// Selling stored per line unit on the wire; weight mode: multiply per-kg × kg_per_unit.
  /// Call only after validation; [sell] must be non-null and >= 0.
  double _sellingForPayloadForWire(double sell) {
    if (_ratesPerKgEconomics) {
      final k = _kgPer()!;
      return sell * k;
    }
    return sell;
  }

  Map<String, dynamic>? _validateAndBuildLine() {
    final name = _itemCtrl.text.trim();
    final qty = _qtyVal();
    final unit = _unitCtrl.text.trim();
    final rate =
        _ratesPerKgEconomics ? (_landingParsedAsPerKg() ?? 0) : (_parseD(_landingCtrl.text) ?? 0);

    final catalogId = _selectedCatalogItemId;
    final rowSnap = catalogId != null && catalogId.isNotEmpty
        ? _catalogRowById(catalogId)
        : null;
    final clf = UnitClassifier.classify(
      itemName: name,
      lineUnit: unit,
      catalogDefaultUnit: rowSnap?['default_unit']?.toString(),
      catalogDefaultKgPerBag: _catalogKpb(rowSnap),
      categoryName: rowSnap?['category_name']?.toString() ??
          rowSnap?['category']?.toString(),
      subcategoryName: rowSnap?['subcategory_name']?.toString() ??
          rowSnap?['subcategory']?.toString(),
    );

    setState(() {
      if (name.isEmpty) {
        _errItem = 'Enter an item';
      } else if (catalogId == null || catalogId.isEmpty) {
        _errItem = 'Pick a catalog item from the list';
      } else {
        _errItem = null;
      }
      final unitLow = unit.toLowerCase();
      final fracPack = (unitLow == 'bag' ||
              unitLow == 'sack' ||
              unitLow == 'box' ||
              unitLow == 'tin') &&
          (qty - qty.roundToDouble()).abs() > 1e-6;
      _errQty = qty <= 0
          ? 'Quantity must be greater than zero'
          : fracPack
              ? 'Use a whole number for $unitLow lines (no decimals)'
              : null;
      if (_errQty == null &&
          _qtyEntryMode == 'kg' &&
          (unitLow == 'bag' || unitLow == 'sack')) {
        final k = _kgPer();
        final enteredKg = _enteredKgForBagMode();
        if (k != null && k > 0 && enteredKg != null && enteredKg > 0) {
          final bags = enteredKg / k;
          if (!_bagQtyIsWhole(bags)) {
            _errQty =
                'Kg must convert to a whole bag count. '
                'Use a multiple of ${_fmtQty(k)} kg.';
          }
        }
      }
      _errUnit = unit.isEmpty ? 'Unit is required' : null;
      _errKgPerBag = null;
      if (unitLow == 'bag' || unitLow == 'sack') {
        final k = _kgPer();
        if (k == null || k <= 0) {
          _errKgPerBag = 'Kg per bag required';
        }
      } else if (clf.type == UnitType.weightBag) {
        final k = _kgPer();
        _errKgPerBag = (k == null || k <= 0) ? 'Kg per bag required' : null;
      }
      if (_ratesPerKgEconomics) {
        _errLanding = rate <= 0
            ? (_rateFieldsPerKg
                ? 'Enter a purchase rate per kg greater than zero'
                : 'Enter a purchase rate per bag greater than zero')
            : null;
      } else {
        _errLanding =
            rate <= 0 ? 'Enter a purchase rate greater than zero' : null;
      }
      final sellT = _sellingCtrl.text.trim();
      if (sellT.isEmpty) {
        _errSelling = null;
      } else {
        final sv = _parseD(sellT);
        if (sv == null) {
          _errSelling = 'Enter a valid selling rate';
        } else if (sv < 0) {
          _errSelling = 'Selling rate cannot be negative';
        } else {
          _errSelling = null;
        }
      }
      final taxV = _parseD(_taxCtrl.text);
      final uLow = unit.toLowerCase();
      final needHsn = (taxV != null && taxV > 0) ||
          uLow == 'bag' ||
          clf.type == UnitType.weightBag;
      final hsn = _hsnCode?.trim() ?? '';
      _errHsn = (needHsn && hsn.isEmpty)
          ? 'HSN is required (from catalog) for taxed or bag lines'
          : null;
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
    if (_errHsn != null) {
      _scrollToKey(_taxKey);
      return null;
    }

    final disc = _parseD(_discCtrl.text);
    final tax = _parseD(_taxCtrl.text);
    final sellSt = _sellingCtrl.text.trim();

    final m = <String, dynamic>{
      if (_selectedCatalogItemId != null && _selectedCatalogItemId!.isNotEmpty) 'catalog_item_id': _selectedCatalogItemId,
      'item_name': name,
      'qty': qty,
      'unit': unit,
    };

    if (_ratesPerKgEconomics) {
      final kpu = _kgPer()!;
      m['kg_per_unit'] = kpu;
      m['landing_cost_per_kg'] = rate;
      m['landing_cost'] = kpu * rate;
    } else {
      m['landing_cost'] = rate;
      m['purchase_rate'] = rate;
    }
    if (_ratesPerKgEconomics) m['purchase_rate'] = m['landing_cost'];
    final unitLow = unit.toLowerCase();
    // [Bug 1 fix] Default wholesale mode: BOX/TIN are count-only — never write
    // weight fields, items_per_box, kg_per_box, weight_per_tin, or
    // weight_per_unit. The advanced inventory escape hatch is intentionally
    // off (_advancedInventoryEnabled = false in master rebuild).
    final isBoxOrTin = unitLow == 'box' || unitLow == 'tin';
    if (isBoxOrTin && _advancedInventoryEnabled) {
      if (unitLow == 'box') {
        if (clf.type == UnitType.multiPackBox || !_boxFixedWeight) {
          m['box_mode'] = 'items_per_box';
          final items = _parseD(_itemsPerBoxCtrl.text);
          final weight = _parseD(_weightPerItemCtrl.text);
          if (items != null) m['items_per_box'] = items;
          if (weight != null) m['weight_per_item'] = weight;
        } else if (clf.type == UnitType.singlePack) {
          final kg =
              _parseD(_kgPerBoxCtrl.text) ?? clf.kgFromName ?? _kgPer();
          if (kg != null && kg > 0) {
            m['box_mode'] = 'fixed_weight_box';
            m['kg_per_box'] = kg;
            m['weight_per_unit'] = kg;
          }
        } else {
          if (_boxFixedWeight) {
            m['box_mode'] = 'fixed_weight_box';
            final kg = _parseD(_kgPerBoxCtrl.text) ?? _kgPer();
            if (kg != null) {
              m['kg_per_box'] = kg;
              m['weight_per_unit'] = kg;
            }
          } else {
            m['box_mode'] = 'items_per_box';
            final items = _parseD(_itemsPerBoxCtrl.text);
            final weight = _parseD(_weightPerItemCtrl.text);
            if (items != null) m['items_per_box'] = items;
            if (weight != null) m['weight_per_item'] = weight;
          }
        }
      } else if (unitLow == 'tin') {
        final wt =
            _parseD(_weightPerTinCtrl.text) ?? clf.kgFromName ?? _kgPer();
        if (wt != null) {
          m['weight_per_tin'] = wt;
          m['weight_per_unit'] = wt;
        }
      }
    }
    // For default wholesale mode: do not emit kg_per_unit / weight_per_unit /
    // box_mode for box/tin. The line carries qty + purchase_rate only.
    if (isBoxOrTin && !_advancedInventoryEnabled) {
      m.remove('kg_per_unit');
      m.remove('weight_per_unit');
    }
    if (!widget.omitLineFreightDeliveredBilltyDiscount) {
      if (disc != null && disc > 0) m['discount'] = disc;
    }
    if (tax != null && tax > 0) m['tax_percent'] = tax;
    if (sellSt.isNotEmpty) {
      final sellParsed = _sellingParsedAsPerKg() ?? _parseD(sellSt)!;
      m['selling_cost'] = _sellingForPayloadForWire(sellParsed);
      m['selling_rate'] = m['selling_cost'];
    }
    if (!widget.omitLineFreightDeliveredBilltyDiscount) {
      m['freight_type'] = _freightType;
      final fv = _parseD(_freightCtrl.text);
      final dr = _parseD(_deliveredCtrl.text);
      final br = _parseD(_billtyCtrl.text);
      if (fv != null) m['freight_value'] = fv;
      if (dr != null) m['delivered_rate'] = dr;
      if (br != null) m['billty_rate'] = br;
    }
    final hOut = _hsnCode?.trim() ?? '';
    if (hOut.isNotEmpty) m['hsn_code'] = hOut;
    final icOut = _itemCode?.trim() ?? '';
    if (icOut.isNotEmpty) m['item_code'] = icOut;
    final note = _lineNotesCtrl.text.trim();
    if (note.isNotEmpty) m['description'] = note;
    return m;
  }

  void _resetAfterAdd() {
    setState(() {
      _itemCtrl.clear();
      _selectedCatalogItemId = null;
      _weightPricing = false;
      _kgPerUnit = null;
      _qtyCtrl.text = '1';
      _unitCtrl.text = 'kg';
      _landingCtrl.clear();
      _discCtrl.clear();
      _taxCtrl.clear();
      _sellingCtrl.clear();
      _kgPerBagCtrl.clear();
      _freightCtrl.clear();
      _deliveredCtrl.clear();
      _billtyCtrl.clear();
      _itemsPerBoxCtrl.clear();
      _weightPerItemCtrl.clear();
      _kgPerBoxCtrl.clear();
      _weightPerTinCtrl.clear();
      _freightType = 'separate';
      _boxFixedWeight = true;
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
      _errSelling = null;
      _errKgPerBag = null;
      _errHsn = null;
      _hsnCode = null;
      _itemCode = null;
      _lineNotesCtrl.clear();
      _lastPurchaseAutofillHint = null;
      _rateFieldsPerKg = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _itemFocus.requestFocus();
        _storeFieldBaseline();
      }
    });
  }

  void _commit({required bool closeSheet}) {
    final line = _validateAndBuildLine();
    if (line == null) return;
    widget.onCommitted(line);
    if (!widget.fullPage) {
      if (closeSheet) {
        if (context.canPop()) {
          context.pop();
        }
      } else {
        _resetAfterAdd();
      }
      return;
    }
    // Full-screen page: caller may chain another add via pop result.
    if (context.canPop()) {
      context.pop<bool>(!closeSheet);
    }
  }

  String _purchaseRateLabel(bool showPerKg) {
    if (widget.fullPage) {
      return showPerKg ? 'Purchase Rate (₹/kg) *' : 'Purchase Rate (₹/unit) *';
    }
    return showPerKg ? 'Landing cost (₹/kg) *' : 'Landing cost *';
  }

  String _sellingRateLabel(bool showPerKg) {
    if (widget.fullPage) {
      return showPerKg ? 'Selling Rate (₹/kg)' : 'Selling Rate (₹/unit)';
    }
    return showPerKg ? 'Selling price (₹/kg)' : 'Selling price';
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
    if (_selectedCatalogItemId == null || _selectedCatalogItemId!.isEmpty) return;
    final u0 = _unitCtrl.text.trim().toLowerCase();
    if (u0 != 'bag' && u0 != 'sack') return;
    final row = _catalogRowById(_selectedCatalogItemId!);
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

  void _onItemSelected(String id, String name) {
    if (id.isEmpty) return;
    _suppressCatalogTextUnlink = true;
    unawaited(
      _onCatalogPickAsync(InlineSearchItem(id: id, label: name)).whenComplete(() {
        if (mounted) _suppressCatalogTextUnlink = false;
      }),
    );
  }

  /// Seeds ₹/kg + bag totals from catalog default landing/selling vs [kg].
  void _applyBagKgFromCatalog(Map<String, dynamic> row, double kg) {
    _weightPricing = true;
    _kgPerUnit = kg;
    _kgPerBagCtrl.text = _fmtQty(kg);
    var perKg = 0.0;
    final lp = row['default_landing_cost'];
    final lpD = _numD(lp);
    if (lpD != null && lpD > 0) {
      perKg = StrictDecimal.fromObject(lpD)
          .divide(StrictDecimal.fromObject(kg), scale: 6)
          .toDouble();
    }
    _landingCtrl.text = perKg > 0 ? _fmtMoney(perKg) : '';
    final sc = row['default_selling_cost'];
    final scD = _numD(sc);
    if (scD != null) {
      _sellingCtrl.text = _fmtMoney(
        StrictDecimal.fromObject(scD)
            .divide(StrictDecimal.fromObject(kg), scale: 6)
            .toDouble(),
      );
    } else {
      _sellingCtrl.clear();
    }
  }

  /// Per-line-unit rates from catalog when not using bag ₹/kg snapshot.
  void _applyFlatUnitFromCatalog(Map<String, dynamic> row) {
    _weightPricing = false;
    _kgPerUnit = null;
    _kgPerBagCtrl.clear();
    var rate = 0.0;
    final lp = row['default_landing_cost'];
    final lpD = _numD(lp);
    if (lpD != null && lpD > 0) rate = lpD;
    _landingCtrl.text = rate > 0 ? _fmtMoney(rate) : '';
    final sc2 = row['default_selling_cost'];
    final scD = _numD(sc2);
    if (scD != null) {
      _sellingCtrl.text = _fmtMoney(scD);
    } else {
      _sellingCtrl.clear();
    }
  }

  /// Applies [row] only — no merge with a prior line (call after fresh fetch or list row).
  void _applyCatalogRowToLineState(
    Map<String, dynamic> row, {
    required String catalogId,
    required String nameFallback,
  }) {
    final name = (row['name']?.toString() ?? nameFallback).trim();
    final displayName = name.isNotEmpty ? name : nameFallback;
    final kpb = row['default_kg_per_bag'];
    final kpbD = kpb is num && kpb > 0 ? kpb.toDouble() : null;
    final catalogKpbFull = _catalogKpb(row);

    final classification = UnitClassifier.classify(
      itemName: displayName,
      lineUnit: '',
      catalogDefaultUnit: row['default_unit']?.toString(),
      catalogDefaultKgPerBag: catalogKpbFull,
      categoryName:
          row['category_name']?.toString() ?? row['category']?.toString(),
      subcategoryName: row['subcategory_name']?.toString() ??
          row['subcategory']?.toString(),
    );

    final wire = _wireUnitFromClassification(
      c: classification,
      row: row,
      kpbD: kpbD,
      displayName: displayName,
    );
    final uLowWire = wire.toLowerCase();

    final bool boxUsesItems = classification.type == UnitType.multiPackBox &&
        uLowWire == 'box';

    setState(() {
      _lastPurchaseAutofillHint = null;
      _selectedCatalogItemId = catalogId;
      _itemCtrl.text = displayName;
      _hsnCode = _hsnFromRow(row);
      _itemCode = _itemCodeFromRow(row);
      _unitCtrl.text = wire;

      if (uLowWire == 'box') {
        if (boxUsesItems) {
          _boxFixedWeight = false;
        } else {
          _boxFixedWeight = true;
        }
      }
      _unitDetectHint =
          _hintFromClassification(classification, wire.toLowerCase());

      if (classification.type == UnitType.weightBag) {
        final kg = kpbD ?? classification.kgFromName;
        if (kg != null && kg > 0) {
          _applyBagKgFromCatalog(row, kg);
        } else {
          _applyFlatUnitFromCatalog(row);
        }
      } else if (uLowWire == 'box') {
        _applyFlatUnitFromCatalog(row);
        _itemsPerBoxCtrl.clear();
        _weightPerItemCtrl.clear();
        if (boxUsesItems) {
          _kgPerBoxCtrl.clear();
        } else if (classification.kgFromName != null &&
            classification.kgFromName! > 0) {
          _kgPerBoxCtrl.text = _fmtQty(classification.kgFromName!);
        } else {
          _kgPerBoxCtrl.clear();
        }
      } else if (uLowWire == 'tin') {
        _applyFlatUnitFromCatalog(row);
        _kgPerBagCtrl.clear();
        _kgPerUnit = null;
        _weightPricing = false;
        _weightPerTinCtrl.clear();
        if (classification.kgFromName != null &&
            classification.kgFromName! > 0) {
          _weightPerTinCtrl.text = _fmtQty(classification.kgFromName!);
        }
      } else {
        if (kpbD != null && kpbD > 0) {
          _applyBagKgFromCatalog(row, kpbD);
        } else {
          _applyFlatUnitFromCatalog(row);
        }
      }

      final tax = _numD(row['tax_percent']);
      _taxCtrl.text =
          tax != null && tax > 0 ? StrictDecimal.fromObject(tax).format(2) : '';
      _errItem = null;
    });
  }

  String? _hintForLastPurchaseDefaults(Map<String, dynamic> d) {
    final src = d['source']?.toString();
    if (d.isEmpty || src == null || src == 'none') return null;
    final supplier = d['supplier_name']?.toString().trim();
    final dateRaw = d['purchase_date']?.toString().trim();
    final dateShort = (dateRaw != null && dateRaw.length >= 10)
        ? dateRaw.substring(0, 10)
        : dateRaw;
    final pr = _numD(d['purchase_rate'] ?? d['landing_cost']);
    final buf = StringBuffer('Filled from last purchase');
    if (pr != null && pr > 0) {
      buf.write(' · rate ₹');
      buf.write(pr.toStringAsFixed(2));
    }
    if (supplier != null && supplier.isNotEmpty) {
      buf.write(' · ');
      buf.write(supplier);
    }
    if (dateShort != null && dateShort.isNotEmpty) {
      buf.write(' · ');
      buf.write(dateShort);
    }
    buf.write('.');
    return buf.toString();
  }

  void _applyLastDefaults(Map<String, dynamic> d) {
    final src = d['source']?.toString();
    if (d.isEmpty || src == null || src == 'none') {
      if (mounted) {
        setState(() => _lastPurchaseAutofillHint = null);
      }
      return;
    }
    widget.onDefaultsResolved?.call(d);
    final unit = d['unit']?.toString().trim();
    final kpu = _numD(d['weight_per_unit'] ?? d['kg_per_unit']);
    final purchaseRate = _numD(d['purchase_rate'] ?? d['landing_cost']);
    final sellingRate = _numD(d['selling_rate'] ?? d['selling_cost']);
    final taxPercent = _numD(d['tax_percent']);
    final freight = _numD(d['freight_value'] ?? d['freight_amount']);
    final delivered = _numD(d['delivered_rate']);
    final billty = _numD(d['billty_rate']);
    final itemsPerBox = _numD(d['items_per_box']);
    final weightPerItem = _numD(d['weight_per_item']);
    final kgPerBox = _numD(d['kg_per_box']);
    final weightPerTin = _numD(d['weight_per_tin']);
    setState(() {
      if (unit != null && unit.isNotEmpty) {
        _unitCtrl.text = unit;
      }
      if (kpu != null && kpu > 0) {
        final u = _unitCtrl.text.trim().toLowerCase();
        if (u == 'box') {
          _kgPerBoxCtrl.text = _fmtQty(kpu);
          _weightPricing = false;
          _kgPerUnit = null;
          _kgPerBagCtrl.clear();
        } else if (u == 'tin') {
          _weightPerTinCtrl.text = _fmtQty(kpu);
          _weightPricing = false;
          _kgPerUnit = null;
          _kgPerBagCtrl.clear();
        } else {
          _weightPricing = true;
          _kgPerUnit = kpu;
          _kgPerBagCtrl.text = _fmtQty(kpu);
        }
      }
      if (taxPercent != null && taxPercent >= 0) {
        _taxCtrl.text =
            taxPercent > 0 ? StrictDecimal.fromObject(taxPercent).format(2) : '';
      }
      final ft = d['freight_type']?.toString();
      if (ft == 'included' || ft == 'separate') _freightType = ft!;
      if (freight != null && freight >= 0) _freightCtrl.text = _fmtMoney(freight);
      if (delivered != null && delivered >= 0) _deliveredCtrl.text = _fmtMoney(delivered);
      if (billty != null && billty >= 0) _billtyCtrl.text = _fmtMoney(billty);
      if (itemsPerBox != null && itemsPerBox > 0) _itemsPerBoxCtrl.text = _fmtQty(itemsPerBox);
      if (weightPerItem != null && weightPerItem > 0) _weightPerItemCtrl.text = _fmtQty(weightPerItem);
      if (kgPerBox != null && kgPerBox > 0) _kgPerBoxCtrl.text = _fmtQty(kgPerBox);
      if (weightPerTin != null && weightPerTin > 0) _weightPerTinCtrl.text = _fmtQty(weightPerTin);
      final bm = d['box_mode']?.toString();
      if (bm == 'items_per_box') {
        _boxFixedWeight = false;
      } else if (bm == 'fixed_weight_box') {
        _boxFixedWeight = true;
      } else {
        final rr = _rowForClassification();
        final bc = UnitClassifier.classify(
          itemName: _itemCtrl.text.trim(),
          lineUnit: _unitCtrl.text,
          catalogDefaultUnit: rr?['default_unit']?.toString(),
          catalogDefaultKgPerBag: _catalogKpb(rr),
          categoryName:
              rr?['category_name']?.toString() ?? rr?['category']?.toString(),
          subcategoryName: rr?['subcategory_name']?.toString() ??
              rr?['subcategory']?.toString(),
        );
        _adjustBoxFixedForClassification(bc);
      }
      final rr = _rowForClassification();
      final clfRates = UnitClassifier.classify(
        itemName: _itemCtrl.text.trim(),
        lineUnit: _unitCtrl.text,
        catalogDefaultUnit: rr?['default_unit']?.toString(),
        catalogDefaultKgPerBag: _catalogKpb(rr),
        categoryName:
            rr?['category_name']?.toString() ?? rr?['category']?.toString(),
        subcategoryName: rr?['subcategory_name']?.toString() ??
            rr?['subcategory']?.toString(),
      );
      final kEff = _kgPer();
      final lcpkApi = _numD(d['landing_cost_per_kg']);
      final isWeightBagRates =
          clfRates.type == UnitType.weightBag && kEff != null && kEff > 0;
      if (isWeightBagRates) {
        if (lcpkApi != null && lcpkApi > 0) {
          _rateFieldsPerKg = true;
          _landingCtrl.text = _fmtMoney(lcpkApi);
          if (sellingRate != null && sellingRate >= 0) {
            _sellingCtrl.text = _fmtMoney(sellingRate / kEff);
          }
        } else {
          _rateFieldsPerKg = false;
          if (purchaseRate != null && purchaseRate > 0) {
            _landingCtrl.text = _fmtMoney(purchaseRate);
          }
          if (sellingRate != null && sellingRate >= 0) {
            _sellingCtrl.text = _fmtMoney(sellingRate);
          }
        }
      } else {
        if (purchaseRate != null && purchaseRate > 0) {
          _landingCtrl.text = _fmtMoney(purchaseRate);
        }
        if (sellingRate != null && sellingRate >= 0) {
          _sellingCtrl.text = _fmtMoney(sellingRate);
        }
      }
      _lastPurchaseAutofillHint = _hintForLastPurchaseDefaults(d);
    });
  }

  void _scheduleLastDefaultsFetch(String catalogItemId, int seq) {
    _defaultsDebounceTimer?.cancel();
    final fetch = widget.resolveLastDefaults;
    if (fetch == null || widget.isEdit) return;
    _defaultsDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || seq != _catalogPickSeq) return;
      try {
        final defaults = await fetch(catalogItemId);
        if (!mounted || seq != _catalogPickSeq) return;
        _applyLastDefaults(defaults);
      } catch (_) {}
    });
  }

  Future<void> _onCatalogPickAsync(InlineSearchItem it) async {
    if (it.id.isEmpty) {
      _catalogPickSeq++;
      if (!mounted) return;
      setState(() {
        _selectedCatalogItemId = null;
        _weightPricing = false;
        _kgPerUnit = null;
        _kgPerBagCtrl.clear();
        _lastPurchaseAutofillHint = null;
        _unitDetectHint = null;
        _errItem = null;
        _hsnCode = null;
        _itemCode = null;
      });
      return;
    }

    final seq = ++_catalogPickSeq;

    // Id + visible label committed before catalog resolve/network.
    if (mounted) {
      setState(() {
        _selectedCatalogItemId = it.id;
        _itemCtrl.value = TextEditingValue(
          text: it.label,
          selection: TextSelection.collapsed(offset: it.label.length),
        );
        _errItem = null;
      });
    }

    Map<String, dynamic>? row = _catalogRowById(it.id);
    if (widget.resolveCatalogItem != null) {
      try {
        final fresh = await widget.resolveCatalogItem!(it.id);
        if (fresh.isNotEmpty && mounted) {
          setState(() {
            _catalogFetchById[it.id] = Map<String, dynamic>.from(fresh);
          });
          row = _catalogRowById(it.id);
        }
      } catch (_) {}
    }

    if (!mounted || seq != _catalogPickSeq) return;
    if (row == null) {
      final labelTrim = it.label.trim();
      final classification = UnitClassifier.classify(
        itemName: labelTrim,
        lineUnit: '',
        catalogDefaultUnit: null,
      );
      final wire = _wireUnitFromClassification(
        c: classification,
        row: null,
        kpbD: null,
        displayName: labelTrim,
      );
      final wLow = wire.toLowerCase();
      final boxItems = classification.type == UnitType.multiPackBox &&
          wLow == 'box';

      setState(() {
        _selectedCatalogItemId = it.id;
        _itemCtrl.text = it.label;
        _lastPurchaseAutofillHint = null;
        _errItem = null;
        _hsnCode = null;
        _itemCode = null;
        _taxCtrl.clear();
        _landingCtrl.clear();
        _sellingCtrl.clear();

        _unitCtrl.text = wire;
        if (wLow == 'box') {
          _itemsPerBoxCtrl.clear();
          _weightPerItemCtrl.clear();
          if (boxItems) {
            _boxFixedWeight = false;
            _kgPerBoxCtrl.clear();
          } else {
            _boxFixedWeight = true;
            if (classification.kgFromName != null &&
                classification.kgFromName! > 0) {
              _kgPerBoxCtrl.text = _fmtQty(classification.kgFromName!);
            } else {
              _kgPerBoxCtrl.clear();
            }
          }
        } else if (wLow != 'tin') {
          _kgPerBoxCtrl.clear();
        }
        if (wLow != 'box') {
          _itemsPerBoxCtrl.clear();
          _weightPerItemCtrl.clear();
        }
        if (wLow == 'tin') {
          _weightPerTinCtrl.clear();
          _boxFixedWeight = true;
          if (classification.kgFromName != null &&
              classification.kgFromName! > 0) {
            _weightPerTinCtrl.text = _fmtQty(classification.kgFromName!);
          }
        } else if (wLow != 'box') {
          _weightPerTinCtrl.clear();
        }

        if (classification.type == UnitType.weightBag &&
            classification.kgFromName != null &&
            classification.kgFromName! > 0) {
          _weightPricing = true;
          _kgPerUnit = classification.kgFromName;
          _kgPerBagCtrl.text = _fmtQty(classification.kgFromName!);
        } else {
          _weightPricing = false;
          _kgPerUnit = null;
          _kgPerBagCtrl.clear();
        }

        _unitDetectHint =
            _hintFromClassification(classification, wLow);
      });
      _scheduleLastDefaultsFetch(it.id, seq);
      return;
    }
    _applyCatalogRowToLineState(
      row,
      catalogId: it.id,
      nameFallback: it.label,
    );
    _scheduleLastDefaultsFetch(it.id, seq);
  }

  /// Line preview: qty + unit + total weight, then rates and profit.
  Widget _liveTotalsCard(ThemeData theme) {
    final total = _lineTotalPreview();
    final sell = _ratesPerKgEconomics
        ? _sellingParsedAsPerKg()
        : _parseD(_sellingCtrl.text);
    final profit = _profitPreview();
    final k = _kgPer();
    final q = _qtyVal();
    final u = _unitCtrl.text.trim();

    final per = _ratesPerKgEconomics
        ? (_landingParsedAsPerKg() ?? 0)
        : (_parseD(_landingCtrl.text) ?? 0);

    final lines = <Widget>[
      Text(
        _qtyAndUnitWeightSummaryLine(),
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.25,
          color: Colors.blueGrey[900],
        ),
      ),
      const SizedBox(height: 6),
    ];

    if (_showPerKgLandingLabels) {
      if (k != null && k > 0 && q > 0) {
        final totalK = q * k;
        lines.add(Text(
          '${_inQtyWtFmt.format(q)} × ${_fmtQty(k)} kg/bag = ${_inQtyWtFmt.format(totalK)} kg',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: Colors.blueGrey[800],
          ),
        ));
        lines.add(Text(
          '${_inQtyWtFmt.format(totalK)} kg × ₹${per.toStringAsFixed(2)}/kg → ₹${total.toStringAsFixed(2)}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ));
      } else if (_activeClassification().type == UnitType.weightBag) {
        lines.add(Text(
          'Enter kg per bag',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[700],
          ),
        ));
      }
    }
    if (!_showPerKgLandingLabels) {
      lines.add(Text(
        '${_inQtyWtFmt.format(q)} ${_capitalUnitWord(u.isEmpty ? 'unit' : u)} × ₹${per.toStringAsFixed(2)} = ₹${total.toStringAsFixed(2)}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ));
    }

    lines.add(const SizedBox(height: 4));
    lines.add(Text(
      sell == null ? 'Profit —' : 'Profit ₹${profit.toStringAsFixed(2)}',
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
        color: widget.fullPage
            ? const Color(0xFFF0FDFD)
            : Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(widget.fullPage ? 12 : 6),
        border: Border.all(
          color: widget.fullPage
              ? const Color(0xFF17A8A7).withValues(alpha: 0.35)
              : Colors.blueGrey[100]!,
        ),
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
    final k = _kgPer();
    final cRow = _activeClassification();
    final showPerKgFields = _showPerKgLandingLabels;
    final showManualKgField =
        cRow.type == UnitType.weightBag && !_hasCatalogKg();
    final unitLow = _unitCtrl.text.trim().toLowerCase();
    // Compact, stable fields — Tally-style density.
    final sheetTheme = theme.copyWith(visualDensity: VisualDensity.compact);

    const teal = Color(0xFF17A8A7);
    const ink = Color(0xFF0F172A);
    final gapField = widget.fullPage ? 16.0 : 6.0;
    final gapSection = widget.fullPage ? 24.0 : 8.0;
    final rateBasisSeg = _rateEntryBasisSegmented(k, showPerKgFields);

    final formChildren = <Widget>[
      if (!widget.fullPage) ...[
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
        const SizedBox(height: 4),
        Text(
          'Catalog, qty, rate first. Use Discount / Tax for HSN and bag rules.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.blueGrey[700],
            fontSize: 12,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
      ],
      KeyedSubtree(
        key: _itemKey,
        child: _fpShell(
          PartyInlineSuggestField(
            controller: _itemCtrl,
            focusNode: _itemFocus,
            focusAfterSelection: _qtyFocus,
            debugLabel: 'catalogItem',
            hintText: 'Search item (name, code, HSN)…',
            prefixIcon: const Icon(Icons.inventory_2_outlined),
            minQueryLength: 1,
            maxMatches: 8,
            dense: true,
            minFieldHeight: widget.fullPage ? 52 : 0,
            suggestionsAsOverlay: widget.fullPage,
            items: _catalogSearchItems,
            textInputAction: TextInputAction.next,
            onSubmitted: () =>
                FocusScope.of(context).requestFocus(_qtyFocus),
            showAddRow: widget.navigateCatalogQuickAddItem != null,
            addRowLabel: 'New catalog item…',
            onAddRow: widget.navigateCatalogQuickAddItem == null
                ? null
                : () async {
                    final r = await widget.navigateCatalogQuickAddItem!();
                    if (r != null && mounted) {
                      final id = r['id']?.toString() ?? '';
                      final nm = r['name']?.toString() ?? '';
                      if (id.isNotEmpty) _onItemSelected(id, nm);
                    }
                  },
            onSelected: (it) {
              _onItemSelected(it.id, it.label);
            },
          ),
        ),
      ),
              if (_errItem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2),
                  child: Text(_errItem!, style: TextStyle(color: Colors.red[800], fontSize: 11)),
                ),
              if (_lastPurchaseAutofillHint != null &&
                  _lastPurchaseAutofillHint!.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2),
                  child: Text(
                    _lastPurchaseAutofillHint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.blueGrey[700],
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
              if (_unitDetectHint != null && _unitDetectHint!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2),
                  child: Text(
                    _unitDetectHint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: teal,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
              SizedBox(height: gapField),
              if (widget.fullPage)
                _fpShell(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: KeyedSubtree(
                          key: _qtyKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_qtyEntryModeSegmented() != null)
                                _qtyEntryModeSegmented()!,
                              TextField(
                                controller: _qtyCtrl,
                                focusNode: _qtyFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [_decimalFormatter(3)],
                                textInputAction: TextInputAction.next,
                                decoration: _deco(_qtyFieldLabel(),
                                    errorText: _errQty),
                                onChanged: (_) {
                                  _clearFieldErrors();
                                  _schedulePreviewRebuild();
                                },
                                onSubmitted: (_) {
                                  if (showManualKgField) {
                                    FocusScope.of(context)
                                        .requestFocus(_kgManualFocus);
                                  } else {
                                    FocusScope.of(context)
                                        .requestFocus(_landingFocus);
                                  }
                                },
                              ),
                              if (_kgEntryConversionHint() != null) ...[
                                SizedBox(height: gapField * 0.6),
                                _kgEntryConversionHint()!,
                              ],
                            ],
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
                                  decoration:
                                      _deco('Unit *', errorText: _errUnit),
                                  child: Text(
                                    '${_unitCtrl.text.trim()} (${_fmtQty(k ?? 0)} kg)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              : _unitDropdownField(errorText: _errUnit),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: KeyedSubtree(
                        key: _qtyKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_qtyEntryModeSegmented() != null)
                              _qtyEntryModeSegmented()!,
                            TextField(
                              controller: _qtyCtrl,
                              focusNode: _qtyFocus,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [_decimalFormatter(3)],
                              textInputAction: TextInputAction.next,
                              decoration:
                                  _deco(_qtyFieldLabel(), errorText: _errQty),
                              onChanged: (_) {
                                _clearFieldErrors();
                                _schedulePreviewRebuild();
                              },
                              onSubmitted: (_) {
                                if (showManualKgField) {
                                  FocusScope.of(context)
                                      .requestFocus(_kgManualFocus);
                                } else {
                                  FocusScope.of(context)
                                      .requestFocus(_landingFocus);
                                }
                              },
                            ),
                            if (_kgEntryConversionHint() != null) ...[
                              SizedBox(height: gapField * 0.6),
                              _kgEntryConversionHint()!,
                            ],
                          ],
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
                                decoration:
                                    _deco('Unit *', errorText: _errUnit),
                                child: Text(
                                  '${_unitCtrl.text.trim()} (${_fmtQty(k ?? 0)} kg)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : _unitDropdownField(errorText: _errUnit),
                      ),
                    ),
                  ],
                ),
              ListenableBuilder(
                listenable: _lineTotalsListenable,
                builder: (cx, _) {
                  final chips = <Widget>[
                    for (final w in [
                      _nameImpliesBagButKgUnitBanner(),
                      _suggestOneBagInsteadOfKgBanner(),
                      _didYouMeanKgNotBagsBanner(),
                    ])
                      if (w != null) w,
                  ];
                  if (chips.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: EdgeInsets.only(top: gapField * 0.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < chips.length; i++) ...[
                          if (i > 0) SizedBox(height: gapField * 0.35),
                          chips[i],
                        ],
                      ],
                    ),
                  );
                },
              ),
              if (showManualKgField) ...[
                SizedBox(height: gapField),
                KeyedSubtree(
                  key: _kgPerBagKey,
                  child: TextField(
                    controller: _kgPerBagCtrl,
                    focusNode: _kgManualFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_decimalFormatter(3)],
                    textInputAction: TextInputAction.next,
                    decoration: _deco('Kg per bag *', errorText: _errKgPerBag),
                    onSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_landingFocus);
                    },
                  ),
                ),
              ],
              if (_advancedInventoryEnabled && unitLow == 'box') ...[
                SizedBox(height: gapField),
                if (!(cRow.type == UnitType.singlePack ||
                    cRow.type == UnitType.multiPackBox))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Fixed kg')),
                        ButtonSegment(value: false, label: Text('Items/box')),
                      ],
                      selected: {_boxFixedWeight},
                      onSelectionChanged: (s) {
                        setState(() => _boxFixedWeight = s.first);
                      },
                    ),
                  ),
                if (cRow.type == UnitType.multiPackBox)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _itemsPerBoxCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_decimalFormatter(3)],
                          decoration: _deco(
                            'Items per box *',
                            errorText: _errKgPerBag,
                          ),
                          onChanged: (_) => _schedulePreviewRebuild(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _weightPerItemCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_decimalFormatter(3)],
                          decoration: _deco(
                            'Kg per item',
                            errorText: _errKgPerBag,
                          ),
                          onChanged: (_) => _schedulePreviewRebuild(),
                        ),
                      ),
                    ],
                  )
                else if (cRow.type == UnitType.singlePack)
                  TextField(
                    controller: _kgPerBoxCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_decimalFormatter(3)],
                    decoration: _deco(
                      'Kg per box',
                      errorText: _errKgPerBag,
                    ),
                    onChanged: (_) => _schedulePreviewRebuild(),
                  )
                else ...[
                  if (_boxFixedWeight)
                    TextField(
                      controller: _kgPerBoxCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimalFormatter(3)],
                      decoration:
                          _deco('Kg per box *', errorText: _errKgPerBag),
                      onChanged: (_) => _schedulePreviewRebuild(),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _itemsPerBoxCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            inputFormatters: [_decimalFormatter(3)],
                            decoration: _deco(
                              'Items per box *',
                              errorText: _errKgPerBag,
                            ),
                            onChanged: (_) => _schedulePreviewRebuild(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _weightPerItemCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            inputFormatters: [_decimalFormatter(3)],
                            decoration: _deco(
                              'Kg per item *',
                              errorText: _errKgPerBag,
                            ),
                            onChanged: (_) => _schedulePreviewRebuild(),
                          ),
                        ),
                      ],
                    ),
                ],
              ],
              if (_advancedInventoryEnabled && unitLow == 'tin') ...[
                SizedBox(height: gapField),
                TextField(
                  controller: _weightPerTinCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_decimalFormatter(3)],
                  decoration: _deco('Weight per tin *', errorText: _errKgPerBag),
                  onChanged: (_) => _schedulePreviewRebuild(),
                ),
              ],
              SizedBox(height: gapField),
              if (widget.fullPage)
                _fpShell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rateBasisSeg != null) rateBasisSeg,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: KeyedSubtree(
                              key: _landingKey,
                              child: TextField(
                                controller: _landingCtrl,
                                focusNode: _landingFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [_decimalFormatter(2)],
                                textInputAction: TextInputAction.next,
                                decoration: _deco(
                                  _purchaseRateLabel(showPerKgFields),
                                  prefixText: '₹ ',
                                  errorText: _errLanding,
                                ),
                                onChanged: (_) {
                                  _clearFieldErrors();
                                  _schedulePreviewRebuild();
                                },
                                onSubmitted: (_) {
                                  FocusScope.of(context)
                                      .requestFocus(_sellingFocus);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 5,
                            child: KeyedSubtree(
                              key: _sellingKey,
                              child: TextField(
                                controller: _sellingCtrl,
                                focusNode: _sellingFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [_decimalFormatter(2)],
                                textInputAction: TextInputAction.done,
                                decoration: _deco(
                                  _sellingRateLabel(showPerKgFields),
                                  prefixText: '₹ ',
                                  errorText: _errSelling,
                                ),
                                onChanged: (_) {
                                  _clearFieldErrors();
                                  _schedulePreviewRebuild();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else ...[
                if (rateBasisSeg != null) rateBasisSeg,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: KeyedSubtree(
                        key: _landingKey,
                        child: TextField(
                          controller: _landingCtrl,
                          focusNode: _landingFocus,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          inputFormatters: [_decimalFormatter(2)],
                          textInputAction: TextInputAction.next,
                          decoration: _deco(
                            _purchaseRateLabel(showPerKgFields),
                            prefixText: '₹ ',
                            errorText: _errLanding,
                          ),
                          onChanged: (_) {
                            _clearFieldErrors();
                            _schedulePreviewRebuild();
                          },
                          onSubmitted: (_) {
                            FocusScope.of(context)
                                .requestFocus(_sellingFocus);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: KeyedSubtree(
                        key: _sellingKey,
                        child: TextField(
                          controller: _sellingCtrl,
                          focusNode: _sellingFocus,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          inputFormatters: [_decimalFormatter(2)],
                          textInputAction: TextInputAction.done,
                          decoration: _deco(
                            _sellingRateLabel(showPerKgFields),
                            prefixText: '₹ ',
                            errorText: _errSelling,
                          ),
                          onChanged: (_) {
                            _clearFieldErrors();
                            _schedulePreviewRebuild();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: widget.fullPage ? gapSection : 2),
              KeyedSubtree(
                key: _taxKey,
                child: _fpShell(
                  Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                    title: Text(
                      'Advanced',
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
                      if (widget.omitLineFreightDeliveredBilltyDiscount) ...[
                        TextField(
                          controller: _taxCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_decimalFormatter(2)],
                          scrollPadding: const EdgeInsets.only(bottom: 220),
                          decoration: _deco('Tax %'),
                          onChanged: (_) {
                            _clearFieldErrors();
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _lineNotesCtrl,
                          maxLines: 4,
                          minLines: 1,
                          scrollPadding: const EdgeInsets.only(bottom: 220),
                          decoration: _deco('Notes'),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _discCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [_decimalFormatter(2)],
                                scrollPadding: const EdgeInsets.only(bottom: 220),
                                decoration: _deco('Discount %'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _taxCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [_decimalFormatter(2)],
                                scrollPadding: const EdgeInsets.only(bottom: 220),
                                decoration: _deco('Tax %'),
                                onChanged: (_) {
                                  _clearFieldErrors();
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _freightCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [_decimalFormatter(2)],
                                scrollPadding: const EdgeInsets.only(bottom: 220),
                                decoration: _deco('Freight value'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InputDecorator(
                                decoration: _deco('Freight type'),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _freightType,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(value: 'separate', child: Text('Separate')),
                                      DropdownMenuItem(value: 'included', child: Text('Included')),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _freightType = v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _deliveredCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [_decimalFormatter(2)],
                                scrollPadding: const EdgeInsets.only(bottom: 220),
                                decoration: _deco('Delivered rate'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _billtyCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [_decimalFormatter(2)],
                                scrollPadding: const EdgeInsets.only(bottom: 220),
                                decoration: _deco('Billty rate'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _lineNotesCtrl,
                          maxLines: 4,
                          minLines: 1,
                          scrollPadding: const EdgeInsets.only(bottom: 220),
                          decoration: _deco('Notes'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
              ListenableBuilder(
                listenable: _lineTotalsListenable,
                builder: (cx, _) {
                  final showMeta = _showHsnFooterMeta();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errHsn != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _errHsn!,
                          style: TextStyle(
                            color: Colors.red[800],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (showMeta && _hsnCode != null && _hsnCode!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'HSN: ${_hsnCode!}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.blueGrey[800],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (showMeta && _itemCode != null && _itemCode!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Item code: ${_itemCode!}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.blueGrey[800],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              SizedBox(height: widget.fullPage ? gapField : 4),
              ListenableBuilder(
                listenable: _lineTotalsListenable,
                builder: (context, _) => widget.fullPage
                    ? _fpShell(_liveTotalsCard(theme))
                    : _liveTotalsCard(theme),
              ),
            ];

    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final homeBottomInset = MediaQuery.paddingOf(context).bottom;

    if (widget.fullPage) {
      final footerPad = const EdgeInsets.fromLTRB(0, 6, 0, 10);
      final footer = widget.isEdit
          ? Padding(
              padding: footerPad,
              child: FilledButton(
                onPressed: () => _commit(closeSheet: true),
                style: FilledButton.styleFrom(
                  backgroundColor: teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          : Padding(
              padding: footerPad,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _commit(closeSheet: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: teal,
                        side: const BorderSide(color: teal),
                        minimumSize: const Size(double.infinity, 50),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: const Text('Save & add more'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _commit(closeSheet: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: teal,
                        minimumSize: const Size(double.infinity, 50),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );

      return Theme(
        data: sheetTheme,
        child: PopScope(
          canPop: !_isDirtySheet(),
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            await _confirmDiscardAndPop();
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: ink,
              elevation: 0,
              title: Text(widget.isEdit ? 'Edit item' : 'Add item'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: _handleLeadingBack,
              ),
            ),
            body: LayoutBuilder(
              builder: (context, c) {
                final minFields = math.max(200.0, c.maxHeight - 260);
                return KeyboardSafeFormViewport(
                  dismissKeyboardOnTap: true,
                  scrollController: _scrollController,
                  horizontalPadding: 16,
                  topPadding: 4,
                  bottomExtraInset: 32,
                  minFieldsHeight:
                      c.hasBoundedHeight ? minFields : 200,
                  fields: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: formChildren,
                  ),
                  footer: footer,
                );
              },
            ),
          ),
        ),
      );
    }

    final footer = widget.isEdit
        ? FilledButton(
            onPressed: () => _commit(closeSheet: true),
            style: FilledButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          )
        : Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _commit(closeSheet: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: teal,
                    side: const BorderSide(color: teal),
                    minimumSize: const Size(double.infinity, 48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  child: const Text(
                    'Add more',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _commit(closeSheet: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          );

    return Theme(
      data: sheetTheme,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: LayoutBuilder(
          builder: (context, c) {
            final minFields = math.max(200.0, c.maxHeight - 220);
            return KeyboardSafeFormViewport(
              dismissKeyboardOnTap: true,
              scrollController: _scrollController,
              horizontalPadding: 10,
              topPadding: 4,
              bottomExtraInset: 12,
              minFieldsHeight: c.hasBoundedHeight ? minFields : 200,
              fields: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: formChildren,
              ),
              footer: Padding(
                padding: EdgeInsets.only(
                  left: 10,
                  right: 10,
                  top: 8,
                  bottom: (keyboardBottom > 0 ? keyboardBottom : homeBottomInset) + 10,
                ),
                child: footer,
              ),
            );
          },
        ),
      ),
    );
  }
}
