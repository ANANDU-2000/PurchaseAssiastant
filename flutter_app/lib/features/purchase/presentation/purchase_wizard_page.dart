import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/purchase_prefill_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../shared/widgets/full_screen_form_scaffold.dart';
import 'widgets/defaults_applied_card.dart';
import 'widgets/purchase_saved_sheet.dart';

class PurchaseWizardPage extends ConsumerStatefulWidget {
  const PurchaseWizardPage({super.key, this.editingId});

  /// When set, wizard loads this purchase and saves via PUT.
  final String? editingId;

  @override
  ConsumerState<PurchaseWizardPage> createState() => _PurchaseWizardPageState();
}

class _PurchaseWizardPageState extends ConsumerState<PurchaseWizardPage> {
  static const EdgeInsets _pagePadding = EdgeInsets.fromLTRB(10, 4, 10, 14);

  int _step = 0;
  bool _dirty = false;
  String? _editPurchaseId;
  bool _leaveInFlight = false;
  Timer? _draftTimer;
  Timer? _searchDebounce;

  final _search = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _paymentDaysCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _deliveredCtrl = TextEditingController();
  final _billtyCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();

  DateTime _purchaseDate = DateTime.now();
  String _purchaseHumanId = 'PUR-...';
  String? _supplierId;
  String? _brokerId;
  String _freightType = 'included';
  int? _paymentDays;
  double? _discount;
  double? _commission;
  double? _delivered;
  double? _billty;
  double? _freight;
  String? _headerError;
  String? _supplierWarning;

  final List<Map<String, dynamic>> _lines = [];
  List<Map<String, dynamic>> _searchHits = [];
  final Set<String> _supplierMappedItemIds = <String>{};
  final Set<String> _supplierRecentItemNames = <String>{};
  final Map<String, Map<String, dynamic>> _historyByItem = {};

