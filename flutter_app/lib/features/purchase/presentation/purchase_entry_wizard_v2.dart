import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/fastapi_error.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/calc_engine.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateBusinessAggregates, invalidateWorkspaceSeedData;
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/inline_search_field.dart';
import 'widgets/purchase_item_entry_sheet.dart';
import 'widgets/purchase_saved_sheet.dart';

double _wizLineGross(TradeCalcLine li) => li.qty * li.landingCost;

double _wizLineAfterLineDisc(TradeCalcLine li) {
  final base = _wizLineGross(li);
  final ld = li.discountPercent != null ? li.discountPercent! : 0.0;
  final d = ld > 100 ? 100.0 : ld;
  return base * (1.0 - d / 100.0);
}

double _wizLineTaxAmount(TradeCalcLine li) {
  final ad = _wizLineAfterLineDisc(li);
  final tax = li.taxPercent != null ? li.taxPercent! : 0.0;
  final t = tax > 1000 ? 1000.0 : tax;
  return ad * (t / 100.0);
}

class PurchaseEntryWizardV2 extends ConsumerStatefulWidget {
  const PurchaseEntryWizardV2({
    super.key,
    this.editingId,
    this.initialCatalogItemId,
  });

  final String? editingId;
  /// Deep-link from catalog: pre-fill the inline draft row.
  final String? initialCatalogItemId;

  @override
  ConsumerState<PurchaseEntryWizardV2> createState() => _PurchaseEntryWizardV2State();
}

class _PurchaseEntryWizardV2State extends ConsumerState<PurchaseEntryWizardV2> {
  String? _supplierId;
  String? _supplierName;
  String? _brokerId;
  DateTime _purchaseDate = DateTime.now();

  final List<Map<String, dynamic>> _items = [];

  String? _supplierFieldError;
  /// Line / empty-cart validation shown above the item list.
  String? _saveFormError;

  bool _isSaving = false;
  bool _isBootstrapping = false;

  String? _previewHumanId;
  String? _editHumanId;
  String? _brokerIdFromSupplier;
  bool _formDirty = false;
  Timer? _draftDebounce;

  /// Shown on edit — payment snapshot from server.
  String? _loadedDerivedStatus;
  double? _loadedRemaining;

  final _addItemFocusNode = FocusNode();
  final ScrollController _bodyScrollController = ScrollController();
  final GlobalKey _supplierSectionKey = GlobalKey();
  final GlobalKey _termsSectionKey = GlobalKey();
  final GlobalKey _addItemSectionKey = GlobalKey();
  final List<GlobalKey> _lineScrollKeys = [];

  /// Last good supplier list — keeps search field mounted when provider reloads (AsyncLoading).
  List<Map<String, dynamic>>? _lastGoodSuppliersList;
  bool _triedEmptyCatalogBootstrap = false;
  bool _catalogLinePrefillOpened = false;

  final _supplierCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();

