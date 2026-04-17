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

class PurchaseWizardPage extends ConsumerStatefulWidget {
  const PurchaseWizardPage({super.key});

  @override
  ConsumerState<PurchaseWizardPage> createState() => _PurchaseWizardPageState();
}

class _PurchaseWizardPageState extends ConsumerState<PurchaseWizardPage> {
  int _step = 0;
  bool _dirty = false;
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

  final List<Map<String, dynamic>> _lines = [];
  List<Map<String, dynamic>> _searchHits = [];
  final Set<String> _supplierMappedItemIds = <String>{};
  final Set<String> _supplierRecentItemNames = <String>{};
  final Map<String, Map<String, dynamic>> _historyByItem = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDraft();
      await _bootstrapHistoryCache();
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
        _dirty = true;
        _scheduleDraft();
      });
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
    });
  }

  Map<String, dynamic> _payload() {
    return {
      'human_id': _purchaseHumanId,
      'purchase_date': DateFormat('yyyy-MM-dd').format(_purchaseDate),
      'supplier_id': _supplierId,
      'broker_id': _brokerId,
      'freight_type': _freightType,
      'payment_days': _paymentDays,
      'discount': _discount,
      'commission_percent': _commission,
      'delivered_rate': _delivered,
      'billty_rate': _billty,
      'freight_amount': _freight,
      'lines': List<Map<String, dynamic>>.from(_lines),
    };
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
    _paymentDays = (s['default_payment_days'] as num?)?.toInt() ?? _paymentDays;
    _discount = (s['default_discount'] as num?)?.toDouble() ?? _discount;
    _delivered = (s['default_delivered_rate'] as num?)?.toDouble() ?? _delivered;
    _billty = (s['default_billty_rate'] as num?)?.toDouble() ?? _billty;
    final freightType = s['freight_type']?.toString();
    if (freightType == 'included' || freightType == 'separate') {
      _freightType = freightType!;
    }
    final bid = s['broker_id']?.toString();
    if (bid != null && bid.isNotEmpty) {
      _brokerId = bid;
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

  double _lineGross(Map<String, dynamic> l) {
    final q = (l['qty'] as num?)?.toDouble() ?? 0;
    final lc = (l['landing_cost'] as num?)?.toDouble() ?? 0;
    return q * lc;
  }

  double _lineNetAfterLineDiscount(Map<String, dynamic> l) {
    final disc = (l['discount'] as num?)?.toDouble() ?? 0;
    return _lineGross(l) * (1 - disc / 100.0);
  }

  double _lineTaxAmount(Map<String, dynamic> l) {
    final tax = (l['tax_percent'] as num?)?.toDouble() ?? 0;
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
    var s = _linesSubtotal();
    final disc = _discount ?? 0;
    if (disc > 0) {
      s *= (1 - disc / 100.0);
    }
    if (_freightType == 'separate') {
      s += _freight ?? 0;
    }
    return s;
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
    var base = (l['default_unit']?.toString() ?? l['unit']?.toString() ?? 'kg').toLowerCase();
    if (base.isEmpty) base = 'kg';
    if (base == 'bag') {
      final k = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
      if (k > 0) return ['bag', 'kg'];
      return ['bag'];
    }
    return [base];
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
    var linePay = _paymentDays;

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

  Widget _lineUnitPicker(int i, Map<String, dynamic> l) {
    final opts = _allowedUnitsForLine(l);
    final fallback = opts.isNotEmpty ? opts.first : 'kg';
    if (opts.length == 1) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Unit'),
        child: Text(fallback.toUpperCase()),
      );
    }
    final cur = (l['unit']?.toString() ?? fallback).toLowerCase();
    final v = opts.contains(cur) ? cur : fallback;
    if (!opts.contains(cur)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!opts.contains((l['unit']?.toString() ?? '').toLowerCase())) {
          setState(() {
            l['unit'] = v;
            _dirty = true;
          });
          _scheduleDraft();
        }
      });
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('unit_${i}_$v'),
      initialValue: v,
      decoration: const InputDecoration(labelText: 'Unit'),
      items: opts
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(e.toUpperCase()),
            ),
          )
          .toList(),
      onChanged: (newU) {
        if (newU == null) return;
        final oldU = (l['unit']?.toString() ?? '').toLowerCase();
        if (newU == oldU) return;
        var qty = (l['qty'] as num?)?.toDouble() ?? 1;
        final kgPer = (l['default_kg_per_bag'] as num?)?.toDouble() ?? 0;
        if (kgPer > 0) {
          if (oldU == 'bag' && newU == 'kg') {
            qty *= kgPer;
          } else if (oldU == 'kg' && newU == 'bag') {
            qty /= kgPer;
          }
        }
        l['unit'] = newU;
        l['qty'] = qty;
        _markDirty();
      },
    );
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
    if ((_discount ?? 0) <= 0) return 0;
    return _linesSubtotal() * ((_discount ?? 0) / 100.0);
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

  int _searchScore(String q, Map<String, dynamic> item) {
    final name = (item['name']?.toString() ?? '').toLowerCase();
    var score = 0;
    if (name.startsWith(q)) score += 30;
    if (_supplierMappedItemIds.contains(item['id']?.toString())) score += 120;
    if (_supplierRecentItemNames.contains(name)) score += 95;
    if (item['_same_supplier'] == true) score += 110;
    if (_historyByItem.containsKey(name)) score += 40;
    score += ((item['used_count'] as int?) ?? 0) * 3;
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

  Future<void> _savePurchase() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line item.')),
      );
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
      if (dup['duplicate'] == true && mounted) {
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
      final created = await ref.read(hexaApiProvider).createTradePurchase(
            businessId: session.primaryBusiness.id,
            body: body,
          );
      await ref.read(hexaApiProvider).deleteTradePurchaseDraft(
            businessId: session.primaryBusiness.id,
          );
      ref.invalidate(tradePurchasesListProvider);
      if (!mounted) return;
      final hid = created['human_id']?.toString() ?? _purchaseHumanId;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Purchase created'),
          content: Text('ID: $hid'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      await _loadNextPurchaseId();
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
    if (!_dirty) {
      context.pop();
      return;
    }
    final action = await showDialog<String>(
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildStep0(AsyncValue<List<Map<String, dynamic>>> suppliers) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
      children: [
        _stepHeader('Purchase header'),
        Container(
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
              Text(_purchaseHumanId, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Purchase date'),
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
            decoration: const InputDecoration(labelText: 'Supplier *'),
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
                  }
                }
                _markDirty();
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        ref.watch(brokersListProvider).when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (brokers) => DropdownButtonFormField<String?>(
                key: ValueKey(_brokerId),
                initialValue: _brokerId != null && brokers.any((b) => b['id']?.toString() == _brokerId)
                    ? _brokerId
                    : null,
                decoration: const InputDecoration(labelText: 'Broker'),
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
                    if (v != null) {
                      final b = brokers.firstWhere(
                        (row) => row['id']?.toString() == v,
                        orElse: () => <String, dynamic>{},
                      );
                      final cv = (b['commission_value'] as num?)?.toDouble();
                      if (cv != null) {
                        _commission = cv;
                        _commissionCtrl.text = cv.toString();
                      }
                    }
                    _markDirty();
                  });
                },
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
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'included', label: Text('Freight Included')),
            ButtonSegment(value: 'separate', label: Text('Freight Separate')),
          ],
          selected: {_freightType},
          onSelectionChanged: (v) {
            setState(() {
              _freightType = v.first;
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
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _paymentDaysCtrl,
          decoration: const InputDecoration(labelText: 'Payment days'),
          keyboardType: TextInputType.number,
          onChanged: (t) {
            _paymentDays = int.tryParse(t);
            _markDirty();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _discountCtrl,
          decoration: const InputDecoration(labelText: 'Header discount %'),
          keyboardType: TextInputType.number,
          onChanged: (t) {
            _discount = double.tryParse(t);
            _markDirty();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _commissionCtrl,
          decoration: const InputDecoration(labelText: 'Broker commission %'),
          keyboardType: TextInputType.number,
          onChanged: (t) {
            _commission = double.tryParse(t);
            _markDirty();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _deliveredCtrl,
          decoration: const InputDecoration(labelText: 'Delivered rate'),
          keyboardType: TextInputType.number,
          onChanged: (t) {
            _delivered = double.tryParse(t);
            if (_freightType == 'separate') {
              _freight = (_delivered ?? 0) + (_billty ?? 0);
              _freightCtrl.text = (_freight ?? 0).toStringAsFixed(2);
            }
            _markDirty();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _billtyCtrl,
          decoration: const InputDecoration(labelText: 'Billty rate'),
          keyboardType: TextInputType.number,
          onChanged: (t) {
            _billty = double.tryParse(t);
            if (_freightType == 'separate') {
              _freight = (_delivered ?? 0) + (_billty ?? 0);
              _freightCtrl.text = (_freight ?? 0).toStringAsFixed(2);
            }
            _markDirty();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _freightCtrl,
          readOnly: _freightType == 'included',
          decoration: InputDecoration(
            labelText: _freightType == 'included' ? 'Freight (included — not added to total)' : 'Freight amount',
          ),
          keyboardType: TextInputType.number,
          onChanged: (t) {
            if (_freightType == 'included') return;
            _freight = double.tryParse(t);
            _markDirty();
          },
        ),
      ],
    );
  }

  Widget _buildStep1() {
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
      children: [
        _stepHeader('Items'),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search items',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () => _runSearch(v));
          },
        ),
        const SizedBox(height: 8),
        if (_searchHits.isNotEmpty)
          ..._searchHits.map((h) {
            final name = h['name']?.toString() ?? h['item_name']?.toString() ?? 'Item';
            final score = (h['_score'] as int?) ?? 0;
            final used = h['used_count'];
            final subtitleParts = <String>[
              if (h['_same_supplier'] == true) 'Same supplier',
              if (used is num && used > 0) 'Used ${used.toInt()}×',
              if ((h['category_name']?.toString() ?? '').trim().isNotEmpty)
                h['category_name'].toString(),
              if (h['avg_5'] != null) 'Avg5 ${money.format(h['avg_5'])}',
              if (h['last_price'] != null) 'Last ${money.format(h['last_price'])}',
            ];
            return ListTile(
              dense: true,
              title: Text(name),
              subtitle: Text(subtitleParts.join(' · ')),
              trailing: score >= 100 ? const Icon(Icons.auto_awesome_rounded, size: 16) : null,
              onTap: () async {
                await _addLineFromCatalogHit(h);
              },
            );
          }),
        const SizedBox(height: 8),
        ..._lines.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return Card(
            key: ValueKey('line_$i'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l['item_name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('qty_${i}_${l['qty']}'),
                          initialValue: (l['qty'] as num?)?.toString() ?? '1',
                          decoration: const InputDecoration(labelText: 'Qty'),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            l['qty'] = double.tryParse(t) ?? 1.0;
                            _markDirty();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _lineUnitPicker(i, l)),
                    ],
                  ),
                  if (_kgHelperLine(l) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _kgHelperLine(l)!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('land_$i'),
                          initialValue: (l['landing_cost'] as num?)?.toString() ?? '0',
                          decoration: const InputDecoration(labelText: 'Landing cost *'),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            l['landing_cost'] = double.tryParse(t) ?? 0;
                            _markDirty();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('sell_$i'),
                          initialValue: l['selling_cost'] != null ? (l['selling_cost'] as num).toString() : '',
                          decoration: const InputDecoration(labelText: 'Selling cost'),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            l['selling_cost'] = double.tryParse(t);
                            _markDirty();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('disc_$i'),
                          initialValue: (l['discount'] as num?)?.toString() ?? '0',
                          decoration: const InputDecoration(labelText: 'Line discount %'),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            l['discount'] = double.tryParse(t) ?? 0;
                            _markDirty();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('pay_$i'),
                          initialValue: (l['payment_days'] as num?)?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'Line payment days'),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            l['payment_days'] = int.tryParse(t);
                            _markDirty();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'HSN: ${l['hsn_code'] ?? '—'}   ·   Tax: ${(l['tax_percent'] as num?) ?? 0}% (from item)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Net ${money.format(_lineNetAfterLineDiscount(l))} + Tax ${money.format(_lineTaxAmount(l))} = ${money.format(_lineFinal(l))}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep2() {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
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

    Widget row(String left, String right, {bool bold = false, double gap = 4}) {
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
      children: [
        _stepHeader('Summary'),
        row('Purchase ID', _purchaseHumanId),
        row('Supplier', supplierName ?? '—'),
        row('Broker', brokerName ?? '—'),
        row('Freight', _freightType == 'included' ? 'Included in rate' : 'Separate (+${fmt.format(_freight ?? 0)})'),
        const Divider(height: 20),
        Text('ITEMS', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ..._lines.map((l) {
          final name = l['item_name']?.toString() ?? '';
          final u = (l['unit']?.toString() ?? '').toUpperCase();
          final rate = (l['landing_cost'] as num?)?.toDouble() ?? 0;
          final disc = (l['discount'] as num?)?.toDouble() ?? 0;
          final taxPct = (l['tax_percent'] as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                row(
                  '${l['qty']} $u × ${fmt.format(rate)}',
                  fmt.format(_lineGross(l)),
                  gap: 2,
                ),
                if (disc > 0) row('Line discount ($disc%)', '- ${fmt.format(_lineGross(l) - _lineNetAfterLineDiscount(l))}', gap: 2),
                row('Tax ($taxPct%)', fmt.format(_lineTaxAmount(l)), gap: 2),
                row('Line final', fmt.format(_lineFinal(l)), bold: true, gap: 2),
              ],
            ),
          );
        }),
        const Divider(height: 20),
        Text('TOTAL', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        row('Subtotal (lines)', fmt.format(subtotal)),
        if (headerDisc > 0) row('Header discount', '- ${fmt.format(headerDisc)}'),
        row('Tax (sum of lines)', fmt.format(taxTotal)),
        if (_freightType == 'separate' && (_freight ?? 0) > 0) row('Freight', fmt.format(_freight ?? 0)),
        if (brokerAmt > 0) row('Broker commission (${_commission ?? 0}%)', fmt.format(brokerAmt)),
        const SizedBox(height: 6),
        row('Grand total', fmt.format(grand), bold: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
        child: FilledButton(
          onPressed: () {
            setState(() {
              _step = 2;
              _scheduleDraft();
            });
          },
          child: const Text('Done'),
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