  @override
  void initState() {
    super.initState();
    _editPurchaseId =
        (widget.editingId != null && widget.editingId!.trim().isNotEmpty)
            ? widget.editingId!.trim()
            : null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_editPurchaseId != null) {
        await _bootstrapHistoryCache();
        await _loadExistingForEdit(_editPurchaseId!);
        if (!mounted) return;
        await _hydrateSupplierMemoryFromSupplierId();
        return;
      }
      await _loadDraft();
      await _bootstrapHistoryCache();
      await _hydrateSupplierMemoryFromSupplierId();
      await _loadNextPurchaseId();
      if (!mounted) return;
      final pre = ref.read(pendingPurchaseSupplierIdProvider);
      if (pre != null && pre.isNotEmpty) {
        ref.read(pendingPurchaseSupplierIdProvider.notifier).state = null;
        await _applyPrefillSupplier(pre);
      }
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _commissionCtrl.dispose();
    _paymentDaysCtrl.dispose();
    _discountCtrl.dispose();
    _deliveredCtrl.dispose();
    _billtyCtrl.dispose();
    _freightCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrapHistoryCache() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final purchases = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: 120,
          );
      final history = <String, Map<String, dynamic>>{};
      for (final p in purchases) {
        final pDate = p['purchase_date']?.toString();
        final supplier = p['supplier_id']?.toString();
        final lines = p['lines'];
        if (lines is! List) continue;
        for (final raw in lines) {
          if (raw is! Map) continue;
          final l = Map<String, dynamic>.from(raw);
          final name = (l['item_name']?.toString() ?? '').trim();
          if (name.isEmpty) continue;
          final key = name.toLowerCase();
          final item = history.putIfAbsent(
            key,
            () => {
              'name': name,
              'prices': <double>[],
              'last_price': null,
              'last_date': null,
              'supplier_ids': <String>{},
              'used_count': 0,
            },
          );
          item['used_count'] = (item['used_count'] as int) + 1;
          final price = (l['landing_cost'] as num?)?.toDouble();
          if (price != null) {
            (item['prices'] as List<double>).add(price);
          }
          final prevDate = item['last_date']?.toString();
          if (pDate != null && (prevDate == null || pDate.compareTo(prevDate) > 0)) {
            item['last_date'] = pDate;
            item['last_price'] = price;
          }
          if (supplier != null && supplier.isNotEmpty) {
            (item['supplier_ids'] as Set<String>).add(supplier);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _historyByItem
          ..clear()
          ..addAll(history);
      });
    } catch (_) {}
  }

  Future<void> _loadNextPurchaseId() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final id = await ref.read(hexaApiProvider).nextTradePurchaseHumanId(
            businessId: session.primaryBusiness.id,
          );
      if (!mounted || id.isEmpty) return;
      setState(() => _purchaseHumanId = id);
    } catch (_) {}
  }

  Future<void> _applyPrefillSupplier(String id) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final s = await ref.read(hexaApiProvider).getSupplier(
            businessId: session.primaryBusiness.id,
            supplierId: id,
          );
      if (!mounted || s.isEmpty) return;
      setState(() {
        _supplierId = id;
        _applySupplierDefaults(s);
        _refreshSupplierMemory(s);
        _syncBrokerCommissionFromList(ref.read(brokersListProvider).valueOrNull, force: true);
        _dirty = true;
        _scheduleDraft();
      });
    } catch (_) {}
  }

  Future<void> _hydrateSupplierMemoryFromSupplierId() async {
    final session = ref.read(sessionProvider);
    final sid = _supplierId;
    if (session == null || sid == null || sid.isEmpty) return;
    try {
      final s = await ref.read(hexaApiProvider).getSupplier(
            businessId: session.primaryBusiness.id,
            supplierId: sid,
          );
      if (!mounted || s.isEmpty) return;
      setState(() => _refreshSupplierMemory(s));
    } catch (_) {}
  }

  void _refreshSupplierMemory(Map<String, dynamic> supplierRow) {
    _supplierMappedItemIds.clear();
    final raw = supplierRow['preferences_json']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final itemIds = (m['item_ids'] as List?) ?? const [];
        for (final id in itemIds) {
          _supplierMappedItemIds.add(id.toString());
        }
      } catch (_) {}
    }
    _supplierRecentItemNames.clear();
    for (final e in _historyByItem.entries) {
      final supplierIds = e.value['supplier_ids'] as Set<String>? ?? const {};
      if (_supplierId != null && supplierIds.contains(_supplierId)) {
        _supplierRecentItemNames.add(e.key);
      }
    }
  }

  Future<void> _loadDraft() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final d = await ref.read(hexaApiProvider).getTradePurchaseDraft(
          businessId: session.primaryBusiness.id,
        );
    if (!mounted || d == null) return;
    final p = d['payload'];
    if (p is! Map) return;
    final m = Map<String, dynamic>.from(Map<Object?, Object?>.from(p));
    setState(() {
      _step = (d['step'] as num?)?.toInt() ?? 0;
      if (m['purchase_date'] != null) {
        _purchaseDate = DateTime.tryParse(m['purchase_date'].toString()) ?? _purchaseDate;
      }
      _purchaseHumanId = m['human_id']?.toString() ?? _purchaseHumanId;
      _supplierId = m['supplier_id']?.toString();
      _brokerId = m['broker_id']?.toString();
      _freightType = m['freight_type']?.toString() ?? _freightType;
      _paymentDays = (m['payment_days'] as num?)?.toInt();
      _discount = (m['discount'] as num?)?.toDouble();
      _commission = (m['commission_percent'] as num?)?.toDouble();
      _delivered = (m['delivered_rate'] as num?)?.toDouble();
      _billty = (m['billty_rate'] as num?)?.toDouble();
      _freight = (m['freight_amount'] as num?)?.toDouble();
      _commissionCtrl.text = _commission?.toString() ?? '';
      _paymentDaysCtrl.text = _paymentDays?.toString() ?? '';
      _discountCtrl.text = _discount?.toString() ?? '';
      _deliveredCtrl.text = _delivered?.toString() ?? '';
      _billtyCtrl.text = _billty?.toString() ?? '';
      _freightCtrl.text = _freight?.toString() ?? '';
      final raw = m['lines'];
      if (raw is List) {
        _lines
          ..clear()
          ..addAll(raw.map((e) => Map<String, dynamic>.from(e as Map)));
        for (final l in _lines) {
          final allow = _allowedUnitsForLine(l);
          final u = (l['unit']?.toString() ?? '').toLowerCase();
          if (allow.isNotEmpty && !allow.contains(u)) {
            l['unit'] = allow.first;
          }
        }
      }
      _dirty = false;
      _syncBrokerCommissionFromList(ref.read(brokersListProvider).valueOrNull, force: false);
    });
  }

  int? _maxLinePaymentDays() {
    int? mx;
    for (final l in _lines) {
      final pd = (l['payment_days'] as num?)?.toInt();
      if (pd != null && pd >= 0) {
        mx = mx == null ? pd : (mx > pd ? mx : pd);
      }
    }
    return mx;
  }

  Map<String, dynamic> _payload() {
    return {
      'human_id': _purchaseHumanId,
      'purchase_date': DateFormat('yyyy-MM-dd').format(_purchaseDate),
      'supplier_id': _supplierId,
      'broker_id': _brokerId,
      'freight_type': _freightType,
      'payment_days': _maxLinePaymentDays(),
      'discount': _discount,
      'commission_percent': _commission,
      'delivered_rate': _delivered,
      'billty_rate': _billty,
      'freight_amount': _freight,
      'status': 'confirmed',
      'lines': List<Map<String, dynamic>>.from(_lines),
    };
  }

  Future<void> _loadExistingForEdit(String purchaseId) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final p = await ref.read(hexaApiProvider).getTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: purchaseId,
          );
      if (!mounted || p.isEmpty) return;
      setState(() {
        _purchaseHumanId = p['human_id']?.toString() ?? _purchaseHumanId;
        if (p['purchase_date'] != null) {
          _purchaseDate =
              DateTime.tryParse(p['purchase_date'].toString()) ?? _purchaseDate;
        }
        _supplierId = p['supplier_id']?.toString();
        _brokerId = p['broker_id']?.toString();
        _freightType = p['freight_type']?.toString() ?? _freightType;
        _paymentDays = (p['payment_days'] as num?)?.toInt();
        _discount = (p['discount'] as num?)?.toDouble();
        _commission = (p['commission_percent'] as num?)?.toDouble();
        _delivered = (p['delivered_rate'] as num?)?.toDouble();
        _billty = (p['billty_rate'] as num?)?.toDouble();
        _freight = (p['freight_amount'] as num?)?.toDouble();
        _commissionCtrl.text = _commission?.toString() ?? '';
        _paymentDaysCtrl.text = _paymentDays?.toString() ?? '';
        _discountCtrl.text = _discount?.toString() ?? '';
        _deliveredCtrl.text = _delivered?.toString() ?? '';
        _billtyCtrl.text = _billty?.toString() ?? '';
        _freightCtrl.text = _freight?.toString() ?? '';
        _lines
          ..clear()
          ..addAll(_linesFromPurchaseJson(p));
        _dirty = false;
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> _linesFromPurchaseJson(Map<String, dynamic> p) {
    final raw = p['lines'];
    final out = <Map<String, dynamic>>[];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      out.add({
        'item_name': m['item_name'],
        'qty': m['qty'],
        'unit': m['unit'] ?? 'kg',
        'landing_cost': m['landing_cost'],
        'selling_cost': m['selling_cost'],
        'discount': m['discount'],
        'tax_percent': m['tax_percent'],
        'payment_days': m['payment_days'],
        'hsn_code': m['hsn_code']?.toString(),
        'description': m['description']?.toString(),
        'catalog_item_id': m['catalog_item_id']?.toString(),
      });
    }
    return out;
  }

  void _scheduleDraft() {
    if (!mounted) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 1200), () async {
      final session = ref.read(sessionProvider);
      if (session == null || !mounted) return;
      try {
        await ref.read(hexaApiProvider).putTradePurchaseDraft(
              businessId: session.primaryBusiness.id,
              step: _step,
              payload: _payload(),
            );
      } catch (_) {}
    });
  }

  void _markDirty() {
    setState(() => _dirty = true);
    _scheduleDraft();
  }

  bool _validateHeader() {
    _headerError = null;
    if (_supplierId == null || _supplierId!.isEmpty) {
      _headerError = 'Supplier is required';
    }
    setState(() {});
    return _headerError == null;
  }

  void _applySupplierDefaults(Map<String, dynamic> s) {
    _delivered = (s['default_delivered_rate'] as num?)?.toDouble() ?? _delivered;
    _billty = (s['default_billty_rate'] as num?)?.toDouble() ?? _billty;
    final freightType = s['freight_type']?.toString();
    if (freightType == 'included' || freightType == 'separate') {
      _freightType = freightType!;
    }
    final bid = s['broker_id']?.toString();
    if (bid != null && bid.isNotEmpty) {
      _brokerId = bid;
    } else {
      _brokerId = null;
      _commission = null;
      _commissionCtrl.clear();
    }
    _paymentDaysCtrl.text = _paymentDays?.toString() ?? '';
    _discountCtrl.text = _discount?.toString() ?? '';
    _deliveredCtrl.text = _delivered?.toString() ?? '';
    _billtyCtrl.text = _billty?.toString() ?? '';
    if (_freightType == 'included') {
      _freight = 0;
      _freightCtrl.text = '0';
    } else {
      _freight = (_delivered ?? 0) + (_billty ?? 0);
      _freightCtrl.text = _freight?.toStringAsFixed(2) ?? '';
    }
  }

  /// When [force] is true (e.g. supplier or broker dropdown changed), commission is refreshed from broker master.
  /// Otherwise fills only if commission is still unset (async broker list load after draft).
  bool _syncBrokerCommissionFromList(List<Map<String, dynamic>>? brokers, {required bool force}) {
    if (brokers == null) return false;
    final id = _brokerId;
    if (id == null || id.isEmpty) {
      if (force) {
        final had = _commission != null || _commissionCtrl.text.trim().isNotEmpty;
        _commission = null;
        _commissionCtrl.clear();
        return had;
      }
      return false;
    }
    if (!force && _commission != null) return false;
    Map<String, dynamic>? row;
    for (final r in brokers) {
      if (r['id']?.toString() == id) {
        row = r;
        break;
      }
    }
    if (row == null) return false;
    final cv = (row['commission_value'] as num?)?.toDouble();
    if (cv == null) return false;
    final text = cv.toString();
    if (_commission == cv && _commissionCtrl.text == text) return false;
    _commission = cv;
    _commissionCtrl.text = text;
    return true;
  }

  double _lineGross(Map<String, dynamic> l) {
    final q = (l['qty'] as num?)?.toDouble() ?? 0;
    final lc = (l['landing_cost'] as num?)?.toDouble() ?? 0;
    return q * lc;
  }

  double _lineNetAfterLineDiscount(Map<String, dynamic> l) {
    final disc = ((l['discount'] as num?)?.toDouble() ?? 0).clamp(0.0, 100.0);
    return _lineGross(l) * (1 - disc / 100.0);
  }

  double _lineTaxAmount(Map<String, dynamic> l) {
    final tax = ((l['tax_percent'] as num?)?.toDouble() ?? 0).clamp(0.0, 100.0);
    return _lineNetAfterLineDiscount(l) * (tax / 100.0);
  }

  double _lineFinal(Map<String, dynamic> l) {
    return _lineNetAfterLineDiscount(l) + _lineTaxAmount(l);
  }

  double _linesSubtotal() {
    var s = 0.0;
    for (final l in _lines) {
      s += _lineFinal(l);
    }
    return s;
  }

  double _grandTotal() {
    var afterHeader = _linesSubtotal();
    final disc = (_discount ?? 0).clamp(0.0, 100.0);
    if (disc > 0) {
      afterHeader *= (1 - disc / 100.0);
    }
    var total = afterHeader;
    if (_freightType == 'separate') {
      total += _freight ?? 0;
    }
    total += _brokerCommissionMoney();
    return total;
  }

  String? _kgHelperLine(Map<String, dynamic> l) {
    final u = (l['unit']?.toString() ?? '').toLowerCase();
    final q = (l['qty'] as num?)?.toDouble() ?? 0;
    if (q <= 0) return null;
    final kgPer = (l['default_kg_per_bag'] as num?)?.toDouble();
    if (u == 'bag' && kgPer != null && kgPer > 0) {
      final totalKg = q * kgPer;
      final uu = u.toUpperCase();
      return '${q.toStringAsFixed(q == q.roundToDouble() ? 0 : 2)} $uu × $kgPer kg'
          ' = ${totalKg.toStringAsFixed(totalKg == totalKg.roundToDouble() ? 0 : 2)} kg';
    }
    final base = (l['default_unit']?.toString() ?? '').toLowerCase();
    if (u == 'kg' && base == 'bag' && kgPer != null && kgPer > 0) {
      final bags = q / kgPer;
      return '${q.toStringAsFixed(q == q.roundToDouble() ? 0 : 2)} kg'
          ' ≈ ${bags.toStringAsFixed(2)} bag';
    }
    return null;
  }

  List<String> _allowedUnitsForLine(Map<String, dynamic> l) {
    final kg = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
    if (kg > 0) return ['bag'];
    var base = (l['default_unit']?.toString() ?? l['unit']?.toString() ?? 'kg').toLowerCase();
    if (base.isEmpty) base = 'kg';
    return [base];
  }

  double _landingPerKg(Map<String, dynamic> l) {
    final u = (l['unit'] ?? '').toString().toLowerCase();
    final kg = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
    final lc = (l['landing_cost'] as num?)?.toDouble() ?? 0;
    if (u == 'bag' && kg > 0) return lc / kg;
    return lc;
  }

  void _putLandingPerKg(Map<String, dynamic> l, double perKg) {
    final u = (l['unit'] ?? '').toString().toLowerCase();
    final kg = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
    if (u == 'bag' && kg > 0) {
      l['landing_cost'] = perKg * kg;
    } else {
      l['landing_cost'] = perKg;
    }
  }

  double? _sellingPerKg(Map<String, dynamic> l) {
    final sc = l['selling_cost'];
    if (sc == null) return null;
    final u = (l['unit'] ?? '').toString().toLowerCase();
    final kg = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
    final v = (sc as num).toDouble();
    if (u == 'bag' && kg > 0) return v / kg;
    return v;
  }

  void _putSellingPerKg(Map<String, dynamic> l, double? perKg) {
    if (perKg == null) {
      l['selling_cost'] = null;
      return;
    }
    final u = (l['unit'] ?? '').toString().toLowerCase();
    final kg = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
    if (u == 'bag' && kg > 0) {
      l['selling_cost'] = perKg * kg;
    } else {
      l['selling_cost'] = perKg;
    }
  }

  Future<void> _refreshSupplierWarning() async {
    final session = ref.read(sessionProvider);
    final sid = _supplierId;
    if (session == null || sid == null || sid.isEmpty) {
      if (mounted) setState(() => _supplierWarning = null);
      return;
    }
    try {
      final s = await ref.read(hexaApiProvider).getSupplier(
            businessId: session.primaryBusiness.id,
            supplierId: sid,
          );
      if (!mounted) return;
      final phone = (s['phone']?.toString() ?? '').trim();
      final gst = (s['gst_number']?.toString() ?? '').trim();
      final addr = (s['address']?.toString() ?? '').trim();
      setState(() {
        if (phone.isEmpty || gst.isEmpty || addr.isEmpty) {
          _supplierWarning =
              'Add supplier phone, GSTIN, and address for invoices and WhatsApp.';
        } else {
          _supplierWarning = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _supplierWarning = null);
    }
  }

  Future<void> _addLineFromCatalogHit(Map<String, dynamic> h) async {
    final name = (h['name']?.toString() ?? h['item_name']?.toString() ?? 'Item').trim();
    final id = h['id']?.toString();
    if (_lineAlreadyExists(name, id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item already added')),
        );
      }
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;

    var tax = (h['tax_percent'] as num?)?.toDouble();
    String? hsn = h['hsn_code']?.toString();
    var defaultUnit = (h['default_unit']?.toString() ?? 'kg').toLowerCase();
    double? kgPerBag = (h['default_kg_per_bag'] as num?)?.toDouble();
    var purchaseUnit = (h['default_purchase_unit']?.toString() ?? defaultUnit).toLowerCase();

    var landing = (h['last_purchase_price'] as num?)?.toDouble() ??
        (h['last_price'] as num?)?.toDouble() ??
        (h['default_landing_cost'] as num?)?.toDouble() ??
        0.0;
    var lineDisc = 0.0;
    int? linePay;

    if (id != null && _supplierId != null && _supplierId!.isNotEmpty) {
      try {
        final d = await ref.read(hexaApiProvider).supplierPurchaseDefaults(
              businessId: session.primaryBusiness.id,
              supplierId: _supplierId!,
              itemId: id,
            );
        if (d['last_price'] != null) landing = (d['last_price'] as num).toDouble();
        if (d['last_discount'] != null) lineDisc = (d['last_discount'] as num).toDouble();
        if (d['last_payment_days'] != null) linePay = (d['last_payment_days'] as num).toInt();
        tax ??= (d['item_tax_percent'] as num?)?.toDouble();
        hsn ??= d['item_hsn_code']?.toString();
        if (d['item_default_unit'] != null) {
          defaultUnit = d['item_default_unit'].toString().toLowerCase();
        }
        if (d['item_default_kg_per_bag'] != null) {
          kgPerBag = (d['item_default_kg_per_bag'] as num).toDouble();
        }
        if (landing == 0 && d['item_default_landing_cost'] != null) {
          landing = (d['item_default_landing_cost'] as num).toDouble();
        }
        if (d['item_default_purchase_unit'] != null) {
          purchaseUnit = d['item_default_purchase_unit'].toString().toLowerCase();
        }
      } catch (_) {}
    }

    tax ??= 0;
    if (hsn != null && hsn.trim().isEmpty) hsn = null;
    if (!mounted) return;
    setState(() {
      final newLine = <String, dynamic>{
        'item_name': name,
        'qty': 1.0,
        'default_unit': defaultUnit,
        'default_kg_per_bag': kgPerBag,
        'unit': purchaseUnit.isNotEmpty ? purchaseUnit : defaultUnit,
        'landing_cost': landing,
        'selling_cost': null,
        'discount': lineDisc,
        'payment_days': linePay,
        'tax_percent': tax,
        'hsn_code': hsn,
        'description': null,
        if (id != null) 'catalog_item_id': id,
      };
      final allow = _allowedUnitsForLine(newLine);
      final u0 = (newLine['unit']?.toString() ?? '').toLowerCase();
      if (allow.isNotEmpty && !allow.contains(u0)) {
        newLine['unit'] = allow.first;
      }
      _lines.add(newLine);
      _search.clear();
      _searchHits = [];
      _dirty = true;
    });
    _scheduleDraft();
  }

  String _lineUnitWarning(Map<String, dynamic> l) {
    final canonical = (l['default_unit']?.toString() ?? '').toLowerCase();
    final selected = (l['unit']?.toString() ?? '').toLowerCase();
    if (canonical.isEmpty || selected.isEmpty) return '';
    if (canonical == selected) return '';
    final kgPer = (l['default_kg_per_bag'] as num?)?.toDouble();
    if (canonical == 'bag' && selected == 'kg' && kgPer != null && kgPer > 0) {
      return 'This item uses BAG ($kgPer kg per bag). You selected KG — qty is in kg; verify conversion.';
    }
    return 'Unit differs from item master ($canonical).';
  }

  bool _lineAlreadyExists(String name, String? itemId) {
    for (final l in _lines) {
      final id = l['catalog_item_id']?.toString();
      if (itemId != null && itemId.isNotEmpty && id == itemId) return true;
      if ((l['item_name']?.toString().trim().toLowerCase() ?? '') == name.trim().toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  double _headerDiscountMoney() {
    final d = (_discount ?? 0).clamp(0.0, 100.0);
    if (d <= 0) return 0;
    return _linesSubtotal() * (d / 100.0);
  }

  double _totalTaxMoney() {
    var t = 0.0;
    for (final l in _lines) {
      t += _lineTaxAmount(l);
    }
    return t;
  }

  double _brokerCommissionMoney() {
    final p = _commission ?? 0;
    if (p <= 0) return 0;
    final base = _linesSubtotal() - _headerDiscountMoney();
    return base * (p / 100.0);
  }

  int _recencyBoostForItemName(String nameKey) {
    final h = _historyByItem[nameKey.trim().toLowerCase()];
    if (h == null) return 0;
    final ds = h['last_date']?.toString();
    if (ds == null || ds.isEmpty) return 0;
    final dt = DateTime.tryParse(ds);
    if (dt == null) return 0;
    final days = DateTime.now().difference(dt).inDays;
    final clamped = days.clamp(0, 730);
    return ((730 - clamped) / 13).floor();
  }

  int _searchScore(String q, Map<String, dynamic> item) {
    final name = (item['name']?.toString() ?? '').toLowerCase();
    var score = 0;
    if (name.startsWith(q)) score += 30;
    if (_supplierMappedItemIds.contains(item['id']?.toString())) score += 120;
    if (_supplierRecentItemNames.contains(name)) score += 95;
    if (item['_same_supplier'] == true) score += 110;
    if (_historyByItem.containsKey(name)) score += 40;
    score += ((item['used_count'] as int?) ?? 0) * 3;
    score += _recencyBoostForItemName(name);
    return score;
  }

  Future<void> _runSearch(String q) async {
    final session = ref.read(sessionProvider);
    if (session == null || q.trim().length < 2) {
      setState(() => _searchHits = []);
      return;
    }
    try {
      final res = await ref.read(hexaApiProvider).unifiedSearch(
            businessId: session.primaryBusiness.id,
            q: q.trim(),
          );
      final items = res['catalog_items'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items.take(40)) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final key = (m['name']?.toString() ?? '').trim().toLowerCase();
          final h = _historyByItem[key];
          if (h != null) {
            final prices = h['prices'] as List<double>;
            final recent = prices.length > 5 ? prices.sublist(prices.length - 5) : prices;
            final avg = recent.isEmpty ? null : recent.reduce((a, b) => a + b) / recent.length;
            m['last_price'] = h['last_price'];
            m['avg_5'] = avg;
            m['last_date'] = h['last_date'];
            m['used_count'] = h['used_count'];
            final sups = h['supplier_ids'] as Set<String>?;
            if (_supplierId != null && sups != null && sups.contains(_supplierId)) {
              m['_same_supplier'] = true;
            }
          }
          m['_score'] = _searchScore(q.trim().toLowerCase(), m);
          list.add(m);
        }
      }
      list.sort((a, b) => ((b['_score'] as int?) ?? 0).compareTo((a['_score'] as int?) ?? 0));
      if (mounted) setState(() => _searchHits = list);
    } catch (_) {
      if (mounted) setState(() => _searchHits = []);
    }
  }

  String? _linesValidationError() {
    for (final l in _lines) {
      final q = (l['qty'] as num?)?.toDouble() ?? 0;
      if (q <= 0) {
        return 'Each line needs quantity greater than zero.';
      }
      final rate = (l['landing_cost'] as num?)?.toDouble() ?? 0;
      if (rate < 0) {
        final name = l['item_name']?.toString() ?? 'Item';
        return 'Line "$name" has a negative landing rate.';
      }
      final u = (l['unit'] ?? '').toString().toLowerCase();
      final kg = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
      if (u == 'bag' && kg <= 0) {
        final name = l['item_name']?.toString() ?? 'Item';
        return 'Line "$name": bag unit needs kg-per-bag on the catalog item.';
      }
    }
    return null;
  }

  Future<void> _savePurchase() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line item.')),
      );
      return;
    }
    final lineErr = _linesValidationError();
    if (lineErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lineErr)));
      return;
    }
    final body = {
      ..._payload(),
      'lines': _lines
          .map(
            (l) => {
              'item_name': l['item_name'],
              'qty': l['qty'],
              'unit': l['unit'] ?? 'kg',
              'landing_cost': l['landing_cost'],
              if (l['selling_cost'] != null) 'selling_cost': l['selling_cost'],
              if (l['discount'] != null) 'discount': l['discount'],
              if (l['tax_percent'] != null) 'tax_percent': l['tax_percent'],
              if (l['payment_days'] != null) 'payment_days': l['payment_days'],
              if (l['hsn_code'] != null && (l['hsn_code'] as String).trim().isNotEmpty)
                'hsn_code': (l['hsn_code'] as String).trim(),
              if (l['description'] != null && (l['description'] as String).trim().isNotEmpty)
                'description': (l['description'] as String).trim(),
              if (l['catalog_item_id'] != null) 'catalog_item_id': l['catalog_item_id'],
            },
          )
          .toList(),
    };
    final dupBody = <String, dynamic>{
      'purchase_date': DateFormat('yyyy-MM-dd').format(_purchaseDate),
      'total_amount': _grandTotal(),
      'lines': body['lines'],
    };
    if (_supplierId != null && _supplierId!.isNotEmpty) {
      dupBody['supplier_id'] = _supplierId;
    }
    try {
      final dup = await ref.read(hexaApiProvider).checkTradePurchaseDuplicate(
            businessId: session.primaryBusiness.id,
            body: dupBody,
          );
      if (dup['duplicate'] == true) {
        final sameEdit = _editPurchaseId != null &&
            dup['existing_id']?.toString() == _editPurchaseId;
        if (!sameEdit && mounted) {
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Possible duplicate'),
              content: Text(dup['message']?.toString() ?? 'Save anyway?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (go != true) return;
        }
      }
      final Map<String, dynamic> saved;
      if (_editPurchaseId != null) {
        final upd = Map<String, dynamic>.from(body)..remove('human_id');
        saved = await ref.read(hexaApiProvider).updateTradePurchase(
              businessId: session.primaryBusiness.id,
              purchaseId: _editPurchaseId!,
              body: upd,
            );
      } else {
        saved = await ref.read(hexaApiProvider).createTradePurchase(
              businessId: session.primaryBusiness.id,
              body: body,
            );
        await ref.read(hexaApiProvider).deleteTradePurchaseDraft(
              businessId: session.primaryBusiness.id,
            );
      }
      ref.invalidate(tradePurchasesListProvider);
      if (!mounted) return;
      await showPurchaseSavedSheet(
        context,
        ref,
        savedJson: saved,
        wasEdit: _editPurchaseId != null,
      );
      if (_editPurchaseId == null) {
        await _loadNextPurchaseId();
      }
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  Future<void> _handleLeaveRequest() async {
    if (!mounted) return;
    if (_leaveInFlight) return;
    if (!_dirty) {
      context.pop();
      return;
    }
    _leaveInFlight = true;
    String? action;
    try {
      action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save draft?'),
          content: const Text('You have unsaved changes. Save a draft to continue later?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save draft'),
            ),
          ],
        ),
      );
    } finally {
      _leaveInFlight = false;
    }
    if (!mounted || action == null || action == 'cancel') return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (action == 'save') {
      await ref.read(hexaApiProvider).putTradePurchaseDraft(
            businessId: session.primaryBusiness.id,
            step: _step,
            payload: _payload(),
          );
      if (mounted) context.pop();
    } else if (action == 'discard') {
      await ref.read(hexaApiProvider).deleteTradePurchaseDraft(
            businessId: session.primaryBusiness.id,
          );
      if (mounted) context.pop();
    }
  }

  Widget _stepHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildStep0(AsyncValue<List<Map<String, dynamic>>> suppliers) {
    String supplierName(List<Map<String, dynamic>> rows) {
      if (_supplierId == null) return '';
      for (final r in rows) {
        if (r['id']?.toString() == _supplierId) return r['name']?.toString() ?? '';
      }
      return '';
    }

    return ListView(
      padding: _pagePadding,
      children: [
        _stepHeader('Purchase header'),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 18),
                    const SizedBox(width: 8),
                    const Text('Purchase ID: '),
                    Expanded(
                      child: Text(_purchaseHumanId,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Scan bill',
              onPressed: () async {
                final lines = await context.push<List<Map<String, dynamic>>>('/purchase/scan');
                if (!mounted || lines == null || lines.isEmpty) return;
                setState(() {
                  for (final raw in lines) {
                    final m = Map<String, dynamic>.from(raw);
                    m['default_unit'] = (m['unit'] ?? 'kg').toString().toLowerCase();
                    m['default_kg_per_bag'] = null;
                    m['discount'] = m['discount'] ?? 0.0;
                    m['tax_percent'] = m['tax_percent'] ?? 0.0;
                    m['payment_days'] = m['payment_days'];
                    m['hsn_code'] = m['hsn_code'];
                    m['description'] = m['description'];
                    final allow = _allowedUnitsForLine(m);
                    m['unit'] = allow.isNotEmpty ? allow.first : 'kg';
                    _lines.add(m);
                  }
                  _dirty = true;
                });
                _scheduleDraft();
              },
              icon: const Icon(Icons.document_scanner_outlined),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Purchase date', isDense: true),
          child: Text(DateFormat.yMMMd().format(_purchaseDate)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _purchaseDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) {
                setState(() {
                  _purchaseDate = d;
                  _markDirty();
                });
              }
            },
            icon: const Icon(Icons.calendar_today_rounded),
            label: const Text('Change date'),
          ),
        ),
        suppliers.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load suppliers'),
          data: (rows) => DropdownButtonFormField<String>(
            key: ValueKey(_supplierId),
            initialValue: _supplierId != null && rows.any((r) => r['id']?.toString() == _supplierId)
                ? _supplierId
                : null,
            decoration: const InputDecoration(labelText: 'Supplier *', isDense: true),
            items: rows
                .map((r) => DropdownMenuItem<String>(
                      value: r['id']?.toString(),
                      child: Text(r['name']?.toString() ?? ''),
                    ))
                .toList(),
            onChanged: (v) {
              setState(() {
                _supplierId = v;
                if (v != null) {
                  final s = rows.firstWhere(
                    (r) => r['id']?.toString() == v,
                    orElse: () => <String, dynamic>{},
                  );
                  if (s.isNotEmpty) {
                    _applySupplierDefaults(s);
                    _refreshSupplierMemory(s);
                    _syncBrokerCommissionFromList(ref.read(brokersListProvider).valueOrNull, force: true);
                  }
                }
                _markDirty();
              });
              unawaited(_refreshSupplierWarning());
            },
          ),
        ),
        const SizedBox(height: 6),
        ref.watch(brokersListProvider).when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (brokers) => DropdownButtonFormField<String?>(
                key: ValueKey(_brokerId),
                initialValue: _brokerId != null && brokers.any((b) => b['id']?.toString() == _brokerId)
                    ? _brokerId
                    : null,
                decoration: const InputDecoration(labelText: 'Broker (optional)', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('None')),
                  ...brokers.map(
                    (b) => DropdownMenuItem<String?>(
                      value: b['id']?.toString(),
                      child: Text(b['name']?.toString() ?? ''),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _brokerId = v;
                    if (v == null) {
                      _commission = null;
                      _commissionCtrl.clear();
                    } else {
                      _syncBrokerCommissionFromList(brokers, force: true);
                    }
                    _markDirty();
                  });
                },
              ),
            ),
        if (_supplierWarning != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFEA580C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _supplierWarning!,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_headerError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _headerError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 8),
        suppliers.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => DefaultsAppliedCard(
            supplierLabel: supplierName(rows),
            freightType: _freightType,
            onFreightTypeChanged: (ft) {
              setState(() {
                _freightType = ft;
                if (_freightType == 'included') {
                  _freight = 0;
                  _freightCtrl.text = '0';
                } else {
                  _freight = (_delivered ?? 0) + (_billty ?? 0);
                  _freightCtrl.text = (_freight ?? 0).toStringAsFixed(2);
                }
                _dirty = true;
              });
              _scheduleDraft();
            },
            deliveredController: _deliveredCtrl,
            billtyController: _billtyCtrl,
            freightController: _freightCtrl,
            freightReadOnly: _freightType == 'included',
            onDeliveredChanged: (t) {
              _delivered = double.tryParse(t);
              if (_freightType == 'separate') {
                _freight = (_delivered ?? 0) + (_billty ?? 0);
                _freightCtrl.text = (_freight ?? 0).toStringAsFixed(2);
              }
              _markDirty();
            },
            onBilltyChanged: (t) {
              _billty = double.tryParse(t);
              if (_freightType == 'separate') {
                _freight = (_delivered ?? 0) + (_billty ?? 0);
                _freightCtrl.text = (_freight ?? 0).toStringAsFixed(2);
              }
              _markDirty();
            },
            onFreightChanged: (t) {
              if (_freightType == 'included') return;
              _freight = double.tryParse(t);
              _markDirty();
            },
          ),
        ),
      ],
    );
  }

  Widget _liveLineMath(Map<String, dynamic> l, NumberFormat money) {
    final q = (l['qty'] as num?)?.toDouble() ?? 0;
    final u = (l['unit'] ?? '').toString().toUpperCase();
    final kgPer = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
    final landKg = _landingPerKg(l);
    final sellKg = _sellingPerKg(l);
    final bagLand = (u == 'BAG' && kgPer > 0) ? landKg * kgPer : landKg;
    final bagSell = (sellKg != null && u == 'BAG' && kgPer > 0) ? sellKg * kgPer : sellKg;
    final total = _lineFinal(l);
    if (u == 'BAG' && kgPer > 0) {
      final kgTot = q * kgPer;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Per KG → ${money.format(landKg)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Text('Per BAG → ${money.format(bagLand)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Text(
            '$q $u (${kgTot.toStringAsFixed(kgTot == kgTot.roundToDouble() ? 0 : 1)} kg) → Line total ${money.format(total)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (bagSell != null)
            Text('Selling per BAG → ${money.format(bagSell)}', style: const TextStyle(fontSize: 11.5)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Per KG → ${money.format(landKg)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        Text(
          '$q $u → Line total ${money.format(total)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: _pagePadding,
      children: [
        _stepHeader('Items'),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search items (supplier-aware)',
            hintText: 'Supplier, item, category…',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () => _runSearch(v));
          },
        ),
        const SizedBox(height: 6),
        if (_searchHits.isNotEmpty)
          ..._searchHits.map((h) {
            final name = h['name']?.toString() ?? h['item_name']?.toString() ?? 'Item';
            final score = (h['_score'] as int?) ?? 0;
            final used = h['used_count'];
            final kgPer = (h['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
            final last = (h['last_price'] as num?)?.toDouble();
            String? lastKg;
            if (last != null) {
              final pu = (h['default_purchase_unit']?.toString() ?? '').toLowerCase();
              if (pu == 'bag' && kgPer > 0) {
                lastKg = '${money.format(last / kgPer)}/kg';
              } else {
                lastKg = '${money.format(last)}/kg';
              }
            }
            final subtitleParts = <String>[
              if (lastKg != null) 'Last purchase: $lastKg',
              if (used is num && used > 0) 'Used ${used.toInt()}×',
              if (h['_same_supplier'] == true) 'Supplier: match',
              if ((h['category_name']?.toString() ?? '').trim().isNotEmpty)
                h['category_name'].toString(),
            ];
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(subtitleParts.join(' · ')),
              trailing: score >= 100 ? const Icon(Icons.auto_awesome_rounded, size: 16) : null,
              onTap: () async {
                await _addLineFromCatalogHit(h);
              },
            );
          }),
        const SizedBox(height: 6),
        ..._lines.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          final uopts = _allowedUnitsForLine(l);
          final udisp = uopts.isNotEmpty ? uopts.first.toUpperCase() : 'KG';
          final qtyErr = ((l['qty'] as num?)?.toDouble() ?? 0) <= 0;
          return Card(
            key: ValueKey('line_$i'),
            elevation: 1,
            shadowColor: Colors.black26,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l['item_name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _lines.removeAt(i);
                            _markDirty();
                          });
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  if (_lineUnitWarning(l).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        _lineUnitWarning(l),
                        style: TextStyle(
                          color: cs.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('qty_${i}_${l['unit']}'),
                          initialValue: (l['qty'] as num?)?.toString() ?? '1',
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                            errorText: qtyErr ? 'Enter quantity' : null,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            l['qty'] = double.tryParse(t) ?? 1.0;
                            _markDirty();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                          child: Text(udisp, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                  if (_kgHelperLine(l) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _kgHelperLine(l)!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('lpk_$i'),
                          initialValue: _landingPerKg(l).toString(),
                          decoration: const InputDecoration(
                            labelText: 'Landing ₹/kg',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            final v = double.tryParse(t);
                            if (v == null) return;
                            _putLandingPerKg(l, v);
                            _markDirty();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('spk_$i'),
                          initialValue: _sellingPerKg(l)?.toString() ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Selling ₹/kg',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            final v = double.tryParse(t);
                            _putSellingPerKg(l, v);
                            _markDirty();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _liveLineMath(l, money),
                  const SizedBox(height: 4),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Show advanced fields', style: TextStyle(fontWeight: FontWeight.w600)),
                    children: [
                      TextFormField(
                        key: ValueKey('disc_$i'),
                        initialValue: (l['discount'] as num?)?.toString() ?? '0',
                        decoration: const InputDecoration(labelText: 'Line discount %', isDense: true),
                        keyboardType: TextInputType.number,
                        onChanged: (t) {
                          l['discount'] = (double.tryParse(t) ?? 0).clamp(0, 100);
                          _markDirty();
                        },
                      ),
                      TextFormField(
                        key: ValueKey('pay_$i'),
                        initialValue: (l['payment_days'] as num?)?.toString() ?? '',
                        decoration: const InputDecoration(labelText: 'Payment days (line)', isDense: true),
                        keyboardType: TextInputType.number,
                        onChanged: (t) {
                          l['payment_days'] = int.tryParse(t);
                          _markDirty();
                        },
                      ),
                      TextFormField(
                        key: ValueKey('hsn_$i'),
                        initialValue: l['hsn_code']?.toString() ?? '',
                        decoration: const InputDecoration(labelText: 'HSN (optional)', isDense: true),
                        onChanged: (t) {
                          l['hsn_code'] = t.trim().isEmpty ? null : t.trim();
                          _markDirty();
                        },
                      ),
                      TextFormField(
                        key: ValueKey('tax_$i'),
                        initialValue: (l['tax_percent'] as num?)?.toString() ?? '0',
                        decoration: const InputDecoration(labelText: 'Tax %', isDense: true),
                        keyboardType: TextInputType.number,
                        onChanged: (t) {
                          l['tax_percent'] = double.tryParse(t) ?? 0;
                          _markDirty();
                        },
                      ),
                      TextFormField(
                        key: ValueKey('desc_$i'),
                        initialValue: l['description']?.toString() ?? '',
                        decoration: const InputDecoration(labelText: 'Description', isDense: true),
                        maxLines: 2,
                        onChanged: (t) {
                          l['description'] = t.trim().isEmpty ? null : t.trim();
                          _markDirty();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  ({double bags, double kg}) _totBagsAndKg() {
    var bags = 0.0;
    var kg = 0.0;
    for (final l in _lines) {
      final q = (l['qty'] as num?)?.toDouble() ?? 0;
      final u = (l['unit'] ?? '').toString().toLowerCase();
      final kpb = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
      if (u == 'bag' && kpb > 0) {
        bags += q;
        kg += q * kpb;
      } else {
        kg += q;
      }
    }
    return (bags: bags, kg: kg);
  }

  Widget _buildStep2() {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final cs = Theme.of(context).colorScheme;
    final suppliers = ref.watch(suppliersListProvider).valueOrNull ?? const [];
    final brokers = ref.watch(brokersListProvider).valueOrNull ?? const [];
    final supplierName = suppliers
        .firstWhere(
          (r) => r['id']?.toString() == _supplierId,
          orElse: () => <String, dynamic>{},
        )['name']
        ?.toString();
    final brokerName = brokers
        .firstWhere(
          (r) => r['id']?.toString() == _brokerId,
          orElse: () => <String, dynamic>{},
        )['name']
        ?.toString();
    final subtotal = _linesSubtotal();
    final headerDisc = _headerDiscountMoney();
    final taxTotal = _totalTaxMoney();
    final brokerAmt = _brokerCommissionMoney();
    final grand = _grandTotal();
    final tot = _totBagsAndKg();

    Widget row(String left, String right, {bool bold = false, double gap = 3}) {
      return Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                left,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  fontSize: bold ? 15 : 13,
                ),
              ),
            ),
            Text(
              right,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                fontSize: bold ? 15 : 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: _pagePadding,
      children: [
        _stepHeader('Summary'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Supplier · ${supplierName ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Broker · ${brokerName ?? '—'}', style: TextStyle(color: cs.onSurfaceVariant)),
                Text('Date · ${DateFormat.yMMMd().format(_purchaseDate)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ..._lines.map((l) {
          final name = l['item_name']?.toString() ?? '';
          final u = (l['unit']?.toString() ?? '').toUpperCase();
          final q = (l['qty'] as num?)?.toDouble() ?? 0;
          final kgPer = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
          final kgLine = (u == 'BAG' && kgPer > 0) ? q * kgPer : q;
          final land = _landingPerKg(l);
          final sell = _sellingPerKg(l);
          final pk = (sell != null) ? (sell - land) : null;
          final profitStyle = TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: pk == null
                ? cs.onSurfaceVariant
                : (pk >= 0 ? const Color(0xFF15803D) : const Color(0xFFDC2626)),
          );
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Item: $name', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    u == 'BAG' && kgPer > 0
                        ? '$q $u (${kgLine.toStringAsFixed(kgLine == kgLine.roundToDouble() ? 0 : 1)} kg)'
                        : '$q $u',
                    style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text('Landing: ${fmt.format(land)}/kg', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (sell != null) Text('Selling: ${fmt.format(sell)}/kg', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (pk != null) Text('Profit: ${fmt.format(pk)}/kg', style: profitStyle),
                  const Divider(height: 14),
                  Text('Line total ${fmt.format(_lineFinal(l))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        Card(
          color: cs.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('TOTAL', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                row('Total bags', tot.bags.toStringAsFixed(tot.bags == tot.bags.roundToDouble() ? 0 : 1)),
                row('Total kg', tot.kg.toStringAsFixed(tot.kg == tot.kg.roundToDouble() ? 0 : 1)),
                row('Subtotal', fmt.format(subtotal)),
                if (headerDisc > 0) row('Header discount', '- ${fmt.format(headerDisc)}'),
                row('Tax (lines)', fmt.format(taxTotal)),
                if (_freightType == 'separate' && (_freight ?? 0) > 0) row('Freight', fmt.format(_freight ?? 0)),
                if (brokerAmt > 0) row('Broker', fmt.format(brokerAmt)),
                const Divider(height: 12),
                row('Final total', fmt.format(grand), bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(brokersListProvider, (prev, next) {
      final brokers = next.asData?.value;
      if (brokers == null) return;
      if (!_syncBrokerCommissionFromList(brokers, force: false)) return;
      if (mounted) setState(() {});
    });

    final suppliers = ref.watch(suppliersListProvider);
    final title = switch (_step) {
      0 => 'New Purchase',
      1 => 'Purchase Items',
      _ => 'Review Purchase',
    };

    Widget body;
    if (_step == 0) {
      body = _buildStep0(suppliers);
    } else if (_step == 1) {
      body = _buildStep1();
    } else {
      body = _buildStep2();
    }

    Widget bottom;
    if (_step == 0) {
      bottom = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: () {
            if (!_validateHeader()) return;
            setState(() {
              _step = 1;
              _scheduleDraft();
            });
          },
          child: const Text('Next'),
        ),
      );
    } else if (_step == 1) {
      bottom = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  _search.requestFocus();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  final err = _linesValidationError();
                  if (err != null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    return;
                  }
                  setState(() {
                    _step = 2;
                    _scheduleDraft();
                  });
                },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      );
    } else {
      bottom = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _step = 0;
                    _scheduleDraft();
                  });
                },
                child: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _savePurchase,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleLeaveRequest();
      },
      child: FullScreenFormScaffold(
        title: title,
        subtitle: 'Step ${_step + 1} of 3',
        actions: [
          IconButton(
            onPressed: _handleLeaveRequest,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
        body: body,
        bottom: bottom,
      ),
    );
  }
}