  final _paymentDaysCtrl = TextEditingController();
  final _headerDiscCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _deliveredRateCtrl = TextEditingController();
  final _billtyRateCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();
  String _freightType = 'separate';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadEdit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _prefetchNextHumanId();
      if (!mounted) return;
      await _maybeRestoreDraft();
      if (!mounted) return;
      await _openCatalogLinePrefillIfNeeded();
      if (!mounted) return;
      await _ensureCatalogSeedIfEmpty();
    });
  }

  /// If catalog is empty after login, run idempotent bootstrap once and refresh seed providers.
  Future<void> _ensureCatalogSeedIfEmpty() async {
    if (_triedEmptyCatalogBootstrap) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final catalog = await ref.read(catalogItemsListProvider.future);
      if (!mounted) return;
      if (catalog.isNotEmpty) return;
      _triedEmptyCatalogBootstrap = true;
      await ref.read(hexaApiProvider).bootstrapWorkspace();
      if (!mounted) return;
      invalidateWorkspaceSeedData(ref);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(suppliersListProvider);
    } catch (_) {
      _triedEmptyCatalogBootstrap = true;
    }
  }

  /// After supplier is set (purchase.md), open the line sheet for catalog deep-link.
  Future<void> _openCatalogLinePrefillIfNeeded() async {
    final cid = widget.initialCatalogItemId;
    if (cid == null || cid.isEmpty) return;
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    if (_catalogLinePrefillOpened) return;
    if (!_headerComplete) return;
    if (_items.isNotEmpty) return;
    _catalogLinePrefillOpened = true;
    try {
      final catalog = await ref.read(catalogItemsListProvider.future);
      if (!mounted) return;
      final row = _catalogRowById(catalog, cid);
      if (row == null) return;
      final label = row['name']?.toString() ?? '';
      final unit = row['default_purchase_unit']?.toString() ??
          row['default_unit']?.toString() ??
          'kg';
      var rate = 0.0;
      final lp = row['default_landing_cost'];
      if (lp is num && lp > 0) rate = lp.toDouble();
      final tax = row['tax_percent'];
      final initial = <String, dynamic>{
        'catalog_item_id': cid,
        'item_name': label,
        'qty': 1.0,
        'unit': unit,
        'landing_cost': rate,
        if (tax is num && tax > 0) 'tax_percent': tax.toDouble(),
      };
      if (!mounted) return;
      await _openItemSheet(catalog, initialOverride: initial);
    } catch (_) {}
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    if (widget.editingId == null || widget.editingId!.isEmpty) {
      // Read [ref] and prefs synchronously: async [Future]s run after [super.dispose] and
      // [ConsumerState.ref] is no longer valid.
      final s = ref.read(sessionProvider);
      if (s != null) {
        final k = '${_draftKeyV1}_${s.primaryBusiness.id}';
        final p = ref.read(sharedPreferencesProvider);
        final json = jsonEncode(_collectDraftMap());
        unawaited(p.setString(k, json));
      }
    }
    _bodyScrollController.dispose();
    _supplierCtrl.dispose();
    _invoiceCtrl.dispose();
    _paymentDaysCtrl.dispose();
    _headerDiscCtrl.dispose();
    _commissionCtrl.dispose();
    _deliveredRateCtrl.dispose();
    _billtyRateCtrl.dispose();
    _freightCtrl.dispose();
    _addItemFocusNode.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadEdit() async {
    final id = widget.editingId;
    if (id == null || id.isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _isBootstrapping = true);
    try {
      final raw = await ref.read(hexaApiProvider).getTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: id,
          );
      if (!mounted) return;
      final pd = raw['purchase_date']?.toString();
      if (pd != null && pd.isNotEmpty) {
        final d = DateTime.tryParse(pd);
        if (d != null) _purchaseDate = d;
      }
      _supplierId = raw['supplier_id']?.toString();
      _supplierName = raw['supplier_name']?.toString();
      if (_supplierName != null && _supplierName!.isNotEmpty) {
        _supplierCtrl.text = _supplierName!;
      }
      _brokerId = raw['broker_id']?.toString();
      _brokerIdFromSupplier = _brokerId;
      final invn = raw['invoice_number']?.toString();
      if (invn != null && invn.isNotEmpty) {
        _invoiceCtrl.text = invn;
      }
      _editHumanId = raw['human_id']?.toString();
      _loadedDerivedStatus = raw['derived_status']?.toString();
      _loadedRemaining = (raw['remaining'] as num?)?.toDouble();
      final pay = raw['payment_days'];
      _paymentDaysCtrl.text = pay is num ? pay.toString() : '';
      final disc = raw['discount'];
      _headerDiscCtrl.text = disc is num ? disc.toString() : '';
      final comm = raw['commission_percent'];
      _commissionCtrl.text = comm is num ? comm.toString() : '';
      final dr = raw['delivered_rate'];
      _deliveredRateCtrl.text = dr is num ? dr.toString() : '';
      final br = raw['billty_rate'];
      _billtyRateCtrl.text = br is num ? br.toString() : '';
      final fa = raw['freight_amount'];
      _freightCtrl.text = fa is num ? fa.toString() : '';
      final ft = raw['freight_type']?.toString();
      if (ft == 'included' || ft == 'separate') _freightType = ft!;

      _items.clear();
      final lines = raw['lines'];
      if (lines is List) {
        for (final e in lines) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          _items.add({
            'catalog_item_id': m['catalog_item_id']?.toString(),
            'item_name': m['item_name']?.toString() ?? '',
            'qty': (m['qty'] as num?)?.toDouble() ?? 0,
            'unit': m['unit']?.toString() ?? 'kg',
            'landing_cost': (m['landing_cost'] as num?)?.toDouble() ?? 0,
            if (m['selling_cost'] != null) 'selling_cost': (m['selling_cost'] as num?)?.toDouble(),
            if (m['tax_percent'] != null) 'tax_percent': (m['tax_percent'] as num?)?.toDouble(),
            if (m['discount'] != null) 'discount': (m['discount'] as num?)?.toDouble(),
          });
        }
      }
      _rebuildLineKeys();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load purchase: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBootstrapping = false);
    }
  }

  double? _parseOptionalPercent(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  double? _parseOptionalAmount(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String _duePreviewText() {
    final pd = int.tryParse(_paymentDaysCtrl.text.trim());
    if (pd == null || pd < 0) return 'Due: —';
    final d = _purchaseDate.add(Duration(days: pd));
    return 'Due: ${DateFormat('dd MMM yyyy').format(d)}';
  }

  TradeCalcTotals _computeTotals() {
    return computeTradeTotals(
      TradeCalcRequest(
        headerDiscountPercent: _parseOptionalPercent(_headerDiscCtrl),
        commissionPercent: _parseOptionalPercent(_commissionCtrl),
        freightAmount: _parseOptionalAmount(_freightCtrl),
        freightType: _freightType,
        lines: [
          for (final item in _items)
            TradeCalcLine(
              qty: (item['qty'] as num?)?.toDouble() ?? 0,
              landingCost: (item['landing_cost'] as num?)?.toDouble() ?? 0,
              taxPercent: (item['tax_percent'] as num?)?.toDouble(),
              discountPercent: (item['discount'] as num?)?.toDouble(),
            ),
        ],
      ),
    );
  }

  /// Strict invoice-style breakdown (separate Subtotal / Tax / Discount rows).
  ({
    double subtotalGross,
    double taxTotal,
    double discountTotal,
    double freight,
    double commission,
    double grand,
  }) _strictFooterBreakdown(TradeCalcTotals totals) {
    var subtotalGross = 0.0;
    var lineDiscountTotal = 0.0;
    var taxTotal = 0.0;
    var linesTotal = 0.0;
    for (final item in _items) {
      final li = TradeCalcLine(
        qty: (item['qty'] as num?)?.toDouble() ?? 0,
        landingCost: (item['landing_cost'] as num?)?.toDouble() ?? 0,
        taxPercent: (item['tax_percent'] as num?)?.toDouble(),
        discountPercent: (item['discount'] as num?)?.toDouble(),
      );
      final g = _wizLineGross(li);
      final ad = _wizLineAfterLineDisc(li);
      subtotalGross += g;
      lineDiscountTotal += (g - ad);
      taxTotal += _wizLineTaxAmount(li);
      linesTotal += lineMoney(li);
    }
    final headerDisc = _parseOptionalPercent(_headerDiscCtrl) ?? 0.0;
    final hd = headerDisc > 100 ? 100.0 : headerDisc;
    final afterHeader = linesTotal * (1.0 - hd / 100.0);
    final headerDiscountAmt = linesTotal - afterHeader;
    final discountTotal = lineDiscountTotal + headerDiscountAmt;
    var freight = _parseOptionalAmount(_freightCtrl) ?? 0.0;
    if (_freightType == 'included') freight = 0.0;
    final comm = _parseOptionalPercent(_commissionCtrl) ?? 0.0;
    final c = comm > 100 ? 100.0 : comm;
    final commission = comm > 0 ? afterHeader * c / 100.0 : 0.0;
    return (
      subtotalGross: subtotalGross,
      taxTotal: taxTotal,
      discountTotal: discountTotal,
      freight: freight,
      commission: commission,
      grand: totals.amountSum,
    );
  }

  void _rebuildLineKeys() {
    _lineScrollKeys
      ..clear()
      ..addAll(List.generate(_items.length, (_) => GlobalKey()));
  }

  /// purchase.md: supplier required before add/save; edit flow needs supplier from server.
  bool get _headerComplete {
    final sid = _supplierId;
    return sid != null && sid.isNotEmpty;
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: Duration.zero,
        curve: Curves.linear,
      );
    });
  }

  /// Atomic supplier pick: controller, ids, and supplier defaults in one [setState] (purchase.md §1).
  void _applySupplierSelection(
    List<Map<String, dynamic>> list,
    InlineSearchItem it,
  ) {
    Map<String, dynamic>? row;
    for (final m in list) {
      if (m['id']?.toString() == it.id) {
        row = m;
        break;
      }
    }
    setState(() {
      _supplierId = it.id;
      _supplierName = it.label;
      _supplierCtrl.text = it.label;
      _supplierFieldError = null;
      _saveFormError = null;
      if (row == null) return;
      final supplier = row;
      final brId = supplier['broker_id']?.toString();
      _brokerIdFromSupplier = (brId != null && brId.isNotEmpty) ? brId : null;
      _brokerId = _brokerIdFromSupplier;
      final pd = supplier['default_payment_days'];
      _paymentDaysCtrl.text = pd is num ? pd.toString() : '';
      final dr = supplier['default_delivered_rate'];
      if (dr is num && dr > 0) {
        _deliveredRateCtrl.text = dr.toString();
      } else {
        _deliveredRateCtrl.clear();
      }
      final brR = supplier['default_billty_rate'];
      if (brR is num && brR > 0) {
        _billtyRateCtrl.text = brR.toString();
      } else {
        _billtyRateCtrl.clear();
      }
      final ft = supplier['freight_type']?.toString();
      if (ft == 'included' || ft == 'separate') {
        _freightType = ft!;
      }
    });
    _onFormChanged();
    unawaited(_openCatalogLinePrefillIfNeeded());
  }

  Map<String, dynamic> _buildTradePurchaseBody() {
    final lines = <Map<String, dynamic>>[];
    for (final item in _items) {
      final m = <String, dynamic>{
        'item_name': item['item_name'],
        'qty': item['qty'],
        'unit': item['unit'],
        'landing_cost': item['landing_cost'],
      };
      final cid = item['catalog_item_id']?.toString();
      if (cid != null && cid.isNotEmpty) m['catalog_item_id'] = cid;
      final sc = item['selling_cost'];
      if (sc is num) m['selling_cost'] = sc.toDouble();
      final tp = item['tax_percent'];
      if (tp is num) m['tax_percent'] = tp.toDouble();
      final disc = item['discount'];
      if (disc is num) m['discount'] = disc.toDouble();
      lines.add(m);
    }

    final body = <String, dynamic>{
      'purchase_date': DateFormat('yyyy-MM-dd').format(_purchaseDate),
      'status': 'confirmed',
      'lines': lines,
      'freight_type': _freightType,
    };
    final inv = _invoiceCtrl.text.trim();
    if (inv.isNotEmpty) body['invoice_number'] = inv;
    if (_supplierId != null && _supplierId!.isNotEmpty) {
      body['supplier_id'] = _supplierId;
    }
    if (_brokerId != null && _brokerId!.isNotEmpty) {
      body['broker_id'] = _brokerId;
    }
    final pd = int.tryParse(_paymentDaysCtrl.text.trim());
    if (pd != null && pd >= 0) body['payment_days'] = pd;
    final hd = double.tryParse(_headerDiscCtrl.text.trim());
    if (hd != null && hd > 0) body['discount'] = hd;
    final comm = double.tryParse(_commissionCtrl.text.trim());
    if (comm != null && comm > 0) body['commission_percent'] = comm;
    final dlr = double.tryParse(_deliveredRateCtrl.text.trim());
    if (dlr != null && dlr >= 0) body['delivered_rate'] = dlr;
    final brt = double.tryParse(_billtyRateCtrl.text.trim());
    if (brt != null && brt >= 0) body['billty_rate'] = brt;
    final fa = double.tryParse(_freightCtrl.text.trim());
    if (fa != null && fa > 0) body['freight_amount'] = fa;
    return body;
  }

  void _removeLineAt(int index) {
    if (index < 0 || index >= _items.length) return;
    if (index < _lineScrollKeys.length) {
      _lineScrollKeys.removeAt(index);
    }
    _items.removeAt(index);
    setState(() {});
    _onFormChanged();
  }

  double _lineProfit(Map<String, dynamic> item) {
    final sc = item['selling_cost'];
    if (sc is! num) return 0;
    final lc = (item['landing_cost'] as num?)?.toDouble() ?? 0;
    final q = (item['qty'] as num?)?.toDouble() ?? 0;
    return (sc.toDouble() - lc) * q;
  }

  Future<void> _openItemSheet(
    List<Map<String, dynamic>> catalog, {
    int? editIndex,
    Map<String, dynamic>? initialOverride,
  }) async {
    if (!_headerComplete) return;
    final initial =
        initialOverride ?? (editIndex != null ? Map<String, dynamic>.from(_items[editIndex]) : null);
    final mq = MediaQuery.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: mq.size.height - mq.padding.top - 12,
      ),
      builder: (ctx) {
        final viewBottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewBottom),
          child: PurchaseItemEntrySheet(
            catalog: catalog,
            initial: initial,
            isEdit: editIndex != null,
            onCommitted: (line) {
              setState(() {
                if (editIndex != null) {
                  _items[editIndex] = Map<String, dynamic>.from(line);
                } else {
                  _items.add(Map<String, dynamic>.from(line));
                  _lineScrollKeys.add(GlobalKey());
                }
                _saveFormError = null;
              });
              _onFormChanged();
            },
          ),
        );
      },
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addItemFocusNode.requestFocus();
    });
  }

  Map<String, dynamic>? _catalogRowById(List<Map<String, dynamic>> catalog, String id) {
    for (final m in catalog) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  static const _draftKeyV1 = 'draft_trade_purchase_v1';

  String? _draftPrefsKey() {
    final s = ref.read(sessionProvider);
    if (s == null) return null;
    return '${_draftKeyV1}_${s.primaryBusiness.id}';
  }

  Future<void> _prefetchNextHumanId() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final s = ref.read(sessionProvider);
    if (s == null) return;
    try {
      final id = await ref
          .read(hexaApiProvider)
          .nextTradePurchaseHumanId(businessId: s.primaryBusiness.id);
      if (!mounted) return;
      if (id.isNotEmpty) setState(() => _previewHumanId = id);
    } catch (_) {}
  }

  void _onFormChanged() {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    if (!mounted) return;
    if (!_formDirty) {
      setState(() => _formDirty = true);
    }
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(_flushDraftToPrefs());
    });
  }

  Map<String, dynamic> _collectDraftMap() {
    return {
      'supplierId': _supplierId,
      'supplierName': _supplierName,
      'brokerId': _brokerId,
      'brokerIdFromSupplier': _brokerIdFromSupplier,
      'purchaseDate': _purchaseDate.toIso8601String(),
      'invoice': _invoiceCtrl.text,
      'paymentDays': _paymentDaysCtrl.text,
      'headerDisc': _headerDiscCtrl.text,
      'commission': _commissionCtrl.text,
      'delivered': _deliveredRateCtrl.text,
      'billty': _billtyRateCtrl.text,
      'freight': _freightCtrl.text,
      'freightType': _freightType,
      'items': _items.map((e) => Map<String, dynamic>.from(e)).toList(),
    };
  }

  Future<void> _flushDraftToPrefs() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final k = _draftPrefsKey();
    if (k == null) return;
    final p = ref.read(sharedPreferencesProvider);
    await p.setString(k, jsonEncode(_collectDraftMap()));
  }

  Future<void> _clearDraftInPrefs() async {
    final k = _draftPrefsKey();
    if (k == null) return;
    final p = ref.read(sharedPreferencesProvider);
    await p.remove(k);
  }

  Future<void> _maybeRestoreDraft() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final k = _draftPrefsKey();
    if (k == null) return;
    final p = ref.read(sharedPreferencesProvider);
    final s = p.getString(k);
    if (s == null || s.isEmpty) return;
    try {
      final o = jsonDecode(s);
      if (o is! Map) return;
      final m = Map<String, dynamic>.from(o);
      if (!mounted) return;
      setState(() {
        _supplierId = m['supplierId']?.toString();
        _supplierName = m['supplierName']?.toString();
        if (_supplierName != null && _supplierName!.isNotEmpty) {
          _supplierCtrl.text = _supplierName!;
        }
        _brokerId = m['brokerId']?.toString();
        _brokerIdFromSupplier = m['brokerIdFromSupplier']?.toString();
        final pd = m['purchaseDate']?.toString();
        if (pd != null && pd.isNotEmpty) {
          final d = DateTime.tryParse(pd);
          if (d != null) _purchaseDate = d;
        }
        _invoiceCtrl.text = m['invoice']?.toString() ?? '';
        _paymentDaysCtrl.text = m['paymentDays']?.toString() ?? '';
        _headerDiscCtrl.text = m['headerDisc']?.toString() ?? '';
        _commissionCtrl.text = m['commission']?.toString() ?? '';
        _deliveredRateCtrl.text = m['delivered']?.toString() ?? '';
        _billtyRateCtrl.text = m['billty']?.toString() ?? '';
        _freightCtrl.text = m['freight']?.toString() ?? '';
        final ft = m['freightType']?.toString();
        if (ft == 'included' || ft == 'separate') _freightType = ft!;
        final lines = m['items'];
        _items.clear();
        if (lines is List) {
          for (final e in lines) {
            if (e is Map) _items.add(Map<String, dynamic>.from(e));
          }
        }
        _rebuildLineKeys();
        _formDirty = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restored your unsaved purchase draft')),
        );
      }
    } catch (_) {}
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return true;
    if (!_formDirty) return true;
    final a = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return a == true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(suppliersListProvider, (prev, next) {
      next.whenData((d) {
        _lastGoodSuppliersList = d;
      });
    });
    final totals = _computeTotals();
    final isEdit = widget.editingId != null && widget.editingId!.isNotEmpty;

    return PopScope(
      canPop: isEdit || !_formDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfNeeded();
        if (ok == true && mounted) {
          await _clearDraftInPrefs();
          if (context.mounted) {
            if (context.canPop()) context.pop();
          }
        }
      },
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit purchase' : 'New Purchase'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        elevation: 0,
      ),
      body: _isBootstrapping
          ? const Center(child: CircularProgressIndicator())
          : ref.watch(catalogItemsListProvider).when(
                loading: () => const Center(child: LinearProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Could not load catalog')),
                data: (catalog) {
                  final kb = MediaQuery.viewInsetsOf(context).bottom;
                  final header = _buildFixedHeader(catalog, isEdit: isEdit);
                  return Padding(
                    padding: EdgeInsets.only(bottom: kb),
                    child: CustomScrollView(
                      controller: _bodyScrollController,
                      physics: const ClampingScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          sliver: SliverToBoxAdapter(child: header),
                        ),
                        if (_saveFormError != null)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            sliver: SliverToBoxAdapter(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red[200]!),
                                ),
                                child: Text(
                                  _saveFormError!,
                                  style: TextStyle(color: Colors.red[900], fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        if (_items.isEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
                            sliver: SliverToBoxAdapter(
                              child: Center(
                                child: Text(
                                  'No items yet — tap Add item',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            sliver: RepaintBoundary(
                              child: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, i) {
                                    if (i.isOdd) {
                                      return Divider(height: 1, color: Colors.grey[300]);
                                    }
                                    final lineIndex = i ~/ 2;
                                    return KeyedSubtree(
                                      key: _lineScrollKeys[lineIndex],
                                      child: _buildLineTile(catalog, lineIndex),
                                    );
                                  },
                                  childCount: _items.length * 2 - 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      bottomNavigationBar: _isBootstrapping
          ? null
          : _buildPurchaseSummaryFooter(totals, isEdit: isEdit),
      ),
    );
  }

  Widget _buildFixedHeader(List<Map<String, dynamic>> catalog, {required bool isEdit}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEdit &&
            _loadedDerivedStatus != null &&
            _loadedDerivedStatus!.isNotEmpty) ...[
          Text(
            'Payment: $_loadedDerivedStatus · Bal ₹${(_loadedRemaining ?? 0).toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: Colors.grey[800],
                ),
          ),
          const SizedBox(height: 8),
        ],
        if (!isEdit &&
            _previewHumanId != null &&
            _previewHumanId!.isNotEmpty) ...[
          Text(
            'Purchase ID (preview): $_previewHumanId',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: HexaColors.brandPrimary,
                ),
          ),
          const SizedBox(height: 8),
        ],
        if (isEdit && _editHumanId != null && _editHumanId!.isNotEmpty) ...[
          Text(
            'Purchase ID: $_editHumanId',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
        ],
        KeyedSubtree(
          key: _supplierSectionKey,
          child: _buildSupplierField(),
        ),
        if (_supplierName != null && _supplierName!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Supplier: $_supplierName',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[900],
                ),
          ),
        ],
        const SizedBox(height: 10),
        _buildPurchaseDateField(),
        const SizedBox(height: 8),
        _buildBrokerOptionalTile(),
        if (_supplierId != null && _supplierId!.isNotEmpty) ...[
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _termsSectionKey,
            child: _buildSupplierTermsCard(),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Invoice (optional)',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _invoiceCtrl,
          decoration: _fieldDeco('Invoice #', hint: 'Optional'),
          onChanged: (_) {
            setState(() {});
            _onFormChanged();
          },
        ),
        const SizedBox(height: 10),
        KeyedSubtree(
          key: _addItemSectionKey,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              focusNode: _addItemFocusNode,
              onPressed: (!_headerComplete || _isSaving || _isBootstrapping)
                  ? null
                  : () => _openItemSheet(catalog),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add item'),
            ),
          ),
        ),
      ],
    );
  }

  /// Purchase date (trader path: after supplier).
  Widget _buildPurchaseDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date *',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _purchaseDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              setState(() => _purchaseDate = date);
              _onFormChanged();
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 18, color: HexaColors.brandPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('dd MMM yyyy').format(_purchaseDate),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _termsChanged() {
    setState(() {});
    _onFormChanged();
  }

  /// purchase.md §2: payment_days, delivered, billty, freight+type, broker commission — no header discount here.
  Widget _buildSupplierTermsCard() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Supplier terms',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              'Editable for this purchase',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            _buildPaymentDaysDueRow(),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(
                _duePreviewText(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: HexaColors.brandPrimary,
                      fontSize: 12,
                    ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deliveredRateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _compactFieldDeco('Delivered rate'),
                    onChanged: (_) => _termsChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _billtyRateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _compactFieldDeco('Billty rate'),
                    onChanged: (_) => _termsChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _freightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _compactFieldDeco('Freight', prefixText: '₹ '),
                    onChanged: (_) => _termsChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InputDecorator(
                    decoration: _compactFieldDeco('Freight type'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _freightType,
                        isExpanded: true,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'separate', child: Text('Separate')),
                          DropdownMenuItem(value: 'included', child: Text('Included')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _freightType = v);
                          _onFormChanged();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commissionCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _compactFieldDeco('Broker commission %'),
              onChanged: (_) => _termsChanged(),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: HexaColors.brandPrimary, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  InputDecoration _compactFieldDeco(String label, {String? hint, String? prefixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
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
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );
  }

  Widget _buildPaymentDaysDueRow() {
    return TextField(
      controller: _paymentDaysCtrl,
      keyboardType: TextInputType.number,
      decoration: _fieldDeco('Payment days'),
      onChanged: (_) => _termsChanged(),
    );
  }

  Widget _buildBrokerOptionalTile() {
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: Colors.grey[800],
        );
    final br = _brokerId;
    final fromS = _brokerIdFromSupplier;
    String sub;
    if (br == null || br.isEmpty) {
      sub = 'No broker on this purchase.';
    } else if (fromS != null && fromS.isNotEmpty && br == fromS) {
      sub = 'From supplier';
    } else {
      sub = 'Manual (differs from supplier default or edited)';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Broker (optional)',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          style: small,
        ),
      ],
    );
  }

  Widget _buildLineTile(List<Map<String, dynamic>> catalog, int index) {
    final item = _items[index];
    final name = item['item_name']?.toString() ?? 'Item';
    final q = (item['qty'] as num?)?.toDouble() ?? 0;
    final r = (item['landing_cost'] as num?)?.toDouble() ?? 0;
    final tax = item['tax_percent'];
    final disc = item['discount'];
    final line = TradeCalcLine(
      qty: q,
      landingCost: r,
      taxPercent: tax is num ? tax.toDouble() : null,
      discountPercent: disc is num ? disc.toDouble() : null,
    );
    final lineTotal = lineMoney(line);
    final profit = _lineProfit(item);

    return KeyedSubtree(
      key: ValueKey('purchase_line_${item['catalog_item_id']}_$index'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${q == q.roundToDouble() ? q.round() : q} × landing ₹${r.toStringAsFixed(0)} = ₹${lineTotal.toStringAsFixed(0)}'
              '${profit != 0 ? ' · Profit ₹${profit.toStringAsFixed(0)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[800],
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton(
                  onPressed: (!_headerComplete || _isSaving || _isBootstrapping)
                      ? null
                      : () => _openItemSheet(catalog, editIndex: index),
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: (_isSaving || _isBootstrapping) ? null : () => _removeLineAt(index),
                  child: Text('Delete', style: TextStyle(color: Colors.red[800])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowPair(String label, String value, {bool emphasize = false, Color? valueColor}) {
    final vStyle = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: valueColor ?? Colors.green[800],
            )
        : Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
            );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: Colors.grey[800],
                  ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: vStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseSummaryFooter(TradeCalcTotals totals, {required bool isEdit}) {
    final b = _strictFooterBreakdown(totals);
    return SafeArea(
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_headerComplete) ...[
                Text(
                  'Purchase-level',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _headerDiscCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _compactFieldDeco('Header discount % (optional)'),
                  onChanged: (_) {
                    setState(() {});
                    _onFormChanged();
                  },
                ),
                const SizedBox(height: 10),
              ],
              _rowPair('Subtotal', '₹${b.subtotalGross.toStringAsFixed(0)}'),
              _rowPair('Tax', '₹${b.taxTotal.toStringAsFixed(0)}'),
              _rowPair(
                'Discount',
                '- ₹${b.discountTotal.toStringAsFixed(0)}',
                valueColor: Colors.red[800],
              ),
              _rowPair('Freight', '₹${b.freight.toStringAsFixed(0)}'),
              _rowPair('Broker commission', '₹${b.commission.toStringAsFixed(0)}'),
              const Divider(height: 16),
              _rowPair('Final total', '₹${b.grand.toStringAsFixed(0)}', emphasize: true),
              const SizedBox(height: 4),
              Text(
                _duePreviewText(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: HexaColors.brandPrimary,
                      fontSize: 12,
                    ),
              ),
              if (isEdit &&
                  _loadedDerivedStatus != null &&
                  _loadedDerivedStatus!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_loadedDerivedStatus!} · Bal ₹${(_loadedRemaining ?? 0).toStringAsFixed(0)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: Colors.grey[700],
                        ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: (_isSaving || _isBootstrapping || !_headerComplete)
                    ? null
                    : _validateAndSave,
                child: _isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save purchase'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierField() {
    final av = ref.watch(suppliersListProvider);
    final showErrorBorder = _supplierFieldError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Supplier *',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: showErrorBorder ? Colors.red[400]! : Colors.grey[300]!,
              width: showErrorBorder ? 2 : 1,
            ),
          ),
          child: av.when(
            data: (list) {
              return _buildSupplierSearchColumn(list);
            },
            error: (_, __) {
              if (_lastGoodSuppliersList != null) {
                return _buildSupplierSearchColumn(_lastGoodSuppliersList!);
              }
              return const Text('Could not load suppliers');
            },
            loading: () {
              if (_lastGoodSuppliersList != null) {
                return _buildSupplierSearchColumn(_lastGoodSuppliersList!);
              }
              return const LinearProgressIndicator();
            },
          ),
        ),
        if (_supplierFieldError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _supplierFieldError!,
              style: TextStyle(color: Colors.red[800], fontSize: 12),
            ),
          ),
        if (_supplierName != null && _supplierName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Chip(
              label: Text(_supplierName!),
              onDeleted: () {
                setState(() {
                  _supplierId = null;
                  _supplierName = null;
                  _brokerId = null;
                  _brokerIdFromSupplier = null;
                  _supplierCtrl.clear();
                  _paymentDaysCtrl.clear();
                  _headerDiscCtrl.clear();
                  _commissionCtrl.clear();
                  _deliveredRateCtrl.clear();
                  _billtyRateCtrl.clear();
                  _freightCtrl.clear();
                  _freightType = 'separate';
                  _supplierFieldError = null;
                  _saveFormError = null;
                });
                _onFormChanged();
              },
            ),
          ),
      ],
    );
  }

  /// API may use [name] or legacy/alternate keys; keep search/selection working either way.
  String _supplierMapLabel(Map<String, dynamic> m) {
    for (final k in ['name', 'legal_name', 'display_name', 'company_name', 'trading_name']) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return m['id']?.toString() ?? '';
  }

  Widget _buildSupplierSearchColumn(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return Text(
        'No suppliers in this workspace yet — the list is empty, so search cannot match anything. '
        'If you see HTTP 404 on bootstrap-workspace, your API is missing the seed route: update the backend, '
        'or add at least one supplier under Contacts.',
        style: TextStyle(fontSize: 12, color: Colors.grey[800]),
      );
    }
    final items = <InlineSearchItem>[
      for (final m in list)
        if (m['id'] != null && m['id'].toString().isNotEmpty)
          InlineSearchItem(
            id: m['id'].toString(),
            label: _supplierMapLabel(m),
            subtitle: m['gst_number']?.toString(),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineSearchField(
          key: const ValueKey<String>('purchase_supplier_search'),
          controller: _supplierCtrl,
          placeholder: 'Type at least 1 letter…',
          prefixIcon: const Icon(Icons.business_rounded),
          items: items,
          focusAfterSelection: _addItemFocusNode,
          onSelected: (it) {
            if (it.id.isEmpty) return;
            _applySupplierSelection(list, it);
          },
        ),
      ],
    );
  }

  /// purchase.md §8: normalize line maps before building API body.
  void _syncLineItemsBeforeSave() {
    for (var i = 0; i < _items.length; i++) {
      final e = _items[i];
      final m = Map<String, dynamic>.from(e);
      m['item_name'] = m['item_name']?.toString() ?? '';
      m['qty'] = (m['qty'] as num?)?.toDouble() ?? 0.0;
      m['unit'] = m['unit']?.toString() ?? '';
      m['landing_cost'] = (m['landing_cost'] as num?)?.toDouble() ?? 0.0;
      final sc = m['selling_cost'];
      if (sc is num) m['selling_cost'] = sc.toDouble();
      final tp = m['tax_percent'];
      if (tp is num) m['tax_percent'] = tp.toDouble();
      final disc = m['discount'];
      if (disc is num) m['discount'] = disc.toDouble();
      _items[i] = m;
    }
  }

  void _validateAndSave() {
    if (_isSaving) return;
    setState(() {
      _supplierFieldError = null;
      _saveFormError = null;
    });
    if (_supplierId == null || _supplierId!.isEmpty) {
      setState(() => _supplierFieldError = 'Select a supplier from the suggestions list');
      _scrollToKey(_supplierSectionKey);
      return;
    }
    if (_items.isEmpty) {
      setState(() => _saveFormError = 'Add at least one item using Add item.');
      _scrollToKey(_addItemSectionKey);
      return;
    }
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      final name = it['item_name']?.toString().trim() ?? '';
      final q = (it['qty'] as num?)?.toDouble() ?? 0;
      final r = (it['landing_cost'] as num?)?.toDouble() ?? 0;
      if (name.isEmpty || q <= 0 || r <= 0) {
        setState(() {
          _saveFormError =
              'Line ${i + 1} is invalid: need item name, quantity > 0, and landing cost > 0. Tap Edit on that line.';
        });
        if (i < _lineScrollKeys.length) {
          _scrollToKey(_lineScrollKeys[i]);
        }
        return;
      }
    }
    _savePurchase();
  }

  Future<void> _savePurchase() async {
    if (_isSaving) return;
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    _syncLineItemsBeforeSave();
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    final body = _buildTradePurchaseBody();
    final isEdit = widget.editingId != null && widget.editingId!.isNotEmpty;

    try {
      final saved = isEdit
          ? await api.updateTradePurchase(
              businessId: bid,
              purchaseId: widget.editingId!,
              body: body,
            )
          : await api.createTradePurchase(
              businessId: bid,
              body: body,
            );

      ref.invalidate(tradePurchasesListProvider);
      ref.invalidate(suppliersListProvider);
      invalidateBusinessAggregates(ref);

      await _clearDraftInPrefs();
      if (mounted) setState(() => _formDirty = false);
      final pid = saved['id']?.toString() ?? '';
      if (pid.isNotEmpty) {
        await LocalNotificationsService.instance.scheduleTradePurchaseDueAtNineAmIfNeeded(
          purchaseId: pid,
          dueDateIso: saved['due_date']?.toString(),
          humanId: saved['human_id']?.toString(),
        );
      }

      if (!mounted) return;
      setState(() => _isSaving = false);

      final quickSave = ref.read(quickSavePurchaseProvider);
      if (quickSave) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Purchase updated' : 'Purchase saved'),
            backgroundColor: Colors.green[700],
          ),
        );
        if (context.canPop()) context.pop();
      } else {
        final where = await showPurchaseSavedSheet(
          context,
          ref,
          savedJson: saved,
          wasEdit: isEdit,
        );
        if (!mounted) return;
        if (where == 'detail') {
          final pid = saved['id']?.toString();
          if (pid != null && pid.isNotEmpty) {
            context.go('/purchase/detail/$pid');
          }
        } else {
          if (context.canPop()) context.pop();
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        final hint = fastApiPurchaseScrollHint(e.response?.data);
        if (hint != null) {
          if (hint.supplierField) {
            _scrollToKey(_supplierSectionKey);
          } else if (hint.lineIndex != null) {
            final i = hint.lineIndex!;
            if (i >= 0 && i < _lineScrollKeys.length) {
              _scrollToKey(_lineScrollKeys[i]);
            } else {
              _scrollToKey(_addItemSectionKey);
            }
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
